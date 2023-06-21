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

function c_getch() bind(c, name='c_getch_')
    import :: c_int
    integer(c_int) :: c_getch
end function c_getch

#if !defined(FASTMODE)
#define FASTMODE 1
#endif

end interface

#if FASTMODE
integer(2) :: row_table(-32768:32767)
integer(4) :: score_table(-32768:32767)
#endif

integer(4), parameter :: UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3, RETRACT = 4
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

#if FASTMODE
subroutine init_tables()
    integer(2) :: row, row_result, t0, t1, t2, t3
    integer(2) :: row_line(0:3)
    integer(4) :: i, j, rank
    integer(4) :: score

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
        row_table(row) = ieor(row, row_result)

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
        ret = ieor(ret, unpack_col(row_table(int(iand(t, ROW_MASK), kind=2))))
        ret = ieor(ret, ishft(unpack_col(row_table(int(iand(ishft(t, -16), ROW_MASK), kind=2))), 4))
        ret = ieor(ret, ishft(unpack_col(row_table(int(iand(ishft(t, -32), ROW_MASK), kind=2))), 8))
        ret = ieor(ret, ishft(unpack_col(row_table(int(iand(ishft(t, -48), ROW_MASK), kind=2))), 12))
    else if (move == DOWN) then
        t = transpose_board(board)
        ret = ieor(ret, unpack_col(reverse_row(row_table(reverse_row(int(iand(t, ROW_MASK), kind=2))))))
        ret = ieor(ret, ishft(unpack_col(reverse_row(row_table(reverse_row(int(iand(ishft(t, -16), ROW_MASK), kind=2))))), 4))
        ret = ieor(ret, ishft(unpack_col(reverse_row(row_table(reverse_row(int(iand(ishft(t, -32), ROW_MASK), kind=2))))), 8))
        ret = ieor(ret, ishft(unpack_col(reverse_row(row_table(reverse_row(int(iand(ishft(t, -48), ROW_MASK), kind=2))))), 12))
    else if (move == LEFT) then
        t = board
        ret = ieor(ret, iand(int((row_table(int(iand(t, ROW_MASK), kind=2))), kind=8), ROW_MASK))
        ret = ieor(ret, ishft(iand(int((row_table(int(iand(ishft(t, -16), ROW_MASK), kind=2))), kind=8), ROW_MASK), 16))
        ret = ieor(ret, ishft(iand(int((row_table(int(iand(ishft(t, -32), ROW_MASK), kind=2))), kind=8), ROW_MASK), 32))
        ret = ieor(ret, ishft(iand(int((row_table(int(iand(ishft(t, -48), ROW_MASK), kind=2))), kind=8), ROW_MASK), 48))
    else if (move == RIGHT) then
        t = board
        ret = ieor(ret, iand(int(reverse_row(row_table(reverse_row(int(iand(t, ROW_MASK), kind=2)))), kind=8), ROW_MASK))
        ret = ieor(ret, ishft(iand(int(reverse_row(row_table(reverse_row(int(iand(ishft(t, -16), ROW_MASK), kind=2)))), &
              & kind=8), ROW_MASK), 16))
        ret = ieor(ret, ishft(iand(int(reverse_row(row_table(reverse_row(int(iand(ishft(t, -32), ROW_MASK), kind=2)))), &
              & kind=8), ROW_MASK), 32))
        ret = ieor(ret, ishft(iand(int(reverse_row(row_table(reverse_row(int(iand(ishft(t, -48), ROW_MASK), kind=2)))), &
              & kind=8), ROW_MASK), 48))
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
#else
function execute_move_helper(row)
    integer(2), value, intent(in) :: row
    integer(2) :: execute_move_helper
    integer(2) :: i, j, t0, t1, t2, t3
    integer(2) :: row_line(0:3)

    row_line(0) = iand(row, Z000F)
    row_line(1) = iand(ishft(row, -4), Z000F)
    row_line(2) = iand(ishft(row, -8), Z000F)
    row_line(3) = iand(ishft(row, -12), Z000F)
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
    execute_move_helper = ior(ior(ior(t0, t1), t2), t3)
end function execute_move_helper

