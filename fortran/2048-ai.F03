program Game2048
use, intrinsic :: iso_c_binding, only : c_int, c_long, c_char, c_null_char
implicit none

interface

function c_rand() bind(c, name='c_rand_')
    import :: c_int
    integer(c_int) :: c_rand
end function c_rand

subroutine c_clear_screen() bind(c, name='c_clear_screen_')
end subroutine c_clear_screen

end interface

integer(2) :: row_left_table(-32768:32767)
integer(2) :: row_right_table(-32768:32767)
integer(4) :: score_table(-32768:32767)
integer(4) :: score_heur_table(-32768:32767)

integer(4), parameter :: UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3
integer(8), parameter :: ROW_MASK = int(Z'FFFF', kind=8)
integer(8), parameter :: COL_MASK = int(Z'000F000F000F000F', kind=8)
integer(2), parameter :: Z000F    = int(z'000F', kind=2)
integer(2), parameter :: Z00F0    = int(z'00F0', kind=2)
integer(2), parameter :: Z0F00    = int(z'0F00', kind=2)
! workaround for -frange-check
integer(8), parameter :: ZF0F00F0FF0F00F0F = ior(ishft(int(z'F0F00F0F', kind=8), 32), int(z'F0F00F0F', kind=8))
integer(8), parameter :: Z0000F0F00000F0F0 = int(z'0000F0F00000F0F0', kind=8)
integer(8), parameter :: Z0F0F00000F0F0000 = int(z'0F0F00000F0F0000', kind=8)
integer(8), parameter :: ZFF00FF0000FF00FF = ior(ishft(int(z'FF00FF00', kind=8), 32), int(z'00FF00FF', kind=8))
integer(8), parameter :: Z00FF00FF00000000 = int(z'00FF00FF00000000', kind=8)
integer(8), parameter :: Z00000000FF00FF00 = int(z'00000000FF00FF00', kind=8)
integer(8), parameter :: Z3333333333333333 = int(z'3333333333333333', kind=8)
integer(8), parameter :: Z1111111111111111 = int(z'1111111111111111', kind=8)

real(4), parameter :: SCORE_LOST_PENALTY = 200000.0
real(4), parameter :: SCORE_MONOTONICITY_POWER = 4.0
real(4), parameter :: SCORE_MONOTONICITY_WEIGHT = 47.0
real(4), parameter :: SCORE_SUM_POWER = 3.5
real(4), parameter :: SCORE_SUM_WEIGHT = 11.0
real(4), parameter :: SCORE_MERGES_WEIGHT = 700.0
real(4), parameter :: SCORE_EMPTY_WEIGHT = 270.0
real(4), parameter :: CPROB_THRESH_BASE = 0.0001

type eval_state
    integer(4) :: maxdepth
    integer(4) :: curdepth
    integer(4) :: nomoves
    integer(4) :: tablehits
    integer(4) :: cachehits
    integer(4) :: moves_evaled
    integer(4) :: depth_limit
end type eval_state

call main()

contains

function unif_random(n)
    integer(4), value, intent(in) :: n
    integer(4) :: unif_random

    unif_random = mod(c_rand(), n)
end function unif_random

function unpack_col(row)
    integer(2), value, intent(in) :: row
    integer(8) :: unpack_col, t0, t1, t2, t3

    t0 = iand(int(row, kind=8), ROW_MASK)
    t1 = ishft(t0, 12)
    t2 = ishft(t0, 24)
    t3 = ishft(t0, 36)

    unpack_col = iand(ior(ior(ior(t0, t1), t2), t3), COL_MASK)
end function unpack_col

function reverse_row(row)
    integer(2), value, intent(in) :: row
    integer(2) :: reverse_row, t0, t1, t2, t3

    t0 = ishft(row, -12)
    t1 = iand(ishft(row, -4), Z00F0)
    t2 = iand(ishft(row, 4), Z0F00)
    t3 = ishft(row, 12)

    reverse_row = ior(ior(ior(t0, t1), t2), t3)
end function reverse_row

