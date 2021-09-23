Imports System

Public Module Class2048
    Private rand As Random = New Random()
    Const ROW_MASK As ULong = &HFFFFUL
    Const COL_MASK As ULong = &HF000F000F000FUL
    Const TABLESIZE As Integer = 65536
    Private row_table As UShort() = New UShort(TABLESIZE - 1) {}
    Private score_table As UInteger() = New UInteger(TABLESIZE - 1) {}
    Delegate Function get_move_func_t(board As ULong) As Integer
    Const UP As Integer = 0
    Const DOWN As Integer = 1
    Const LEFT As Integer = 2
    Const RIGHT As Integer = 3
    Const RETRACT As Integer = 4

    Private Function unif_random(n As Integer) As Integer
        Return rand.Next(n)
    End Function

    Private Sub clear_screen()
        Console.Clear()
    End Sub

    Private Function get_ch() As Char
        Return Console.ReadKey(True).KeyChar
    End Function

    Private Function unpack_col(row As UShort) As ULong
        Dim tmp As ULong = row
        Return (tmp Or (tmp << 12) Or (tmp << 24) Or (tmp << 36)) And COL_MASK
    End Function

    Private Function reverse_row(row As UShort) As UShort
        Return (row >> 12) Or ((row >> 4) And &HF0) Or ((row << 4) And &HF00) Or (row << 12)
    End Function

    Private Sub print_board(board As ULong)
        Console.WriteLine("-----------------------------")
        For i As Integer = 0 To 3
            For j As Integer = 0 To 3
                Dim power_val As Integer = board And &HFUL
                If power_val = 0 Then
                    Console.Write("|{0,6}", " "c)
                Else
                    Console.Write("|{0,6}", 1 << power_val)
                End If
                board >>= 4
            Next
            Console.WriteLine("|")
        Next
        Console.WriteLine("-----------------------------")
    End Sub

    Private Function transpose(x As ULong) As ULong
        Dim a1 As ULong = x And &HF0F00F0FF0F00F0FUL
        Dim a2 As ULong = x And &HF0F00000F0F0UL
        Dim a3 As ULong = x And &HF0F00000F0F0000UL
        Dim a As ULong = a1 Or (a2 << 12) Or (a3 >> 12)
        Dim b1 As ULong = a And &HFF00FF0000FF00FFUL
        Dim b2 As ULong = a And &HFF00FF00000000UL
        Dim b3 As ULong = a And &HFF00FF00UL
        Return (b1 Or (b2 >> 24) Or (b3 << 24))
    End Function

    Private Function count_empty(x As ULong) As Integer
        x = x Or ((x >> 2) And &H3333333333333333UL)
        x = x Or (x >> 1)
        x = (Not x) And &H1111111111111111UL
        x += x >> 32
        x += x >> 16
        x += x >> 8
        x += x >> 4
        Return x And &HF
    End Function

    Private Sub init_tables()
        Dim row As UShort = 0
        Dim result As UShort = 0
        Dim line As UShort() = New UShort(3) {}

        Do
            Dim i As Integer = 0, j As Integer = 0
            Dim score As UInteger = 0
            line(0) = row And &HF
            line(1) = (row >> 4) And &HF
            line(2) = (row >> 8) And &HF
            line(3) = (row >> 12) And &HF

            While i < 4
                Dim rank As Integer = line(i)
                If rank >= 2 Then
                    score += (rank - 1) * (1 << rank)
                End If
                i += 1
            End While
            score_table(row) = score

            i = 0
            While i < 3
                j = i + 1
                While j < 4
                    If line(j) <> 0 Then Exit While
                    j += 1
                End While
                If j = 4 Then Exit While

                If line(i) = 0 Then
                    line(i) = line(j)
                    line(j) = 0
                    i -= 1
                ElseIf line(i) = line(j) Then
                    If line(i) <> &HF Then
                        line(i) += 1
                    End If
                    line(j) = 0
                End If
                i += 1
            End While
            result = line(0) Or (line(1) << 4) Or (line(2) << 8) Or (line(3) << 12)
            row_table(row) = row Xor result

            row += 1
        Loop While row <> (TABLESIZE - 1)
    End Sub

    Private Function execute_move_col(board As ULong, _move As Integer) As ULong
        Dim ret As ULong = board
        Dim t As ULong = transpose(board)
        If _move = UP Then
            ret = ret Xor unpack_col(row_table(t And ROW_MASK))
            ret = ret Xor (unpack_col(row_table((t >> 16) And ROW_MASK)) << 4)
            ret = ret Xor (unpack_col(row_table((t >> 32) And ROW_MASK)) << 8)
            ret = ret Xor (unpack_col(row_table((t >> 48) And ROW_MASK)) << 12)
        ElseIf _move = DOWN Then
            ret = ret Xor unpack_col(reverse_row(row_table(reverse_row(t And ROW_MASK))))
            ret = ret Xor (unpack_col(reverse_row(row_table(reverse_row((t >> 16) And ROW_MASK)))) << 4)
            ret = ret Xor (unpack_col(reverse_row(row_table(reverse_row((t >> 32) And ROW_MASK)))) << 8)
            ret = ret Xor (unpack_col(reverse_row(row_table(reverse_row((t >> 48) And ROW_MASK)))) << 12)
        End If
        Return ret
    End Function

    Private Function execute_move_row(board As ULong, _move As Integer ) As ULong
        Dim ret As ULong = board
        If _move = LEFT Then
            ret = ret Xor CULng(row_table(board And ROW_MASK))
            ret = ret Xor (CULng(row_table((board >> 16) And ROW_MASK)) << 16)
            ret = ret Xor (CULng(row_table((board >> 32) And ROW_MASK)) << 32)
            ret = ret Xor (CULng(row_table((board >> 48) And ROW_MASK)) << 48)
        ElseIf _move = RIGHT Then
            ret = ret Xor CULng(reverse_row(row_table(reverse_row(board And ROW_MASK))))
            ret = ret Xor (CULng(reverse_row(row_table(reverse_row((board >> 16) And ROW_MASK)))) << 16)
            ret = ret Xor (CULng(reverse_row(row_table(reverse_row((board >> 32) And ROW_MASK)))) << 32)
            ret = ret Xor (CULng(reverse_row(row_table(reverse_row((board >> 48) And ROW_MASK)))) << 48)
        End If
        Return ret
    End Function

    Private Function execute_move(_move As Integer, board As ULong) As ULong
        If _move = UP OrElse _move = DOWN Then
            Return execute_move_col(board, _move)
        ElseIf _move = LEFT OrElse _move = RIGHT Then
            Return execute_move_row(board, _move)
        Else
            Return &HFFFFFFFFFFFFFFFFUL
        End If
    End Function

    Private Function score_helper(board As ULong) As UInteger
        Return score_table(board And ROW_MASK) + score_table(board >> 16 And ROW_MASK) + score_table(board >> 32 And ROW_MASK) + score_table(board >> 48 And ROW_MASK)
    End Function

    Private Function score_board(board As ULong) As UInteger
        Return score_helper(board)
    End Function

    Private Function ask_for_move(board As ULong) As Integer
        print_board(board)
        While True
            Const allmoves As String = "wsadkjhl"
            Dim pos As Integer = 0
            Dim movechar As Char = get_ch()

            If movechar = "q"c Then
                Return -1
            ElseIf movechar = "r"c Then
                Return RETRACT
            End If
            pos = allmoves.IndexOf(movechar)
            If pos <> -1 Then
                Return pos Mod 4
            End If
        End While
    End Function

    Private Function draw_tile() As ULong
        If unif_random(10) < 9 Then
            Return 1
        Else
            Return 2
        End If
    End Function

    Private Function insert_tile_rand(board As ULong, tile As ULong) As ULong
        Dim index As Integer = unif_random(count_empty(board))
        Dim tmp As ULong = board

        While True
            While (tmp And &HFUL) <> 0
                tmp >>= 4
                tile <<= 4
            End While
            If index = 0 Then Exit While
            index -= 1
            tmp >>= 4
            tile <<= 4
        End While
        Return board Or tile
    End Function

    Private Function initial_board() As ULong
        Dim board As ULong = CULng((draw_tile())) << (unif_random(16) << 2)
        Return insert_tile_rand(board, draw_tile())
    End Function

    Private Sub play_game(get_move As get_move_func_t)
        Dim board As ULong = initial_board()
        Dim scorepenalty As Integer = 0
        Dim last_score As Integer = 0, current_score As Integer = 0, moveno As Integer = 0
        Const MAX_RETRACT As Integer = 64
        Dim retract_vec As ULong() = New ULong(MAX_RETRACT - 1) {}
        Dim retract_penalty_vec As Byte() = New Byte(MAX_RETRACT - 1) {}
        Dim retract_pos As Integer = 0, retract_num As Integer = 0

        While True
            Dim _move As Integer = 0
            Dim tile As ULong = 0
            Dim newboard As ULong
            clear_screen()

            For _move = 0 To 3
                If execute_move(_move, board) <> board Then Exit For
            Next

            If _move = 4 Then Exit While
            current_score = CInt(score_board(board) - scorepenalty)
            moveno += 1
            Console.WriteLine("Move #{0}, current score={1}(+{2})", moveno, current_score, current_score - last_score)
            last_score = current_score
            _move = get_move(board)
            If _move < 0 Then Exit While

            If _move = RETRACT Then
                If moveno <= 1 OrElse retract_num <= 0 Then
                    moveno -= 1
                    Continue While
                End If
                moveno -= 2
                If retract_pos = 0 AndAlso retract_num > 0 Then retract_pos = MAX_RETRACT
                retract_pos -= 1
                board = retract_vec(retract_pos)
                scorepenalty -= retract_penalty_vec(retract_pos)
                retract_num -= 1
                Continue While
            End If

            newboard = execute_move(_move, board)
            If newboard = board Then
                moveno -= 1
                Continue While
            End If

            tile = draw_tile()
            If tile = 2 Then
                scorepenalty += 4
                retract_penalty_vec(retract_pos) = 4
            Else
                retract_penalty_vec(retract_pos) = 0
            End If
            retract_vec(retract_pos) = board
            retract_pos += 1
            If retract_pos = MAX_RETRACT Then retract_pos = 0
            If retract_num < MAX_RETRACT Then retract_num += 1
            board = insert_tile_rand(newboard, tile)
        End While

        print_board(board)
        Console.WriteLine("Game over. Your score is {0}.", current_score)
    End Sub

    Sub Main(args As String())
        init_tables()
        play_game(New get_move_func_t(AddressOf ask_for_move))
    End Sub
End Module
