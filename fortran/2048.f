      PROGRAM GAME2048

      CALL MAIN()
      STOP
      END

      SUBROUTINE INIT_NUM()
        INTEGER*8 :: ZF0F00F0F
        INTEGER*8 :: ZFF00FF00
        INTEGER*8 :: T8_1, T8_2
        INTEGER*8 :: ROW_MASK, COL_MASK
        COMMON /MASK_NUM/ ROW_MASK, COL_MASK
        INTEGER*2 :: Z000F, Z00F0, Z0F00
        COMMON /CONST_NUM/  Z000F, Z00F0, Z0F00
        INTEGER*8 :: ZF0F00F0FF0F00F0F, Z0000F0F00000F0F0,
     & Z0F0F00000F0F0000, ZFF00FF0000FF00FF
        INTEGER*8 :: Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111
        COMMON /LARGE_NUM1/ ZF0F00F0FF0F00F0F, Z0000F0F00000F0F0,
     & Z0F0F00000F0F0000, ZFF00FF0000FF00FF
        COMMON /LARGE_NUM2/ Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111

        ROW_MASK = 65535
        T8_1 = 983055
        COL_MASK = IOR(ISHFT(T8_1, 32), T8_1)

        Z000F = 15
        Z00F0 = 240
        Z0F00 = 3840

        T8_1 = 61680
        T8_2 = 3855
        ZF0F00F0F = IOR(ISHFT(T8_1, 16), T8_2)
        T8_1 = 65280
        ZFF00FF00 = IOR(ISHFT(T8_1, 16), T8_1) 

        ZF0F00F0FF0F00F0F = IOR(ISHFT(ZF0F00F0F, 32), ZF0F00F0F)
        T8_1 = 61680
        Z0000F0F00000F0F0 = IOR(ISHFT(T8_1, 32), T8_1)
        T8_1 = 252641280
        Z0F0F00000F0F0000 = IOR(ISHFT(T8_1, 32), T8_1)
        T8_1 = 16711935
        ZFF00FF0000FF00FF = IOR(ISHFT(ZFF00FF00, 32), T8_1)
        T8_1 = 16711935
        Z00FF00FF00000000 = ISHFT(T8_1, 32)
        Z00000000FF00FF00 = ZFF00FF00
        T8_1 = 858993459
        Z3333333333333333 = IOR(ISHFT(T8_1, 32), T8_1)
        T8_1 = 286331153
        Z1111111111111111 = IOR(ISHFT(T8_1, 32), T8_1)
      END

      INTEGER*4 FUNCTION UNIF_RANDOM(N)
        INTEGER*4 :: N
        EXTERNAL c_rand
        INTEGER*4 :: c_rand

        UNIF_RANDOM = MOD(c_rand(), N)
      END

      INTEGER*8 FUNCTION UNPACK_COL(ROW)
        INTEGER*2 :: ROW
        INTEGER*8 :: T0, T1, T2, T3
        INTEGER*8 :: ROW_MASK, COL_MASK
        COMMON /MASK_NUM/ ROW_MASK, COL_MASK

        T0 = ROW
        T0 = IAND(T0, ROW_MASK)
        T1 = ISHFT(T0, 12)
        T2 = ISHFT(T0, 24)
        T3 = ISHFT(T0, 36)

        UNPACK_COL = IAND(IOR(IOR(IOR(T0, T1), T2), T3), COL_MASK)
      END

      INTEGER*2 FUNCTION REVERSE_ROW(ROW)
        INTEGER*2 :: ROW
        INTEGER*2 :: T0, T1, T2, T3
        INTEGER*2 :: Z000F, Z00F0, Z0F00
        COMMON /CONST_NUM/  Z000F, Z00F0, Z0F00

        T0 = ISHFT(ROW, -12)
        T1 = IAND(ISHFT(ROW, -4), Z00F0)
        T2 = IAND(ISHFT(ROW, 4), Z0F00)
        T3 = ISHFT(ROW, 12)

        REVERSE_ROW = IOR(IOR(IOR(T0, T1), T2), T3)
      END

      SUBROUTINE PRINT_BOARD(BOARD)
        INTEGER*8 :: BOARD
        INTEGER*8 :: BOARD_, T_
        INTEGER*4 :: I, J, POWER_VAL
        INTEGER*2 :: Z000F, Z00F0, Z0F00
        COMMON /CONST_NUM/  Z000F, Z00F0, Z0F00

        BOARD_ = BOARD
        T_ = Z000F
        WRITE(*, *) '-----------------------------'
        DO I = 0, 3
          DO J = 0, 3
            POWER_VAL = IAND(BOARD_, T_)
            IF (POWER_VAL == 0) THEN
              WRITE(*, '(A, "      ", $)') '|'
            ELSE
              WRITE(*, '(A, I6, $)')
     & '|', ISHFT(1, POWER_VAL)
            END IF
            BOARD_ = ISHFT(BOARD_, -4)
          END DO
          WRITE(*, '(A)') '|'
        END DO
        WRITE(*, *) '-----------------------------'
      END

      INTEGER*8 FUNCTION TRANSPOSE_BOARD(X)
        INTEGER*8 :: X
        INTEGER*8 :: A1, A2, A3, A, B1, B2, B3
        INTEGER*8 :: ZF0F00F0FF0F00F0F, Z0000F0F00000F0F0,
     & Z0F0F00000F0F0000, ZFF00FF0000FF00FF
        INTEGER*8 :: Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111
        COMMON /LARGE_NUM1/ ZF0F00F0FF0F00F0F, Z0000F0F00000F0F0,
     & Z0F0F00000F0F0000, ZFF00FF0000FF00FF
        COMMON /LARGE_NUM2/ Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111

        A1 = IAND(X, ZF0F00F0FF0F00F0F)
        A2 = IAND(X, Z0000F0F00000F0F0)
        A3 = IAND(X, Z0F0F00000F0F0000)
        A = IOR(IOR(A1, ISHFT(A2, 12)), ISHFT(A3, -12))
        B1 = IAND(A, ZFF00FF0000FF00FF)
        B2 = IAND(A, Z00FF00FF00000000)
        B3 = IAND(A, Z00000000FF00FF00)

        TRANSPOSE_BOARD = IOR(IOR(B1, ISHFT(B2, -24)), ISHFT(B3, 24))
      END FUNCTION TRANSPOSE_BOARD

      INTEGER*4 FUNCTION COUNT_EMPTY(X)
        INTEGER*8 :: X
        INTEGER*8 :: X_, T_
        INTEGER*2 :: Z000F, Z00F0, Z0F00
        COMMON /CONST_NUM/  Z000F, Z00F0, Z0F00
        INTEGER*8 :: Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111
        COMMON /LARGE_NUM2/ Z00FF00FF00000000, Z00000000FF00FF00,
     & Z3333333333333333, Z1111111111111111

        X_ = X
        X_ = IOR(X_, IAND(ISHFT(X_, -2), Z3333333333333333))
        X_ = IOR(X_, ISHFT(X_, -1))
        X_ = IAND(NOT(X_), Z1111111111111111)
        X_ = X_ + ISHFT(X_, -32)
        X_ = X_ + ISHFT(X_, -16)
        X_ = X_ + ISHFT(X_, -8)
        X_ = X_ + ISHFT(X_, -4)
        T_ = Z000F
        COUNT_EMPTY = IAND(X_, T_)
      END

      INTEGER*2 FUNCTION EXECUTE_MOVE_HELPER(ROW)
        INTEGER*2 :: ROW
        INTEGER*2 :: I, J, T0, T1, T2, T3
        INTEGER*2 :: ROW_LINE(0:3)
        INTEGER*2 :: Z000F, Z00F0, Z0F00
        COMMON /CONST_NUM/  Z000F, Z00F0, Z0F00

        ROW_LINE(0) = IAND(ROW, Z000F)
        ROW_LINE(1) = IAND(ISHFT(ROW, -4), Z000F)
        ROW_LINE(2) = IAND(ISHFT(ROW, -8), Z000F)
        ROW_LINE(3) = IAND(ISHFT(ROW, -12), Z000F)
        I = 0
        DO WHILE (I < 3)
          J = I + 1
          DO WHILE (J < 4)
            IF (ROW_LINE(J) /= 0) THEN
              EXIT
            END IF
            J = J + 1
          END DO
          IF (J == 4) THEN
            EXIT
          END IF
          IF (ROW_LINE(I) == 0) THEN
            ROW_LINE(I) = ROW_LINE(J)
            ROW_LINE(J) = 0
            I = I - 1
          ELSE IF (ROW_LINE(I) == ROW_LINE(J)) THEN
            IF (ROW_LINE(I) /= 15) THEN
              ROW_LINE(I) = ROW_LINE(I) + 1
            END IF
            ROW_LINE(J) = 0
          END IF
          I = I + 1
        END DO
        T0 = ROW_LINE(0)
        T1 = ISHFT(ROW_LINE(1), 4)
        T2 = ISHFT(ROW_LINE(2), 8)
        T3 = ISHFT(ROW_LINE(3), 12)
        EXECUTE_MOVE_HELPER = IOR(IOR(IOR(T0, T1), T2), T3)
      END

      INTEGER*8 FUNCTION EXECUTE_MOVE(BOARD, MOVE)
        INTEGER*8 :: BOARD
        INTEGER*4 :: MOVE
        INTEGER*8 :: RET, T
        INTEGER*2 :: ROW, REV_ROW, I
        INTEGER*8 :: TRANSPOSE_BOARD, UNPACK_COL
        INTEGER*2 :: REVERSE_ROW, EXECUTE_MOVE_HELPER
        INTEGER*8 :: ROW_MASK, COL_MASK
        COMMON /MASK_NUM/ ROW_MASK, COL_MASK

        RET = BOARD
        IF ((MOVE == 0) .OR. (MOVE == 1)) THEN
            T = TRANSPOSE_BOARD(BOARD)
        ELSE
            T = BOARD
        END IF
        DO I = 0, 3
          ROW = IAND(ISHFT(T, -ISHFT(I, 4)), ROW_MASK)
          IF (MOVE == 0) THEN
            RET = IEOR(RET, ISHFT(UNPACK_COL(IEOR(ROW,
     & EXECUTE_MOVE_HELPER(ROW))), ISHFT(I, 2)))
          ELSE IF (MOVE == 1) THEN
            REV_ROW = REVERSE_ROW(ROW)
            RET = IEOR(RET, ISHFT(UNPACK_COL(IEOR(ROW, REVERSE_ROW(
     & EXECUTE_MOVE_HELPER(REV_ROW)))), ISHFT(I, 2)))
          ELSE IF (MOVE == 2) THEN
            RET = IEOR(RET, ISHFT(IAND(IEOR(ROW,
     & EXECUTE_MOVE_HELPER(ROW)), ROW_MASK), ISHFT(I, 4)))
          ELSE IF (MOVE == 3) THEN
            REV_ROW = REVERSE_ROW(ROW)
            RET = IEOR(RET, ISHFT(IAND(IEOR(ROW, REVERSE_ROW(
     & EXECUTE_MOVE_HELPER(REV_ROW))), ROW_MASK), ISHFT(I, 4)))
          END IF
        END DO
        EXECUTE_MOVE = RET
      END

      INTEGER*4 FUNCTION SCORE_HELPER(BOARD)
        INTEGER*8 :: BOARD
        INTEGER*4 :: SCORE, I, J, RANK
        INTEGER*2 :: ROW
        INTEGER*2 :: Z000F, Z00F0, Z0F00
        COMMON /CONST_NUM/  Z000F, Z00F0, Z0F00
        INTEGER*8 :: ROW_MASK, COL_MASK
        COMMON /MASK_NUM/ ROW_MASK, COL_MASK

        SCORE = 0
        DO J = 0, 3
          ROW = IAND(ISHFT(BOARD, -ISHFT(J, 4)), ROW_MASK)
          DO I = 0, 3
            RANK = IAND(ISHFT(ROW, -ISHFT(I, 2)), Z000F)
            IF (RANK >= 2) THEN
              SCORE = SCORE + ((RANK - 1) * ISHFT(1, RANK))
            END IF
          END DO
        END DO
        SCORE_HELPER = SCORE
      END

      INTEGER*4 FUNCTION SCORE_BOARD(BOARD)
        INTEGER*8 :: BOARD
        INTEGER*4 :: SCORE_HELPER

        SCORE_BOARD = SCORE_HELPER(BOARD)
      END

      INTEGER*8 FUNCTION DRAW_TILE()
        INTEGER*4 :: RET
        INTEGER*4 :: UNIF_RANDOM

        RET = UNIF_RANDOM(10)
        IF (RET < 9) THEN
          RET = 1
        ELSE
          RET = 2
        END IF
        DRAW_TILE = RET
      END

      INTEGER*8 FUNCTION INSERT_TILE_RAND(BOARD, TILE)
        INTEGER*8 :: BOARD
        INTEGER*8 :: TILE
        INTEGER*8 :: TILE_
        INTEGER*8 :: TMP, T_
        INTEGER*4 :: POS
        INTEGER*4 :: UNIF_RANDOM, COUNT_EMPTY
        INTEGER*2 :: Z000F, Z00F0, Z0F00
        COMMON /CONST_NUM/  Z000F, Z00F0, Z0F00

        TILE_ = TILE
        POS = UNIF_RANDOM(COUNT_EMPTY(BOARD))
        TMP = BOARD
        T_ = Z000F
        DO WHILE (1>0)
          DO WHILE (IAND(TMP, T_) /= 0)
            TMP = ISHFT(TMP, -4)
            TILE_ = ISHFT(TILE_, 4)
          END DO
          IF (POS == 0) THEN
            EXIT
          END IF
          POS = POS - 1
          TMP = ISHFT(TMP, -4)
          TILE_ = ISHFT(TILE_, 4)
        END DO
        INSERT_TILE_RAND = IOR(BOARD, TILE_)
      END

      INTEGER*8 FUNCTION INITIAL_BOARD()
        INTEGER*8 :: BOARD
        INTEGER*4 :: RD
        INTEGER*8 :: TILE
        INTEGER*4 :: UNIF_RANDOM
        INTEGER*8 :: DRAW_TILE, INSERT_TILE_RAND

        RD = UNIF_RANDOM(16)
        TILE = DRAW_TILE()
        BOARD = ISHFT(TILE, ISHFT(RD, 2))
        TILE = DRAW_TILE()
        INITIAL_BOARD = INSERT_TILE_RAND(BOARD, TILE)
      END

      INTEGER*4 FUNCTION ASK_FOR_MOVE(BOARD)
        INTEGER*8 :: BOARD
        INTEGER*4 :: RET
        CHARACTER :: MOVECHAR
        INTEGER :: POS
        CHARACTER(LEN=9) :: ALLMOVES = 'wsadkjhl'
        EXTERNAL c_getch
        INTEGER :: c_getch

        CALL PRINT_BOARD(BOARD)
        RET = -1
        DO WHILE (1 > 0)
          MOVECHAR = ACHAR(c_getch())
          IF (MOVECHAR == 'q') THEN
            RET = -1
            EXIT
          ELSE IF (MOVECHAR == 'r') THEN
            RET = 5
            EXIT
          END IF
          POS = INDEX(ALLMOVES, MOVECHAR)
          IF (POS /= 0) THEN
            RET = MOD(POS - 1, 4)
            EXIT
          END IF
        END DO
        ASK_FOR_MOVE = RET
      END

      SUBROUTINE PLAY_GAME()
        INTEGER*8 :: BOARD, NEWBOARD, TILE
        INTEGER*4 :: SCOREPENALTY, CURRENT_SCORE, LAST_SCORE, MOVENO
        INTEGER*8 :: RETRACT_VEC(0:63)
        INTEGER*1 :: RETRACT_PENALTY_VEC(0:63)
        INTEGER*4 :: RETRACT_POS, RETRACT_NUM, MOVE
        EXTERNAL c_clear_screen, c_print_move_score, c_print_final_score
        INTEGER*8 :: INITIAL_BOARD, EXECUTE_MOVE
        INTEGER*8 :: DRAW_TILE, INSERT_TILE_RAND
        INTEGER*4 :: SCORE_BOARD, ASK_FOR_MOVE

        BOARD = INITIAL_BOARD()
        SCOREPENALTY = 0
        CURRENT_SCORE = 0
        LAST_SCORE = 0
        MOVENO = 0
        RETRACT_POS = 0
        RETRACT_NUM = 0

        DO WHILE (1 > 0)
          CALL c_clear_screen()
          MOVE = 0
          DO WHILE (MOVE < 4)
            IF (EXECUTE_MOVE(BOARD, MOVE) /= BOARD) THEN
              EXIT
            END IF
            MOVE = MOVE + 1
          END DO
          IF (MOVE == 4) THEN
            EXIT
          END IF

          CURRENT_SCORE = SCORE_BOARD(BOARD) - SCOREPENALTY
          MOVENO = MOVENO + 1
          CALL c_print_move_score(MOVENO, CURRENT_SCORE, LAST_SCORE)
          LAST_SCORE = CURRENT_SCORE

          MOVE = ASK_FOR_MOVE(BOARD)
          IF (MOVE < 0) THEN
            EXIT
          END IF

          IF (MOVE == 5) THEN
            IF ((MOVENO <= 1) .OR. (RETRACT_NUM <= 0)) THEN
              MOVENO = MOVENO - 1
              CYCLE
            END IF
            MOVENO = MOVENO - 2
            IF ((RETRACT_POS == 0) .AND. (RETRACT_NUM > 0)) THEN
              RETRACT_POS = 64
            END IF
            RETRACT_POS = RETRACT_POS - 1
            BOARD = RETRACT_VEC(RETRACT_POS)
            SCOREPENALTY = 
     & SCOREPENALTY - RETRACT_PENALTY_VEC(RETRACT_POS)
            RETRACT_NUM = RETRACT_NUM - 1
            CYCLE
          END IF

          NEWBOARD = EXECUTE_MOVE(BOARD, MOVE)
          IF (NEWBOARD == BOARD) THEN
            MOVENO = MOVENO - 1
            CYCLE
          END IF

          TILE = DRAW_TILE()
          IF (TILE == 2) THEN
            SCOREPENALTY = SCOREPENALTY + 4
            RETRACT_PENALTY_VEC(RETRACT_POS) = 4
          ELSE
            RETRACT_PENALTY_VEC(RETRACT_POS) = 0
          END IF
          RETRACT_VEC(RETRACT_POS) = BOARD
          RETRACT_POS = RETRACT_POS + 1
          IF (RETRACT_POS == 64) THEN
            RETRACT_POS = 0
          END IF
          IF (RETRACT_NUM < 64) THEN
            RETRACT_NUM = RETRACT_NUM + 1
          END IF
          BOARD = INSERT_TILE_RAND(NEWBOARD, TILE)
        END DO
        CALL PRINT_BOARD(BOARD)
        CALL c_print_final_score(CURRENT_SCORE)
      END

      SUBROUTINE MAIN()
        CALL INIT_NUM()
        CALL PLAY_GAME()
      END