subroutine print_board(board)
    integer(8), value :: board
    integer(4) :: i, j, power_val

    print *, '-----------------------------'
    do i = 0, 3
        do j = 0, 3
            power_val = iand(board, int(Z000F, kind=8))
            if (power_val == 0) then
                write(*, fmt='(a, 6x)', advance='no') '|'
            else
                write(*, fmt='(a, i6)', advance='no') '|', ishft(1, power_val)
            end if
            board = ishft(board, -4)
        end do
        print *, '|'
    end do
    print *, '-----------------------------'
end subroutine print_board

function transpose_board(x)
    integer(8), value, intent(in) :: x
    integer(8) :: transpose_board, a1, a2, a3, a, b1, b2, b3

    a1 = iand(x, ZF0F00F0FF0F00F0F)
    a2 = iand(x, Z0000F0F00000F0F0)
    a3 = iand(x, Z0F0F00000F0F0000)
    a = ior(ior(a1, ishft(a2, 12)), ishft(a3, -12))
    b1 = iand(a, ZFF00FF0000FF00FF)
    b2 = iand(a, Z00FF00FF00000000)
    b3 = iand(a, Z00000000FF00FF00)

    transpose_board = ior(ior(b1, ishft(b2, -24)), ishft(b3, 24))
end function transpose_board

function count_empty(x)
    integer(8), value :: x
    integer(4) :: count_empty

    x = ior(x, iand(ishft(x, -2), Z3333333333333333))
    x = ior(x, ishft(x, -1))
    x = iand(not(x), Z1111111111111111)
    x = x + ishft(x, -32)
    x = x + ishft(x, -16)
    x = x + ishft(x, -8)
    x = x + ishft(x, -4)
    count_empty = iand(x, int(Z000F, kind=8))
end function count_empty

subroutine init_tables()
    integer(2) :: row, row_result, rev_row, rev_result, t0, t1, t2, t3
    integer(2) :: row_line(0:3)
    integer(4) :: i, j, rank
    integer(4) :: score
    integer(4) :: empty, merges, prev, counter
    real(4) :: sum_, monotonicity_left, monotonicity_right

    row = 0
    row_result = 0
    do row = -32768, 32767
        score = 0
        row_line(0) = iand(row, Z000F)
        row_line(1) = iand(ishft(row, -4), Z000F)
        row_line(2) = iand(ishft(row, -8), Z000F)
        row_line(3) = iand(ishft(row, -12), Z000F)

        do i = 0, 3
            rank = row_line(i)
            if (rank >= 2) then
                score = score + ((rank - 1) * ishft(1, rank))
            end if
        end do
        score_table(row) = score

        sum_ = 0.0
        empty = 0
        merges = 0
        prev = 0
        counter = 0

        do i = 0, 3
            rank = row_line(i)

            sum_ = sum_ + rank ** SCORE_SUM_POWER
            if (rank == 0) then
                empty = empty + 1
            else
                if (prev == rank) then
                    counter = counter + 1
                else if (counter > 0) then
                    merges = merges + 1 + counter
                    counter = 0
                end if
                prev = rank
            end if
        end do
        if (counter > 0) then
            merges = merges + 1 + counter
        end if

        monotonicity_left = 0.0
        monotonicity_right = 0.0
        do i = 1, 3
            if (row_line(i - 1) > row_line(i)) then
                monotonicity_left = monotonicity_left + row_line(i - 1) ** SCORE_MONOTONICITY_POWER - &
                & row_line(i) ** SCORE_MONOTONICITY_POWER
            else
                monotonicity_right = monotonicity_right + row_line(i) ** SCORE_MONOTONICITY_POWER - &
                & row_line(i - 1) ** SCORE_MONOTONICITY_POWER
            end if
        end do
        score_heur_table(row) = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges - &
            & SCORE_MONOTONICITY_WEIGHT * min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum_

        i = 0
        do while (i < 3)
            j = i + 1
            do while (j < 4)
                if (row_line(j) /= 0) then
                    exit
                end if
                j = j + 1
            end do
            if (j == 4) then
                exit
            end if
            if (row_line(i) == 0) then
                row_line(i) = row_line(j)
                row_line(j) = 0
                i = i - 1
            else if (row_line(i) == row_line(j)) then
                if (row_line(i) /= 15) then
                    row_line(i) = row_line(i) + 1
                end if
                row_line(j) = 0
            end if
            i = i + 1
        end do

        t0 = row_line(0)
        t1 = ishft(row_line(1), 4)
        t2 = ishft(row_line(2), 8)
        t3 = ishft(row_line(3), 12)
        row_result = ior(ior(ior(t0, t1), t2), t3)

        rev_row = reverse_row(row)
        rev_result = reverse_row(row_result)
        row_left_table(row) = ieor(row, row_result)
        row_right_table(rev_row) = ieor(rev_row, rev_result)

        if (row == 32767) then
            exit
        end if
    end do
