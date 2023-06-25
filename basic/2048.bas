randomize(timer())
Private Const ROW_MASK = &HFFFFULL
Private Const COL_MASK = &HF000F000F000FULL
Private Const TABLESIZE = 65536
Private Dim Shared row_table(TABLESIZE - 1) As UShort
Private Dim Shared score_table(TABLESIZE - 1) As UInteger
Enum MoveAction
    UP_ = 0
    DOWN_
    LEFT_
    RIGHT_
    RETRACT_
End Enum

Private Function unif_random(n As Integer) As Integer
    Return rnd() mod n
End Function

Private Sub clear_screen()
    CLS
End Sub

Private Function get_ch() As ULong
    Return GetKey
End Function

Private Function unpack_col(row As UShort) As ULongint
    Dim tmp As ULongint = row
    Return (tmp Or (tmp Shl 12) Or (tmp Shl 24) Or (tmp Shl 36)) And COL_MASK
End Function

Private Function reverse_row(row As UShort) As UShort
    Return (row Shr 12) Or ((row Shr 4) And &HF0) Or ((row Shl 4) And &HF00) Or (row Shl 12)
End Function

Private Sub print_board(board As ULongint)
    Print "-----------------------------"
    For i As Integer = 0 To 3
        For j As Integer = 0 To 3
            Dim power_val As Integer = board And &HFUL
            If power_val = 0 Then
                Print "|      ";
            Else
                Print Using "|######"; 1 Shl power_val;
            End If
            board = board Shr 4
        Next
        Print "|"
    Next
    Print "-----------------------------"
End Sub

Private Function transpose(x As ULongint) As ULongint
    Dim a1 As ULongint = x And &HF0F00F0FF0F00F0FULL
    Dim a2 As ULongint = x And &HF0F00000F0F0ULL
    Dim a3 As ULongint = x And &HF0F00000F0F0000ULL
    Dim a As ULongint = a1 Or (a2 Shl 12) Or (a3 Shr 12)
    Dim b1 As ULongint = a And &HFF00FF0000FF00FFULL
    Dim b2 As ULongint = a And &HFF00FF00000000ULL
    Dim b3 As ULongint = a And &HFF00FF00ULL
    Return (b1 Or (b2 Shr 24) Or (b3 Shl 24))
End Function

Private Function count_empty(x As ULongint) As Integer
    x = x Or ((x Shr 2) And &H3333333333333333ULL)
    x = x Or (x Shr 1)
    x = (Not x) And &H1111111111111111ULL
    x += x Shr 32
    x += x Shr 16
    x += x Shr 8
    x += x Shr 4
    Return x And &HF
End Function

Private Sub init_tables()
    Dim row As UShort = 0
    Dim result As UShort = 0
    Dim line_(3) As UShort

    Do
        Dim i As Integer = 0, j As Integer = 0
        Dim score As UInteger = 0
        line_(0) = row And &HF
        line_(1) = (row Shr 4) And &HF
        line_(2) = (row Shr 8) And &HF
        line_(3) = (row Shr 12) And &HF

        While i < 4
            Dim rank As Integer = line_(i)
            If rank >= 2 Then
                score += (rank - 1) * (1 Shl rank)
            End If
            i += 1
        Wend
        score_table(row) = score

        i = 0
        While i < 3
            j = i + 1
            While j < 4
                If line_(j) <> 0 Then Exit While
                j += 1
            Wend
            If j = 4 Then Exit While

            If line_(i) = 0 Then
                line_(i) = line_(j)
                line_(j) = 0
                i -= 1
            ElseIf line_(i) = line_(j) Then
                If line_(i) <> &HF Then
                    line_(i) += 1
                End If
                line_(j) = 0
            End If
            i += 1
        Wend
        result = line_(0) Or (line_(1) Shl 4) Or (line_(2) Shl 8) Or (line_(3) Shl 12)
        row_table(row) = row Xor result

        row += 1
    Loop While row <> &HFFFF
End Sub

