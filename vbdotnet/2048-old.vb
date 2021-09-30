Imports System

Public Module Game2048
    Private rand As Random = New Random
    Const ROW_MASK As Long = &HFFFFL
    Const COL_MASK As Long = &HF000F000F000FL
    Const TABLESIZE As Integer = 65536
    Private row_table As Integer() = New Integer(TABLESIZE - 1) {}
    Private score_table As Integer() = New Integer(TABLESIZE - 1) {}
    Const UP As Integer = 0
    Const DOWN As Integer = 1
    Const LEFT As Integer = 2
    Const RIGHT As Integer = 3
    Const RETRACT As Integer = 4

    Private Function unif_random(ByVal n As Integer) As Integer
        Return rand.Next(n)
    End Function

    Private Declare Function system Lib "msvcrt" (ByVal cmd As String) As Integer
    Private Sub clear_screen()
        system("cls")
    End Sub

    Private Declare Function _getch Lib "msvcrt" () As Integer
    Private Function get_ch() As Char
        Return Microsoft.VisualBasic.ChrW(_getch())
    End Function

    Private Function unpack_col(ByVal row As Integer) As Long
        Dim tmp As Long = row
        Return (tmp Or (tmp << 12) Or (tmp << 24) Or (tmp << 36)) And COL_MASK
    End Function

    Private Function reverse_row(ByVal row As Integer) As Integer
        row = row And &HFFFF
        Return ((row >> 12) Or ((row >> 4) And &HF0) Or ((row << 4) And &HF00) Or (row << 12)) And &HFFFF
    End Function

    Private Sub print_board(ByVal board As Long)
        Console.WriteLine("-----------------------------")
        For i As Integer = 0 To 3
            For j As Integer = 0 To 3
                Dim power_val As Integer = board And &HFL
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

    Private Function transpose(ByVal x As Long) As Long
        Dim a1 As Long = x And &HF0F00F0FF0F00F0FL
        Dim a2 As Long = x And &HF0F00000F0F0L
        Dim a3 As Long = x And &HF0F00000F0F0000L
        Dim a As Long = a1 Or (a2 << 12) Or (a3 >> 12)
        Dim b1 As Long = a And &HFF00FF0000FF00FFL
        Dim b2 As Long = a And &HFF00FF00000000L
        Dim b3 As Long = a And &HFF00FF00L
        Return (b1 Or (b2 >> 24) Or (b3 << 24))
    End Function

    Private Function count_empty(ByVal x As Long) As Integer
        x = x Or ((x >> 2) And &H3333333333333333L)
        x = x Or (x >> 1)
        x = (Not x) And &H1111111111111111L
        x += x >> 32
        x += x >> 16
        x += x >> 8
        x += x >> 4
        Return x And &HF
    End Function

    Private Sub init_tables()
        Dim row As Integer = 0
        Dim result As Integer = 0
        Dim line As Integer() = New Integer(3) {}

        Do
            Dim i As Integer = 0, j As Integer = 0
            Dim score As Integer = 0
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
        Loop While row <> &HFFFF
    End Sub

    Private Function execute_move(ByVal board As Long, ByVal move As Integer) As Long
        Dim ret As Long = board
        If move = UP Then
            board = transpose(board)
            ret = ret Xor unpack_col(row_table(board And ROW_MASK))
            ret = ret Xor (unpack_col(row_table((board >> 16) And ROW_MASK)) << 4)
            ret = ret Xor (unpack_col(row_table((board >> 32) And ROW_MASK)) << 8)
            ret = ret Xor (unpack_col(row_table((board >> 48) And ROW_MASK)) << 12)
        ElseIf move = DOWN Then
            board = transpose(board)
            ret = ret Xor unpack_col(reverse_row(row_table(reverse_row(board And ROW_MASK))))
            ret = ret Xor (unpack_col(reverse_row(row_table(reverse_row((board >> 16) And ROW_MASK)))) << 4)
            ret = ret Xor (unpack_col(reverse_row(row_table(reverse_row((board >> 32) And ROW_MASK)))) << 8)
            ret = ret Xor (unpack_col(reverse_row(row_table(reverse_row((board >> 48) And ROW_MASK)))) << 12)
        ElseIf move = LEFT Then
            ret = ret Xor CLng(row_table(board And ROW_MASK))
            ret = ret Xor (CLng(row_table((board >> 16) And ROW_MASK)) << 16)
            ret = ret Xor (CLng(row_table((board >> 32) And ROW_MASK)) << 32)
            ret = ret Xor (CLng(row_table((board >> 48) And ROW_MASK)) << 48)
        ElseIf move = RIGHT Then
            ret = ret Xor CLng(reverse_row(row_table(reverse_row(board And ROW_MASK))))
            ret = ret Xor (CLng(reverse_row(row_table(reverse_row((board >> 16) And ROW_MASK)))) << 16)
            ret = ret Xor (CLng(reverse_row(row_table(reverse_row((board >> 32) And ROW_MASK)))) << 32)
            ret = ret Xor (CLng(reverse_row(row_table(reverse_row((board >> 48) And ROW_MASK)))) << 48)
        End If
        Return ret
    End Function

    Private Function score_helper(ByVal board As Long) As Integer
        Return score_table(board And ROW_MASK) + score_table(board >> 16 And ROW_MASK) + score_table(board >> 32 And ROW_MASK) + score_table(board >> 48 And ROW_MASK)
    End Function

    Private Function score_board(ByVal board As Long) As Integer
        Return score_helper(board)
    End Function

    Private Function draw_tile() As Long
        If unif_random(10) < 9 Then
            Return 1
        Else
            Return 2
        End If
    End Function

    Private Function insert_tile_rand(ByVal board As Long, ByVal tile As Long) As Long
        Dim index As Integer = unif_random(count_empty(board))
        Dim tmp As Long = board

        While True
            While (tmp And &HFL) <> 0
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

    Private Function initial_board() As Long
        Dim board As Long = CLng((draw_tile())) << (unif_random(16) << 2)
        Return insert_tile_rand(board, draw_tile())
    End Function

    Private Function ask_for_move(ByVal board As Long) As Integer
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
        Return -1
    End Function

    Private Sub play_game()
        Dim board As Long = initial_board()
        Dim scorepenalty As Integer = 0
        Dim last_score As Integer = 0, current_score As Integer = 0, moveno As Integer = 0
        Const MAX_RETRACT As Integer = 64
        Dim retract_vec As Long() = New Long(MAX_RETRACT - 1) {}
        Dim retract_penalty_vec As Byte() = New Byte(MAX_RETRACT - 1) {}
        Dim retract_pos As Integer = 0, retract_num As Integer = 0

        init_tables()
        While True
            Dim move As Integer = 0
            Dim tile As Long = 0
            Dim newboard As Long
            clear_screen()

            For move = 0 To 3
                If execute_move(board, move) <> board Then Exit For
            Next

            If move = 4 Then Exit While
            current_score = CInt(score_board(board) - scorepenalty)
            moveno += 1
            Console.WriteLine("Move #{0}, current score={1}(+{2})", moveno, current_score, current_score - last_score)
            last_score = current_score
            move = ask_for_move(board)
            If move < 0 Then Exit While

            Do
                If move = RETRACT Then
                    If moveno <= 1 OrElse retract_num <= 0 Then
                        moveno -= 1
                        Exit Do
                    End If
                    moveno -= 2
                    If retract_pos = 0 AndAlso retract_num > 0 Then retract_pos = MAX_RETRACT
                    retract_pos -= 1
                    board = retract_vec(retract_pos)
                    scorepenalty -= retract_penalty_vec(retract_pos)
                    retract_num -= 1
                    Exit Do
                End If

                newboard = execute_move(board, move)
                If newboard = board Then
                    moveno -= 1
                    Exit Do
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
            Loop While False
        End While

        print_board(board)
        Console.WriteLine("Game over. Your score is {0}.", current_score)
    End Sub

    Sub Main(ByVal args As String())
        play_game()
    End Sub
End Module