end subroutine init_tables

function execute_move(board, move)
    integer(8), value, intent(in) :: board
    integer(4), value, intent(in) :: move
    integer(8) :: execute_move
    integer(8) :: ret, t

    ret = board
    if (move == UP) then
        t = transpose_board(board)
        ret = ieor(ret, unpack_col(row_left_table(int(iand(t, ROW_MASK), kind=2))))
        ret = ieor(ret, ishft(unpack_col(row_left_table(int(iand(ishft(t, -16), ROW_MASK), kind=2))), 4))
        ret = ieor(ret, ishft(unpack_col(row_left_table(int(iand(ishft(t, -32), ROW_MASK), kind=2))), 8))
        ret = ieor(ret, ishft(unpack_col(row_left_table(int(iand(ishft(t, -48), ROW_MASK), kind=2))), 12))
    else if (move == DOWN) then
        t = transpose_board(board)
        ret = ieor(ret, unpack_col(row_right_table(int(iand(t, ROW_MASK), kind=2))))
        ret = ieor(ret, ishft(unpack_col(row_right_table(int(iand(ishft(t, -16), ROW_MASK), kind=2))), 4))
        ret = ieor(ret, ishft(unpack_col(row_right_table(int(iand(ishft(t, -32), ROW_MASK), kind=2))), 8))
        ret = ieor(ret, ishft(unpack_col(row_right_table(int(iand(ishft(t, -48), ROW_MASK), kind=2))), 12))
    else if (move == LEFT) then
        t = board
        ret = ieor(ret, iand(int((row_left_table(int(iand(t, ROW_MASK), kind=2))), kind=8), ROW_MASK))
        ret = ieor(ret, ishft(iand(int((row_left_table(int(iand(ishft(t, -16), ROW_MASK), kind=2))), kind=8), ROW_MASK), 16))
        ret = ieor(ret, ishft(iand(int((row_left_table(int(iand(ishft(t, -32), ROW_MASK), kind=2))), kind=8), ROW_MASK), 32))
        ret = ieor(ret, ishft(iand(int((row_left_table(int(iand(ishft(t, -48), ROW_MASK), kind=2))), kind=8), ROW_MASK), 48))
    else if (move == RIGHT) then
        t = board
        ret = ieor(ret, iand(int((row_right_table(int(iand(t, ROW_MASK), kind=2))), kind=8), ROW_MASK))
        ret = ieor(ret, ishft(iand(int((row_right_table(int(iand(ishft(t, -16), ROW_MASK), kind=2))), kind=8), ROW_MASK), 16))
        ret = ieor(ret, ishft(iand(int((row_right_table(int(iand(ishft(t, -32), ROW_MASK), kind=2))), kind=8), ROW_MASK), 32))
        ret = ieor(ret, ishft(iand(int((row_right_table(int(iand(ishft(t, -48), ROW_MASK), kind=2))), kind=8), ROW_MASK), 48))
    end if
    execute_move = ret
end function execute_move

function score_helper(board)
    integer(8), value, intent(in) :: board
    integer(4) :: score_helper
    integer(4) :: t0, t1, t2, t3

    t0 = score_table(int(iand(board, ROW_MASK), kind=2))
    t1 = score_table(int(iand(ishft(board, -16), ROW_MASK), kind=2))
    t2 = score_table(int(iand(ishft(board, -32), ROW_MASK), kind=2))
    t3 = score_table(int(iand(ishft(board, -48), ROW_MASK), kind=2))
    score_helper = t0 + t1 + t2 + t3
end function score_helper