Private Function execute_move(board As ULongint, move As Integer) As ULongint
    Dim ret As ULongint = board
    If move = MoveAction.UP_ Then
        board = transpose(board)
        ret = ret Xor unpack_col(row_table(board And ROW_MASK))
        ret = ret Xor (unpack_col(row_table((board Shr 16) And ROW_MASK)) Shl 4)
        ret = ret Xor (unpack_col(row_table((board Shr 32) And ROW_MASK)) Shl 8)
        ret = ret Xor (unpack_col(row_table((board Shr 48) And ROW_MASK)) Shl 12)
    ElseIf move = MoveAction.DOWN_ Then
        board = transpose(board)
        ret = ret Xor unpack_col(reverse_row(row_table(reverse_row(board And ROW_MASK))))
        ret = ret Xor (unpack_col(reverse_row(row_table(reverse_row((board Shr 16) And ROW_MASK)))) Shl 4)
        ret = ret Xor (unpack_col(reverse_row(row_table(reverse_row((board Shr 32) And ROW_MASK)))) Shl 8)
        ret = ret Xor (unpack_col(reverse_row(row_table(reverse_row((board Shr 48) And ROW_MASK)))) Shl 12)
    ElseIf move = MoveAction.LEFT_ Then
        ret = ret Xor CULngint(row_table(board And ROW_MASK))
        ret = ret Xor (CULngint(row_table((board Shr 16) And ROW_MASK)) Shl 16)
        ret = ret Xor (CULngint(row_table((board Shr 32) And ROW_MASK)) Shl 32)
        ret = ret Xor (CULngint(row_table((board Shr 48) And ROW_MASK)) Shl 48)
    ElseIf move = MoveAction.RIGHT_ Then
        ret = ret Xor CULngint(reverse_row(row_table(reverse_row(board And ROW_MASK))))
        ret = ret Xor (CULngint(reverse_row(row_table(reverse_row((board Shr 16) And ROW_MASK)))) Shl 16)
        ret = ret Xor (CULngint(reverse_row(row_table(reverse_row((board Shr 32) And ROW_MASK)))) Shl 32)
        ret = ret Xor (CULngint(reverse_row(row_table(reverse_row((board Shr 48) And ROW_MASK)))) Shl 48)
    End If
    Return ret
End Function

Private Function score_helper(board As ULongint) As UInteger
    Return score_table(board And ROW_MASK) + score_table(board Shr 16 And ROW_MASK) + score_table(board Shr 32 And ROW_MASK) + score_table(board Shr 48 And ROW_MASK)
End Function

Private Function score_board(board As ULongint) As UInteger
    Return score_helper(board)
End Function

Private Function draw_tile() As ULongint
    If unif_random(10) < 9 Then
        Return 1
    Else
        Return 2
    End If
End Function

Private Function insert_tile_rand(board As ULongint, tile As ULongint) As ULongint
    Dim index As Integer = unif_random(count_empty(board))
    Dim tmp As ULongint = board

    While 1
        While (tmp And &HFUL) <> 0
            tmp Shr= 4
            tile Shl= 4
        Wend
        If index = 0 Then Exit While
        index -= 1
        tmp Shr= 4
        tile Shl= 4
    Wend
    Return board Or tile
End Function

Private Function initial_board() As ULongint
    Dim board As ULongint = CULngint((draw_tile())) Shl (unif_random(16) Shl 2)
    Return insert_tile_rand(board, draw_tile())
End Function

Private Function ask_for_move(board As ULongint) As Integer
    print_board(board)
    While 1
        Dim allmoves As String = "wsadkjhl"
        Dim pos_ As Integer = 0
        Dim movechar As Byte = get_ch()

        If movechar = Asc("q") Then
            Return -1
        ElseIf movechar = Asc("r") Then
            Return MoveAction.RETRACT_
        End If
        pos_ = InStr(allmoves, String(1, movechar)) - 1
        print pos_
        If pos_ <> -1 Then
            Return pos_ Mod 4
        End If
    Wend
    Return -1
End Function

Private Sub play_game()
    Dim board As ULongint = initial_board()
    Dim scorepenalty As Integer = 0
    Dim last_score As Integer = 0, current_score As Integer = 0, moveno As Integer = 0
    Const MAX_RETRACT = 64
    Dim retract_vec(MAX_RETRACT - 1) As ULongint
    Dim retract_penalty_vec(MAX_RETRACT - 1) As Byte
    Dim retract_pos As Integer = 0, retract_num As Integer = 0

    init_tables()
    While 1
        Dim move As Integer = 0
        Dim tile As ULongint = 0
        Dim newboard As ULongint
        clear_screen()

        For move = 0 To 3
            If execute_move(board, move) <> board Then Exit For
        Next

        If move = 4 Then Exit While
        current_score = CInt(score_board(board) - scorepenalty)
        moveno += 1
        Print Using "Move _#&, current score=&(+&)"; moveno; current_score; current_score - last_score
        last_score = current_score
        move = ask_for_move(board)
        If move < 0 Then Exit While

        If move = MoveAction.RETRACT_ Then
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

        newboard = execute_move(board, move)
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
    Wend

    print_board(board)
    Print Using "Game over. Your score is &."; current_score
End Sub

play_game()
