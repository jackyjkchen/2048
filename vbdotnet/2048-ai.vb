Imports System
Imports System.Collections.Generic
Imports System.Threading

Public Module Game2048
    Private rand As Random = New Random()
    Const ROW_MASK As ULong = &HFFFFUL
    Const COL_MASK As ULong = &HF000F000F000FUL
    Const TABLESIZE As Integer = 65536
    Private row_table As UShort() = New UShort(TABLESIZE - 1) {}
    Private score_table As UInteger() = New UInteger(TABLESIZE - 1) {}
    Private score_heur_table As Double() = New Double(TABLESIZE - 1) {}
    Delegate Function get_move_func_t(board As ULong) As Integer
    Const UP As Integer = 0
    Const DOWN As Integer = 1
    Const LEFT As Integer = 2
    Const RIGHT As Integer = 3

    Friend Structure trans_table_entry_t
        Public depth As Integer
        Public heuristic As Double

        Public Sub New(depth As Byte, heuristic As Double)
            Me.depth = depth
            Me.heuristic = heuristic
        End Sub
    End Structure

    Friend Class eval_state
        Public trans_table As Dictionary(Of ULong, trans_table_entry_t) = New Dictionary(Of ULong, trans_table_entry_t)()
        Public maxdepth As Integer
        Public curdepth As Integer
        Public nomoves As Integer
        Public tablehits As Integer
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

    Private Function unif_random(n As Integer) As Integer
        Return rand.Next(n)
    End Function

    Private Sub clear_screen()
        Console.Clear()
    End Sub

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
            score_heur_table(row) = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges - SCORE_MONOTONICITY_WEIGHT * Math.Min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum

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

    Private Function score_heur_helper(board As ULong) As Double
        Return score_heur_table(board And ROW_MASK) + score_heur_table(board >> 16 And ROW_MASK) + score_heur_table(board >> 32 And ROW_MASK) + score_heur_table(board >> 48 And ROW_MASK)
    End Function

    Private Function score_board(board As ULong) As UInteger
        Return score_helper(board)
    End Function

    Private Function score_heur_board(board As ULong) As Double
        Return score_heur_helper(board) + score_heur_helper(transpose(board))
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

    Private Function count_distinct_tiles(board As ULong) As Integer
        Dim bitset As UShort = 0
        While board <> 0
            bitset = bitset Or (CUShort(1) << (board And &HFUL))
            board >>= 4
        End While

        If bitset <= 3072 Then
            Return 2
        End If
        bitset >>= 1
        Dim count As Integer = 0
        While bitset <> 0
            bitset = bitset And (bitset - 1)
            count += 1
        End While

        Return count
    End Function

    Private Function score_tilechoose_node(ByRef state As eval_state, board As ULong, cprob As Double) As Double
        If cprob < CPROB_THRESH_BASE OrElse state.curdepth >= state.depth_limit Then
            state.maxdepth = Math.Max(state.curdepth, state.maxdepth)
            state.tablehits += 1
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

    Private Function score_move_node(ByRef state As eval_state, board As ULong, cprob As Double) As Double
        Dim best As Double = 0.0F
        state.curdepth += 1
        Dim _move As Integer = 0

        While _move < 4
            Dim newboard As ULong = execute_move(_move, board)
            state.moves_evaled += 1
            If board <> newboard Then
                best = Math.Max(best, score_tilechoose_node(state, newboard, cprob))
            Else
                state.nomoves += 1
            End If
            _move += 1
        End While

        state.curdepth -= 1
        Return best
    End Function

    Private Function _score_toplevel_move(ByRef state As eval_state, board As ULong, _move As Integer) As Double
        Dim newboard As ULong = execute_move(_move, board)
        If board = newboard Then Return 0.0F
        Return score_tilechoose_node(state, newboard, 1.0F) + 0.000001F
    End Function

    Private Function score_toplevel_move(board As ULong, _move As Integer) As Double
        Dim res As Double = 0.0F
        Dim state As eval_state = New eval_state()
        state.depth_limit = Math.Max(3, count_distinct_tiles(board) - 2)
        res = _score_toplevel_move(state, board, _move)
        Console.WriteLine("Move {0}: result {1}: eval'd {2} moves ({3} no moves, {4} table hits, {5} cache hits, {6} cache size) (maxdepth={7})", _move, res, state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, state.trans_table.Count, state.maxdepth)
        Return res
    End Function

    Friend Class thrd_context
        Public board As UInt64
        Public _move As Integer
        Public res As Double
        Public ev As AutoResetEvent = New AutoResetEvent(False)
    End Class

    Private Sub thrd_worker(state As Object)
        Dim context As thrd_context = state
        context.res = score_toplevel_move(context.board, context._move)
        context.ev.Set()
    End Sub

    Private Function find_best_move(board As ULong) As Integer
        Dim best As Double = 0.0F
        Dim bestmove As Integer = -1
        print_board(board)
        Console.WriteLine("Current scores: heur {0}, actual {1}", CUInt(score_heur_board(board)), score_board(board))

        Dim context As thrd_context() = New thrd_context(3) {}
        For _move As Integer = 0 To 3
            context(_move) = New thrd_context()
            context(_move).board = board
            context(_move)._move = _move
            context(_move).res = 0.0F
            ThreadPool.QueueUserWorkItem(AddressOf thrd_worker, context(_move))
        Next
        For _move As Integer = 0 To 3
            context(_move).ev.WaitOne()
            If context(_move).res > best Then
                best = context(_move).res
                bestmove = _move
            End If
        Next

        Console.WriteLine("Selected bestmove: {0}, result: {1}", bestmove, best)
        Return bestmove
    End Function

    Private Sub play_game(get_move As get_move_func_t)
        Dim board As ULong = initial_board()
        Dim scorepenalty As Integer = 0
        Dim last_score As Integer = 0, current_score As Integer = 0, moveno As Integer = 0

        init_tables()
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

            newboard = execute_move(_move, board)
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

    Sub Main(args As String())
        play_game(New get_move_func_t(AddressOf find_best_move))
    End Sub
End Module