function score_heur_helper(board)
    integer(8), value, intent(in) :: board
    integer(4) :: score_heur_helper
    integer(4) :: t0, t1, t2, t3

    t0 = score_heur_table(int(iand(board, ROW_MASK), kind=2))
    t1 = score_heur_table(int(iand(ishft(board, -16), ROW_MASK), kind=2))
    t2 = score_heur_table(int(iand(ishft(board, -32), ROW_MASK), kind=2))
    t3 = score_heur_table(int(iand(ishft(board, -48), ROW_MASK), kind=2))
    score_heur_helper = t0 + t1 + t2 + t3
end function score_heur_helper

function score_board(board)
    integer(8), value, intent(in) :: board
    integer(4) :: score_board

    score_board = score_helper(board)
end function score_board

function score_heur_board(board)
    integer(8), value, intent(in) :: board
    integer(4) :: score_heur_board
    integer(4) :: t0, t1

    t0 = score_heur_helper(board)
    t1 = score_heur_helper(transpose_board(board))
    score_heur_board = t0 + t1
end function score_heur_board

function draw_tile()
    integer(8) :: draw_tile
    integer(4) :: ret

    ret = unif_random(10)
    if (ret < 9) then
        ret = 1
    else
        ret = 2
    end if
    draw_tile = ret
end function draw_tile

function insert_tile_rand(board, tile)
    integer(8), value, intent(in) :: board
    integer(8), value :: tile
    integer(8) :: insert_tile_rand
    integer(8) :: tmp
    integer(4) :: pos

    pos = unif_random(count_empty(board))
    tmp = board
    do while (1>0)
        do while (iand(tmp, int(Z000F, kind=8)) /= 0)
            tmp = ishft(tmp, -4)
            tile = ishft(tile, 4)
        end do
        if (pos == 0) then
            exit
        end if
        pos = pos - 1
        tmp = ishft(tmp, -4)
        tile = ishft(tile, 4)
    end do
    insert_tile_rand = ior(board, tile)
end function insert_tile_rand

function initial_board()
    integer(8) :: initial_board
    integer(8) :: board
    integer(4) :: rd
    integer(8) :: tile

    rd = unif_random(16)
    tile = draw_tile()
    board = ishft(tile, ishft(rd, 2))
    tile = draw_tile()
    initial_board = insert_tile_rand(board, tile)
end function initial_board

function get_depth_limit(board)
    integer(8), value :: board
    integer(4) :: get_depth_limit
    integer(2) :: bitset
    integer(4) :: count_, max_limit

    bitset = 0
    max_limit = 0
    count_ = 0
    do while (board /= 0)
        bitset = ior(bitset, int(ishft(1, iand(board, int(Z000F, kind=8))), kind=2))
        board = ishft(board, -4)
    end do

    if (bitset <= 2048) then
        get_depth_limit = 3
        return
    else if (bitset <= 2048 + 1024) then
        max_limit = 4
    else
        max_limit = 5
    end if

    bitset = ishft(bitset, -1)
    do while (bitset /= 0)
        bitset = iand(bitset, bitset - int(1, kind=2))
        count_ = count_ + 1
    end do
    count_ = count_ - 2
    count_ = max(count_, 3)
    count_ = min(count_, max_limit)
    get_depth_limit = count_
end function get_depth_limit

function score_tilechoose_node(state, board, cprob)
    type(eval_state) :: state
    integer(8), value, intent(in) :: board
    real(4), value :: cprob
    real(4) :: score_tilechoose_node
    integer(4) :: num_open
    real(4) :: res
    integer(8) :: tmp, tile_2

    if ((cprob < CPROB_THRESH_BASE) .or. (state%curdepth >= state%depth_limit)) then
        state%maxdepth = max(state%curdepth, state%maxdepth)
        state%tablehits = state%tablehits + 1
        score_tilechoose_node = score_heur_board(board)
        return
    end if

    num_open = count_empty(board)
    cprob = cprob / num_open
    res = 0.0
    tmp = board
    tile_2 = 1

    do while (tile_2 /= 0)
        if (iand(tmp, int(Z000F, kind=8)) == 0) then
            res = res + score_move_node(state, ior(board, tile_2), cprob * 0.9) * 0.9
            res = res + score_move_node(state, ior(board, ishft(tile_2, 1)), cprob * 0.1) * 0.1
        end if
        tmp = ishft(tmp, -4)
        tile_2 = ishft(tile_2, 4)
    end do
    res = res / num_open

    score_tilechoose_node = res