function execute_move(board, move)
    integer(8), value, intent(in) :: board
    integer(4), value, intent(in) :: move
    integer(8) :: execute_move
    integer(8) :: ret, t
    integer(2) :: row, rev_row, i

    ret = board
    if ((move == UP) .or. (move == DOWN)) then
        t = transpose_board(board)
    else
        t = board
    end if
    do i = 0, 3
        row = int(iand(ishft(t, -ishft(i, 4)), ROW_MASK), kind=2)
        if (move == UP) then
            ret = ieor(ret, ishft(unpack_col(ieor(row, execute_move_helper(row))), ishft(i, 2)))
        else if (move == DOWN) then
            rev_row = reverse_row(row)
            ret = ieor(ret, ishft(unpack_col(ieor(row, reverse_row(execute_move_helper(rev_row)))), ishft(i, 2)))
        else if (move == LEFT) then
            ret = ieor(ret, ishft(iand(int(ieor(row, execute_move_helper(row)), kind=8), ROW_MASK), ishft(i, 4)))
        else if (move == RIGHT) then
            rev_row = reverse_row(row)
            ret = ieor(ret, ishft(iand(int(ieor(row, reverse_row(execute_move_helper(rev_row))), kind=8), ROW_MASK), ishft(i, 4)))
        end if
    end do
    execute_move = ret
end function execute_move

function score_helper(board)
    integer(8), value, intent(in) :: board
    integer(4) :: score_helper
    integer(4) :: score, i, j, rank
    integer(2) :: row

    score = 0
    do j = 0, 3
        row = int(iand(ishft(board, -ishft(j, 4)), ROW_MASK), kind=2)
        do i = 0, 3
            rank = iand(ishft(row, -ishft(i, 2)), Z000F)
            if (rank >= 2) then
                score = score + ((rank - 1) * ishft(1, rank))
            end if
        end do
    end do
    score_helper = score
end function score_helper
#endif

function score_board(board)
    integer(8), value, intent(in) :: board
    integer(4) :: score_board

    score_board = score_helper(board)
end function score_board

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

function ask_for_move(board)
    integer(8), value, intent(in) :: board
    integer(4) :: ask_for_move
    integer(4) :: ret
    character :: movechar
    integer :: pos
    character(len=9) :: allmoves = 'wsadkjhl'

    call print_board(board)
    ret = -1
    do while (1 > 0)
        movechar = achar(c_getch())
        if (movechar == 'q') then
            ret = -1
            exit
        else if (movechar == 'r') then
            ret = RETRACT
            exit
        end if
        pos = index(allmoves, movechar)
        if (pos /= 0) then
            ret = mod(pos - 1, 4)
            exit
        end if
    end do
    ask_for_move = ret
end function ask_for_move

subroutine play_game()
    integer(8) :: board, newboard, tile
    integer(4) :: scorepenalty, current_score, last_score, moveno, move
    integer(8) :: retract_vec(0:63)
    integer(1) :: retract_penalty_vec(0:63)
    integer(4) :: retract_pos, retract_num

    board = initial_board()
    scorepenalty = 0
    current_score = 0
    last_score = 0
    moveno = 0
    retract_pos = 0
    retract_num = 0

#if FASTMODE
    call init_tables()
#endif
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

        move = ask_for_move(board)
        if (move < 0) then
            exit
        end if

        if (move == RETRACT) then
            if ((moveno <= 1) .or. (retract_num <= 0)) then
                moveno = moveno - 1
                cycle
            end if
            moveno = moveno - 2
            if ((retract_pos == 0) .and. (retract_num > 0)) then
                retract_pos = 64
            end if
            retract_pos = retract_pos - 1
            board = retract_vec(retract_pos)
            scorepenalty = scorepenalty - retract_penalty_vec(retract_pos)
            retract_num = retract_num - 1
            cycle
        end if

        newboard = execute_move(board, move)
        if (newboard == board) then
            moveno = moveno - 1
            cycle
        end if

        tile = draw_tile()
        if (tile == 2) then
            scorepenalty = scorepenalty + 4
            retract_penalty_vec(retract_pos) = 4
        else
            retract_penalty_vec(retract_pos) = 0
        end if
        retract_vec(retract_pos) = board
        retract_pos = retract_pos + 1
        if (retract_pos == 64) then
            retract_pos = 0
        end if
        if (retract_num < 64) then
            retract_num = retract_num + 1
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
