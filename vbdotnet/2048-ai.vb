Imports System
Imports System.Collections.Generic

Public Module Class2048
    Private rand As Random = New Random()
    Const ROW_MASK As ULong = &HFFFFUL
    Const COL_MASK As ULong = &HF000F000F000FUL
    Const TABLESIZE As Integer = 65536
    Private row_left_table As UShort() = New UShort(TABLESIZE - 1) {}
    Private row_right_table As UShort() = New UShort(TABLESIZE - 1) {}
    Private score_table As Double() = New Double(TABLESIZE - 1) {}
    Private heur_score_table As Double() = New Double(TABLESIZE - 1) {}
    Delegate Function get_move_func_t(ByVal board As ULong) As Integer
    Const UP As Integer = 0
    Const DOWN As Integer = 1
    Const LEFT As Integer = 2
    Const RIGHT As Integer = 3
    Const RETRACT As Integer = 4

    Friend Structure trans_table_entry_t
        Public depth As Integer
        Public heuristic As Double

        Public Sub New(ByVal depth As Byte, ByVal heuristic As Double)
            Me.depth = depth
            Me.heuristic = heuristic
        End Sub
    End Structure

    Friend Class eval_state
        Public trans_table As Dictionary(Of ULong, trans_table_entry_t) = New Dictionary(Of ULong, trans_table_entry_t)()
        Public maxdepth As Integer
        Public curdepth As Integer
        Public cachehits As Integer
        Public moves_evaled As Integer
        Public depth_limit As Integer
    End Class

    Const SCORE_LOST_PENALTY As Double = 200000.0F
    Const SCORE_MONOTONICITY_POWER As Double = 4.0F
    Const SCORE_MONOTONICITY_WEIGHT As Double = 47.0F
    Const SCORE_SUM_POWER As Double = 3.5F
    Const SCORE_SUM_WEIGHT As Double = 11.0F
    Const SCORE_MERGES_WEIGHT As Double = 700.0F
    Const SCORE_EMPTY_WEIGHT As Double = 270.0F
    Const CPROB_THRESH_BASE As Double = 0.0001F
    Const CACHE_DEPTH_LIMIT As UShort = 15

    Private Function unif_random(ByVal n As Integer) As Integer
        Return rand.Next(n)
    End Function

    Private Sub clear_screen()
        Console.Clear()
    End Sub

    Private Function unpack_col(ByVal row As UShort) As ULong
        Dim tmp As ULong = row
        Return (tmp Or (tmp << 12) Or (tmp << 24) Or (tmp << 36)) And COL_MASK
    End Function

    Private Function reverse_row(ByVal row As UShort) As UShort
        Return (row >> 12) Or ((row >> 4) And &HF0) Or ((row << 4) And &HF00) Or (row << 12)
    End Function

    Private Sub print_board(ByVal board As ULong)
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

    Private Function transpose(ByVal x As ULong) As ULong
        Dim a1 As ULong = x And &HF0F00F0FF0F00F0FUL
        Dim a2 As ULong = x And &HF0F00000F0F0UL
        Dim a3 As ULong = x And &HF0F00000F0F0000UL
        Dim a As ULong = a1 Or (a2 << 12) Or (a3 >> 12)
        Dim b1 As ULong = a And &HFF00FF0000FF00FFUL
        Dim b2 As ULong = a And &HFF00FF00000000UL
        Dim b3 As ULong = a And &HFF00FF00UL
        Return (b1 Or (b2 >> 24) Or (b3 << 24))
    End Function

    Private Function count_empty(ByVal x As ULong) As Integer
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
        Dim row As UShort = 0, rev_row As UShort = 0
        Dim result As UShort = 0, rev_result As UShort = 0
        Dim line As UShort() = New UShort(3) {}

        Do
            Dim i As Integer = 0, j As Integer = 0
            Dim score As Double = 0.0F
            line(0) = (row >> 0) And &HF
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

            Dim sum As Double = 0.0F
            Dim empty As Integer = 0
            Dim merges As Integer = 0
            Dim prev As Integer = 0
            Dim counter As Integer = 0
            i = 0

            While i < 4
                Dim rank As Integer = line(i)
                sum += Math.Pow(rank, SCORE_SUM_POWER)

                If rank = 0 Then
                    empty += 1
                Else
                    If prev = rank Then
                        counter += 1
                    ElseIf counter > 0 Then
                        merges += 1 + counter
                        counter = 0
                    End If
                    prev = rank
                End If

                i += 1
            End While

            If counter > 0 Then
                merges += 1 + counter
            End If

            Dim monotonicity_left As Double = 0.0F
            Dim monotonicity_right As Double = 0.0F
            i = 1

            While i < 4
                If line(i - 1) > line(i) Then
                    monotonicity_left += Math.Pow(line(i - 1), SCORE_MONOTONICITY_POWER) - Math.Pow(line(i), SCORE_MONOTONICITY_POWER)
                Else
                    monotonicity_right += Math.Pow(line(i), SCORE_MONOTONICITY_POWER) - Math.Pow(line(i - 1), SCORE_MONOTONICITY_POWER)
                End If
                i += 1
            End While

            heur_score_table(row) = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges - SCORE_MONOTONICITY_WEIGHT * Math.Min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum
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

            result = (line(0) << 0) Or (line(1) << 4) Or (line(2) << 8) Or (line(3) << 12)
            rev_result = reverse_row(result)
            rev_row = reverse_row(row)
            row_left_table(row) = row Xor result
            row_right_table(rev_row) = rev_row Xor rev_result
            row += 1
        Loop While row <> (TABLESIZE - 1)
    End Sub

    Private Function execute_move_col(ByVal board As ULong, ByRef table As UShort()) As ULong
        Dim ret As ULong = board
        Dim t As ULong = transpose(board)
        ret = ret Xor (unpack_col(table((t >> 0) And ROW_MASK)) << 0)
        ret = ret Xor (unpack_col(table((t >> 16) And ROW_MASK)) << 4)
        ret = ret Xor (unpack_col(table((t >> 32) And ROW_MASK)) << 8)
        ret = ret Xor (unpack_col(table((t >> 48) And ROW_MASK)) << 12)
        Return ret
    End Function

    Private Function execute_move_row(ByVal board As ULong, ByRef table As UShort()) As ULong
        Dim ret As ULong = board
        ret = ret Xor (CULng(table((board >> 0) And ROW_MASK)) << 0)
        ret = ret Xor (CULng(table((board >> 16) And ROW_MASK)) << 16)
        ret = ret Xor (CULng(table((board >> 32) And ROW_MASK)) << 32)
        ret = ret Xor (CULng(table((board >> 48) And ROW_MASK)) << 48)
        Return ret
    End Function

    Private Function execute_move(ByVal move As Integer, ByVal board As ULong) As ULong
        Select Case move
            Case UP
                Return execute_move_col(board, row_left_table)
            Case DOWN
                Return execute_move_col(board, row_right_table)
            Case LEFT
                Return execute_move_row(board, row_left_table)
            Case RIGHT
                Return execute_move_row(board, row_right_table)
            Case Else
                Return &HFFFFFFFFFFFFFFFFUL
        End Select
    End Function

    Private Function count_distinct_tiles(ByVal board As ULong) As Integer
        Dim bitset As ULong = 0
        While board <> 0
            bitset = bitset Or (CULng(1) << (board And &HFUL))
            board >>= 4
        End While

        bitset >>= 1
        Dim count As Integer = 0
        While bitset <> 0
            bitset = bitset And (bitset - 1)
            count += 1
        End While

        Return count
    End Function

    Private Function score_helper(ByVal board As ULong, ByRef table As Double()) As Double
        Return table(board >> 0 And ROW_MASK) + table(board >> 16 And ROW_MASK) + table(board >> 32 And ROW_MASK) + table(board >> 48 And ROW_MASK)
    End Function

    Private Function score_board(ByVal board As ULong) As UInteger
        Return score_helper(board, score_table)
    End Function

    Private Function score_heur_board(ByVal board As ULong) As Double
        Return score_helper(board, heur_score_table) + score_helper(transpose(board), heur_score_table)
    End Function

    Private Function score_tilechoose_node(ByRef state As eval_state, ByVal board As ULong, ByVal cprob As Double) As Double
        If cprob < CPROB_THRESH_BASE OrElse state.curdepth >= state.depth_limit Then
            state.maxdepth = Math.Max(state.curdepth, state.maxdepth)
            Return score_heur_board(board)
        End If

        If state.curdepth < CACHE_DEPTH_LIMIT Then
            If state.trans_table.ContainsKey(board) Then
                Dim entry As trans_table_entry_t = state.trans_table(board)

                If entry.depth <= state.curdepth Then
                    state.cachehits += 1
                    Return entry.heuristic
                End If
            End If
        End If

        Dim num_open As Integer = count_empty(board)
        cprob /= num_open
        Dim res As Double = 0.0F
        Dim tmp As ULong = board
        Dim tile_2 As ULong = 1

        While tile_2 <> 0
            If (tmp And &HFUL) = 0 Then
                res += score_move_node(state, board Or tile_2, cprob * 0.9F) * 0.9F
                res += score_move_node(state, board Or tile_2 << 1, cprob * 0.1F) * 0.1F
            End If
            tmp >>= 4
            tile_2 <<= 4
        End While

        res = res / num_open

        If state.curdepth < CACHE_DEPTH_LIMIT Then
            Dim entry As trans_table_entry_t = New trans_table_entry_t(state.curdepth, res)
            state.trans_table(board) = entry
        End If

        Return res
    End Function

    Private Function score_move_node(ByRef state As eval_state, ByVal board As ULong, ByVal cprob As Double) As Double
        Dim best As Double = 0.0F
        state.curdepth += 1
        Dim move As Integer = 0

        While move < 4
            Dim newboard As ULong = execute_move(move, board)
            state.moves_evaled += 1
            If board <> newboard Then
                best = Math.Max(best, score_tilechoose_node(state, newboard, cprob))
            End If
            move += 1
        End While

        state.curdepth -= 1
        Return best
    End Function

    Private Function _score_toplevel_move(ByRef state As eval_state, ByVal board As ULong, ByVal move As Integer) As Double
        Dim newboard As ULong = execute_move(move, board)
        If board = newboard Then Return 0.0F
        Return score_tilechoose_node(state, newboard, 1.0F) + 0.000001F
    End Function

    Private Function score_toplevel_move(ByVal board As ULong, ByVal move As Integer) As Double
        Dim res As Double = 0.0F
        Dim state As eval_state = New eval_state()
        state.depth_limit = Math.Max(3, count_distinct_tiles(board) - 2)
        res = _score_toplevel_move(state, board, move)
        Console.WriteLine("Move {0}: result {1}: eval'd {2} moves ({3} cache hits, {4} cache size) (maxdepth={5})", move, res, state.moves_evaled, state.cachehits, state.trans_table.Count, state.maxdepth)
        Return res
    End Function

    Private Function find_best_move(ByVal board As ULong) As Integer
        Dim best As Double = 0.0F
        Dim bestmove As Integer = -1
        print_board(board)
        Console.WriteLine("Current scores: heur {0}, actual {1}", CUInt(score_heur_board(board)), score_board(board))

        For move As Integer = 0 To 3
            Dim res As Double = score_toplevel_move(board, move)
            If res > best Then
                best = res
                bestmove = move
            End If
        Next

        Console.WriteLine("Selected bestmove: {0}, result: {1}", bestmove, best)
        Return bestmove
    End Function

    Private Function draw_tile() As ULong
        If unif_random(10) < 9 Then
            Return 1
        Else
            Return 2
        End If
    End Function

    Private Function insert_tile_rand(ByVal board As ULong, ByVal tile As ULong) As ULong
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

    Private Sub play_game(ByVal get_move As get_move_func_t)
        Dim board As ULong = initial_board()
        Dim scorepenalty As Integer = 0
        Dim last_score As Integer = 0, current_score As Integer = 0, moveno As Integer = 0

        While True
            Dim move As Integer = 0
            Dim tile As ULong = 0
            Dim newboard As ULong
            clear_screen()

            For move = 0 To 3
                If execute_move(move, board) <> board Then Exit For
            Next

            If move = 4 Then Exit While
            current_score = CInt(score_board(board) - scorepenalty)
            moveno += 1
            Console.WriteLine("Move #{0}, current score={1}(+{2})", moveno, current_score, current_score - last_score)
            last_score = current_score
            move = get_move(board)
            If move < 0 Then Exit While

            newboard = execute_move(move, board)

            If newboard = board Then
                moveno -= 1
                Continue While
            End If

            tile = draw_tile()

            If tile = 2 Then
                scorepenalty += 4
            End If

            board = insert_tile_rand(newboard, tile)
        End While

        print_board(board)
        Console.WriteLine("Game over. Your score is {0}.", current_score)
    End Sub

    Sub Main(ByVal args As String())
        init_tables()
        play_game(New get_move_func_t(AddressOf find_best_move))
    End Sub
End Module