end function score_tilechoose_node

function score_move_node(state, board, cprob)
    type(eval_state) :: state
    integer(8), value, intent(in) :: board
    real(4), value, intent(in) :: cprob
    real(4) :: score_move_node
    real(4) :: best, tmp
    integer(4) :: move
    integer(8) :: newboard

    best = 0.0
    state%curdepth = state%curdepth + 1
    do move = 0, 3
        newboard = execute_move(board, move)
        state%moves_evaled = state%moves_evaled + 1
        if (board /= newboard) then
            tmp = score_tilechoose_node(state, newboard, cprob)
            if (best < tmp) then
                best = tmp
            end if
        else
            state%nomoves = state%nomoves + 1
        end if
    end do
    state%curdepth = state%curdepth - 1

    score_move_node = best
end function score_move_node

function score_toplevel_move_(state, board, move)
    type(eval_state) :: state
    integer(8), value, intent(in) :: board
    integer(4), value, intent(in) :: move
    real(4) :: score_toplevel_move_
    integer(8) :: newboard

    newboard = execute_move(board, move)

    if (board == newboard) then
        score_toplevel_move_ = 0.0
    else
        score_toplevel_move_ = score_tilechoose_node(state, newboard, 1.0) + 1e-6
    endif
end function score_toplevel_move_

function score_toplevel_move(board, move)
    integer(8), value, intent(in) :: board
    integer(4), value, intent(in) :: move
    real(4) :: score_toplevel_move
    type(eval_state) :: state
    real(4) :: res

    state%maxdepth = 0
    state%curdepth = 0
    state%nomoves = 0
    state%tablehits = 0
    state%cachehits = 0
    state%moves_evaled = 0
    state%depth_limit = get_depth_limit(board)

    res = score_toplevel_move_(state, board, move)

    print '("Move ", i0, ": result ", f0.0, ": eval''d ", i0, " moves (", i0, " no moves, ", i0, &
        & " table hits, ", i0, " cache hits, ", i0, " cache size) (maxdepth=", i0, ")")', &
        & move, res, state%moves_evaled, state%nomoves, state%tablehits, state%cachehits, 0, state%maxdepth

    score_toplevel_move = res
end function score_toplevel_move

function find_best_move(board)
    integer(8), value, intent(in) :: board
    integer(4) :: find_best_move
    integer(4) :: move, bestmove
    real(4) :: best
    real(4) :: res(0:3)

    move = 0
    best = 0.0
    bestmove = -1

    call print_board(board)
    print '("Current scores: heur ", i0, ", actual ", i0)', score_heur_board(board), score_board(board)

!$omp parallel do
    do move = 0, 3
        res(move) = score_toplevel_move(board, move)
    end do

    do move = 0, 3
        if (res(move) > best) then
            best = res(move)
            bestmove = move
        end if
    end do
    print '("Selected bestmove: ", i0, ", result: ", f0.0)', bestmove, best

    find_best_move = bestmove
end function find_best_move

subroutine play_game()
    integer(8) :: board, newboard, tile
    integer(4) :: scorepenalty, current_score, last_score, moveno, move

    board = initial_board()
    scorepenalty = 0
    current_score = 0
    last_score = 0
    moveno = 0

    call init_tables()
    do while (1 > 0)
        call c_clear_screen()
        move = 0
        do while (move < 4)
            if (execute_move(board, move) /= board) then
                exit
            end if
            move = move + 1
        end do
        if (move == 4) then
            exit
        end if

        current_score = score_board(board) - scorepenalty
        moveno = moveno + 1
        print '("Move ", i0, ", current score=", i0, "(+", i0, ")")', moveno, current_score, (current_score - last_score)
        last_score = current_score

        move = find_best_move(board)
        if (move < 0) then
            exit
        end if

        newboard = execute_move(board, move)
        if (newboard == board) then
            moveno = moveno - 1
            cycle
        end if

        tile = draw_tile()
        if (tile == 2) then
            scorepenalty = scorepenalty + 4
        end if
        board = insert_tile_rand(newboard, tile)
    end do
    call print_board(board)
    print '("Game over. Your score is ", i0, ".")', current_score
end subroutine play_game

subroutine main()
    call play_game()
end subroutine main

end program Game2048
