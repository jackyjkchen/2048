      program main_2048

      call main()
      stop
      end

      subroutine init_num()
        integer*8 :: ZF0F00F0F
        integer*8 :: ZFF00FF00
        integer*8 :: t8_1, t8_2

        integer*8 :: ROW_MASK, COL_MASK
        common /MASK_NUM/ ROW_MASK, COL_MASK

        integer*2 :: Z000F, Z00F0, Z0F00
        common /CONST_NUM/  Z000F, Z00F0, Z0F00

        integer*8 :: ZF0F00F0FF0F00F0F, Z0000F0F00000F0F0,
     & Z0F0F00000F0F0000, ZFF00FF0000FF00FF
        integer*8 :: Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111
        common /LARGE_NUM1/ ZF0F00F0FF0F00F0F, Z0000F0F00000F0F0,
     & Z0F0F00000F0F0000, ZFF00FF0000FF00FF
        common /LARGE_NUM2/ Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111

        ROW_MASK = 65535

        t8_1 = 983055
        COL_MASK = ior(ishft(t8_1, 32), t8_1)

        Z000F = 15
        Z00F0 = 240
        Z0F00 = 3840

        t8_1 = 61680
        t8_2 = 3855
        ZF0F00F0F = ior(ishft(t8_1, 16), t8_2)

        t8_1 = 65280
        ZFF00FF00 = ior(ishft(t8_1, 16), t8_1) 

        ZF0F00F0FF0F00F0F = ior(ishft(ZF0F00F0F, 32), ZF0F00F0F)

        t8_1 = 61680
        Z0000F0F00000F0F0 = ior(ishft(t8_1, 32), t8_1)

        t8_1 = 252641280
        Z0F0F00000F0F0000 = ior(ishft(t8_1, 32), t8_1)

        t8_1 = 16711935
        ZFF00FF0000FF00FF = ior(ishft(ZFF00FF00, 32), t8_1)

        t8_1 = 16711935
        Z00FF00FF00000000 = ishft(t8_1, 32)

        Z00000000FF00FF00 = ZFF00FF00

        t8_1 = 858993459
        Z3333333333333333 = ior(ishft(t8_1, 32), t8_1)

        t8_1 = 286331153
        Z1111111111111111 = ior(ishft(t8_1, 32), t8_1)
      end

      integer*4 function unif_random(n)
        integer*4 :: n
        external c_rand
        integer*4 :: c_rand

        unif_random = mod(c_rand(), n)
        return
      end

      integer*8 function unpack_col(row)
        integer*2 :: row
        integer*8 :: t0, t1, t2, t3

        integer*8 :: ROW_MASK, COL_MASK
        common /MASK_NUM/ ROW_MASK, COL_MASK

        t0 = row
        t0 = iand(t0, ROW_MASK)
        t1 = ishft(t0, 12)
        t2 = ishft(t0, 24)
        t3 = ishft(t0, 36)

        unpack_col = iand(ior(ior(ior(t0, t1), t2), t3), COL_MASK)
        return
      end

      integer*2 function reverse_row(row)
        integer*2 :: row
        integer*2 :: t0, t1, t2, t3

        integer*2 :: Z000F, Z00F0, Z0F00
        common /CONST_NUM/  Z000F, Z00F0, Z0F00

        t0 = ishft(row, -12)
        t1 = iand(ishft(row, -4), Z00F0)
        t2 = iand(ishft(row, 4), Z0F00)
        t3 = ishft(row, 12)

        reverse_row = ior(ior(ior(t0, t1), t2), t3)
        return
      end

      subroutine print_board(board)
        integer*8 :: board
        integer*8 :: board_, t_
        integer*2 :: i, j, power_val

        integer*2 :: Z000F, Z00F0, Z0F00
        common /CONST_NUM/  Z000F, Z00F0, Z0F00

        board_ = board
        t_ = Z000F
        write(*, *) '-----------------------------'
        do i = 0, 3
          do j = 0, 3
            power_val = iand(board_, t_)

            if (power_val == 0) then
              write(*, '(a, "      ", $)') '|'
            else
              write(*, '(a, i6, $)')
     & '|', ishft(1, power_val)
            end if
            board_ = ishft(board_, -4)
          end do
          write(*, '(a)') '|'
        end do
        write(*, *) '-----------------------------'
        return
      end

      integer*8 function transpose_board(x)
        integer*8 :: x
        integer*8 :: a1, a2, a3, a, b1, b2, b3

        integer*8 :: ZF0F00F0FF0F00F0F, Z0000F0F00000F0F0,
     & Z0F0F00000F0F0000, ZFF00FF0000FF00FF
        integer*8 :: Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111
        common /LARGE_NUM1/ ZF0F00F0FF0F00F0F, Z0000F0F00000F0F0,
     & Z0F0F00000F0F0000, ZFF00FF0000FF00FF
        common /LARGE_NUM2/ Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111

        a1 = iand(x, ZF0F00F0FF0F00F0F)
        a2 = iand(x, Z0000F0F00000F0F0)
        a3 = iand(x, Z0F0F00000F0F0000)
        a = ior(ior(a1, ishft(a2, 12)), ishft(a3, -12))
        b1 = iand(a, ZFF00FF0000FF00FF)
        b2 = iand(a, Z00FF00FF00000000)
        b3 = iand(a, Z00000000FF00FF00)

        transpose_board = ior(ior(b1, ishft(b2, -24)), ishft(b3, 24))
        return
      end function transpose_board

      integer*4 function count_empty(x)
        integer*8 :: x
        integer*8 :: x_, t_

        integer*2 :: Z000F, Z00F0, Z0F00
        common /CONST_NUM/  Z000F, Z00F0, Z0F00
        integer*8 :: Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111
        common /LARGE_NUM2/ Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111

        x_ = x
        x_ = ior(x_, iand(ishft(x_, -2), Z3333333333333333))
        x_ = ior(x_, ishft(x_, -1))
        x_ = iand(not(x_), Z1111111111111111)
        x_ = x_ + ishft(x_, -32)
        x_ = x_ + ishft(x_, -16)
        x_ = x_ + ishft(x_, -8)
        x_ = x_ + ishft(x_, -4)
        t_ = Z000F
        count_empty = iand(x_, t_)
        return
      end

      integer*2 function execute_move_helper(row)
        integer*2 :: row
        integer*2 :: i, j, t0, t1, t2, t3
        integer*2 :: row_line(0:3)

        integer*2 :: Z000F, Z00F0, Z0F00
        common /CONST_NUM/  Z000F, Z00F0, Z0F00

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
        return
      end

      integer*8 function execute_move_col(board, move)
        integer*8 :: board
        integer*4 :: move
        integer*8 :: ret, t
        integer*2 :: row, rev_row, i

        integer*8 :: transpose_board, unpack_col
        integer*2 :: reverse_row, execute_move_helper

        integer*8 :: ROW_MASK, COL_MASK
        common /MASK_NUM/ ROW_MASK, COL_MASK

        ret = board
        t = transpose_board(board)
        do i = 0, 3
          row = iand(ishft(t, -ishft(i, 4)), ROW_MASK)
          if (move == 0) then
            ret = ieor(ret, ishft(unpack_col(
     & ieor(row, execute_move_helper(row))), ishft(i, 2)))
          else if (move == 1) then
            rev_row = reverse_row(row)
            ret = ieor(ret, ishft(unpack_col(ieor(row, reverse_row(
     & execute_move_helper(rev_row)))), ishft(i, 2)))
          end if
        end do
        execute_move_col = ret
      end

      integer*8 function execute_move_row(board, move)
        integer*8 :: board
        integer*4 :: move
        integer*8 :: ret, t
        integer*2 :: row, rev_row, i

        integer*2 :: reverse_row, execute_move_helper

        integer*8 :: ROW_MASK, COL_MASK
        common /MASK_NUM/ ROW_MASK, COL_MASK

        ret = board
        t = 0
        do i = 0, 3
          row = iand(ishft(board, -ishft(i, 4)), ROW_MASK)
          if (move == 2) then
            t = ieor(row, execute_move_helper(row))
          else if (move == 3) then
            rev_row = reverse_row(row)
            t = ieor(row, reverse_row(execute_move_helper(rev_row)))
          end if
          t = iand(t, ROW_MASK)
          ret = ieor(ret, ishft(t, ishft(i, 4)))
        end do
        execute_move_row = ret
      end

      integer*8 function execute_move(move, board)
        integer*4 :: move
        integer*8 :: board
        integer*8 :: ret

        integer*8 :: execute_move_col, execute_move_row

        if ((move == 0) .or. (move == 1)) then
          ret = execute_move_col(board, move)
        else if ((move == 2) .or. (move == 3)) then
          ret = execute_move_row(board, move)
        else
          ret = -1
        end if
        execute_move = ret 
        return
      end

      integer*4 function score_helper(board)
        integer*8 :: board
        integer*4 :: score
        integer*2 :: row, row_line(0:3), i, j, rank

        integer*2 :: Z000F, Z00F0, Z0F00
        common /CONST_NUM/  Z000F, Z00F0, Z0F00
        integer*8 :: ROW_MASK, COL_MASK
        common /MASK_NUM/ ROW_MASK, COL_MASK

        score = 0
        do j = 0, 3
          row = iand(ishft(board, -ishft(j, 4)), ROW_MASK)
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
        end do
        score_helper = score
      end

      integer*4 function score_board(board)
        integer*8 :: board

        integer*4 :: score_helper

        score_board = score_helper(board)
      end

      integer*4 function ask_for_move(board)
        integer*8 :: board
        integer*4 :: ret
        character :: movechar
        integer :: pos
        character(len=9) :: allmoves = 'wsadkjhl'

        external c_getch
        integer :: c_getch

        call print_board(board)
        ret = -1
        do while (1 > 0)
          movechar = achar(c_getch())
          if (movechar == 'q') then
            ret = -1
            exit
          end if
          if (movechar == 'r') then
            ret = 5
            exit
          end if
          pos = index(allmoves, movechar)
          if (pos /= 0) then
            ret = mod(pos - 1, 4)
            exit
          end if
        end do
        ask_for_move = ret
        return
      end

      integer*8 function draw_tile()
        integer*4 :: ret

        integer*4 :: unif_random

        ret = unif_random(10)
        if (ret < 9) then
          ret = 1
        else
          ret = 2
        end if
        draw_tile = ret
        return
      end

      integer*8 function insert_tile_rand(board, tile)
        integer*8 :: board
        integer*8 :: tile
        integer*8 :: tile_
        integer*8 :: tmp, t_
        integer*4 :: pos

        integer*4 :: unif_random, count_empty

        integer*2 :: Z000F, Z00F0, Z0F00
        common /CONST_NUM/  Z000F, Z00F0, Z0F00

        tile_ = tile
        pos = unif_random(count_empty(board))
        tmp = board
        t_ = Z000F
        do while (1>0)
          do while (iand(tmp, t_) /= 0)
            tmp = ishft(tmp, -4)
            tile_ = ishft(tile_, 4)
          end do
          if (pos == 0) then
            exit
          end if
          pos = pos - 1
          tmp = ishft(tmp, -4)
          tile_ = ishft(tile_, 4)
        end do
        insert_tile_rand = ior(board, tile_)
        return
      end

      integer*8 function initial_board()
        integer*8 :: board
        integer*4 :: rd
        integer*8 :: tile

        integer*4 :: unif_random
        integer*8 :: draw_tile, insert_tile_rand

        rd = unif_random(16)
        tile = draw_tile()
        board = ishft(tile, ishft(rd, 2))
        tile = draw_tile()
        initial_board = insert_tile_rand(board, tile)
        return
      end

      subroutine play_game()
        integer*8 :: board, newboard, tile
        integer*4 :: scorepenalty, current_score, last_score, moveno
        integer*8 :: retract_vec(0:63)
        integer*1 :: retract_penalty_vec(0:63)
        integer*4 :: retract_pos, retract_num, move

        external c_clear_screen
        integer*8 :: initial_board, execute_move
        integer*8 :: draw_tile, insert_tile_rand
        integer*4 :: score_board, ask_for_move

        board = initial_board()
        scorepenalty = 0
        current_score = 0
        last_score = 0
        moveno = 0
        retract_pos = 0
        retract_num = 0

        do while (1 > 0)
          call c_clear_screen()
          move = 0
          do while (move < 4)
            if (execute_move(move, board) /= board) then
              exit
            end if
            move = move + 1
          end do
          if (move == 4) then
            exit
          end if

          current_score = score_board(board) - scorepenalty
          moveno = moveno + 1
          write(*, '("Move ", i6, ", current score=", i7,
     & "(+", i6, ")")')  moveno, current_score,
     & (current_score - last_score)
          last_score = current_score

          move = ask_for_move(board)
          if (move < 0) then
            exit
          end if

          if (move == 5) then
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
            scorepenalty = 
     & scorepenalty - retract_penalty_vec(retract_pos)
            retract_num = retract_num - 1
            cycle
          end if

          newboard = execute_move(move, board)
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
        write(*, '("Game over. Your score is ", i7, ".")') current_score
        return
      end

      subroutine main()
        external c_term_init, c_term_clear

        call c_term_init()
        call init_num()
        call play_game()
        call c_term_clear()
        return
      end

