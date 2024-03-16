randomize(timer())
Private Const ROW_MASK = &HFFFFULL
Private Const COL_MASK = &HF000F000F000FULL
Private Const TABLESIZE = 65536
Private Dim Shared row_left_table(TABLESIZE - 1) As UShort
Private Dim Shared row_right_table(TABLESIZE - 1) As UShort
Private Dim Shared score_table(TABLESIZE - 1) As UInteger
Private Dim Shared score_heur_table(TABLESIZE - 1) As Double
Enum MoveAction
    UP_ = 0
    DOWN_
    LEFT_
    RIGHT_
End Enum

Private Type eval_state
    maxdepth As Integer
    curdepth As Integer
    nomoves As Integer
    tablehits As Integer
    moves_evaled As Integer
    depth_limit As Integer
End Type

Private Const SCORE_LOST_PENALTY = 200000.0F
Private Const SCORE_MONOTONICITY_POWER = 4.0F
Private Const SCORE_MONOTONICITY_WEIGHT = 47.0F
Private Const SCORE_SUM_POWER = 3.5F
Private Const SCORE_SUM_WEIGHT = 11.0F
Private Const SCORE_MERGES_WEIGHT = 700.0F
Private Const SCORE_EMPTY_WEIGHT = 270.0F
Private Const CPROB_THRESH_BASE = 0.0001F
Private Const CACHE_DEPTH_LIMIT = 15

#define min_(a, b) iif((a) < (b), (a), (b))
#define max_(a, b) iif((a) > (b), (a), (b))

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
            Dim fb_Power_val As Integer = board And &HFUL
            If fb_Power_val = 0 Then
                Print "|      ";
            Else
                Print Using "|######"; 1 Shl fb_Power_val;
            End If
            board Shr= 4
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
    Dim rev_row As UShort = 0
    Dim rev_result As UShort = 0
    Dim line_(3) As UShort

    Do
        Dim i As Integer = 0, j As Integer = 0
        Dim score As UInteger = 0
        Dim rank As Integer = 0
        line_(0) = row And &HF
        line_(1) = (row Shr 4) And &HF
        line_(2) = (row Shr 8) And &HF
        line_(3) = (row Shr 12) And &HF

        While i < 4
            rank = line_(i)
            If rank >= 2 Then
                score += (rank - 1) * (1 Shl rank)
            End If
            i += 1
        Wend
        score_table(row) = score

        Dim sum As Double = 0.0F
        Dim empty As Integer = 0
        Dim merges As Integer = 0
        Dim prev As Integer = 0
        Dim counter As Integer = 0
        i = 0
        While i < 4
            rank = line_(i)
            sum += fb_Pow(rank, SCORE_SUM_POWER)

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
        Wend
        If counter > 0 Then
            merges += 1 + counter
        End If

        Dim monotonicity_left As Double = 0.0F
        Dim monotonicity_right As Double = 0.0F
        i = 1
        While i < 4
            If line_(i - 1) > line_(i) Then
                monotonicity_left += (line_(i - 1) ^ SCORE_MONOTONICITY_POWER) - (line_(i) ^ SCORE_MONOTONICITY_POWER)
            Else
                monotonicity_right += (line_(i) ^ SCORE_MONOTONICITY_POWER) - (line_(i - 1) ^ SCORE_MONOTONICITY_POWER)
            End If
            i += 1
        Wend
        score_heur_table(row) = SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges - SCORE_MONOTONICITY_WEIGHT * min_(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum

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

        rev_row = reverse_row(row)
        rev_result = reverse_row(result)
        row_left_table(row) = row Xor result
        row_right_table(rev_row) = rev_row Xor rev_result

        row += 1
    Loop While row <> &HFFFF
End Sub

Private Function execute_move(board As ULongint, move As Integer) As ULongint
    Dim ret As ULongint = board
    If move = MoveAction.UP_ Then
        board = transpose(board)
        ret = ret Xor unpack_col(row_left_table(board And ROW_MASK))
        ret = ret Xor (unpack_col(row_left_table((board Shr 16) And ROW_MASK)) Shl 4)
        ret = ret Xor (unpack_col(row_left_table((board Shr 32) And ROW_MASK)) Shl 8)
        ret = ret Xor (unpack_col(row_left_table((board Shr 48) And ROW_MASK)) Shl 12)
    ElseIf move = MoveAction.DOWN_ Then
        board = transpose(board)
        ret = ret Xor unpack_col(row_right_table(board And ROW_MASK))
        ret = ret Xor (unpack_col(row_right_table((board Shr 16) And ROW_MASK)) Shl 4)
        ret = ret Xor (unpack_col(row_right_table((board Shr 32) And ROW_MASK)) Shl 8)
        ret = ret Xor (unpack_col(row_right_table((board Shr 48) And ROW_MASK)) Shl 12)
    ElseIf move = MoveAction.LEFT_ Then
        ret = ret Xor CULngint(row_left_table(board And ROW_MASK))
        ret = ret Xor (CULngint(row_left_table((board Shr 16) And ROW_MASK)) Shl 16)
        ret = ret Xor (CULngint(row_left_table((board Shr 32) And ROW_MASK)) Shl 32)
        ret = ret Xor (CULngint(row_left_table((board Shr 48) And ROW_MASK)) Shl 48)
    ElseIf move = MoveAction.RIGHT_ Then
        ret = ret Xor CULngint(row_right_table(board And ROW_MASK))
        ret = ret Xor (CULngint(row_right_table((board Shr 16) And ROW_MASK)) Shl 16)
        ret = ret Xor (CULngint(row_right_table((board Shr 32) And ROW_MASK)) Shl 32)
        ret = ret Xor (CULngint(row_right_table((board Shr 48) And ROW_MASK)) Shl 48)
    End If
    Return ret
End Function

Private Function score_helper(board As ULongint) As UInteger
    Return score_table(board And ROW_MASK) + score_table(board Shr 16 And ROW_MASK) + score_table(board Shr 32 And ROW_MASK) + score_table(board Shr 48 And ROW_MASK)
End Function

Private Function score_heur_helper(board As ULongint) As Double
    Return score_heur_table(board And ROW_MASK) + score_heur_table(board Shr 16 And ROW_MASK) + score_heur_table(board Shr 32 And ROW_MASK) + score_heur_table(board Shr 48 And ROW_MASK)
End Function

Private Function score_board(board As ULongint) As UInteger
    Return score_helper(board)
End Function

Private Function score_heur_board(board As ULongint) As Double
    Return score_heur_helper(board) + score_heur_helper(transpose(board))
End Function

Private Function draw_tile() As ULongint
    If unif_random(10) < 9 Then
        Return 1
    Else
        Return 2
    End If
End Function

Private Function get_depth_limit(board As ULongint) As Integer
    Dim bitset_ As UShort = 0
    Dim max_limit As Integer = 3

    While board <> 0
        bitset_ = bitset_ Or (CUShort(1) Shl (board And &HFULL))
        board Shr= 4
    Wend

    If bitset_ <= 2048 Then
        Return max_limit
    ElseIf bitset_ <= 2048 + 1024 Then
        max_limit = 4
    Else
        max_limit = 5
    End If

    bitset_ = bitset_ Shr 1
    Dim count As Integer = 0
    While bitset_ <> 0
        bitset_ = bitset_ And (bitset_ - 1)
        count += 1
    wend
    count -= 2
    count = max_(count, 3)
    count = min_(count, max_limit)
    Return count
End Function

Declare Function score_move_node(ByRef state As eval_state, board As ULongint, cprob As Double) As Double

Private Function score_tilechoose_node(ByRef state As eval_state, board As ULongint, cprob As Double) As Double
    If cprob < CPROB_THRESH_BASE OrElse state.curdepth >= state.depth_limit Then
        state.maxdepth = max_(state.curdepth, state.maxdepth)
        state.tablehits += 1
        Return score_heur_board(board)
    End If

    Dim res As Double = 0.0F
    Dim tmp As ULongint = board
    Dim tile_2 As ULongint = 1
    Dim num_open As Integer = count_empty(board)
    cprob /= num_open

    While tile_2 <> 0
        If (tmp And &HFULL) = 0 Then
            res += score_move_node(state, board Or tile_2, cprob * 0.9F) * 0.9F
            res += score_move_node(state, board Or (tile_2 Shl 1), cprob * 0.1F) * 0.1F
        End If
        tmp Shr= 4
        tile_2 Shl= 4
    Wend

    res = res / num_open

    Return res
End Function

Private Function score_move_node(ByRef state As eval_state, board As ULongint, cprob As Double) As Double
    Dim best As Double = 0.0F
    state.curdepth += 1
    Dim move As Integer = 0

    While move < 4
        Dim newboard As ULongint = execute_move(board, move)

        state.moves_evaled += 1
        If board <> newboard Then
			Dim tmp As Double = score_tilechoose_node(state, newboard, cprob)
            If best < tmp Then
                best = tmp
			End If
        Else
            state.nomoves += 1
        End If
        move += 1
    Wend

    state.curdepth -= 1
    Return best
End Function

Private Function score_toplevel_move(board As ULongint, move As Integer) As Double
    Dim res As Double = 0.0F
    Dim state As eval_state
    Dim newboard As ULongint = execute_move(board, move)
    state.maxdepth = 0
    state.curdepth = 0
    state.nomoves = 0
    state.tablehits = 0
    state.moves_evaled = 0
    state.depth_limit = get_depth_limit(board)
    If board <> newboard Then
        res = score_tilechoose_node(state, newboard, 1.0F) + 0.000001F
    End If
    Print Using "Move &: result &: eval'd & moves (& no moves, & table hits, 0 cache hits, 0 cache size) (maxdepth=&)"; move; res; state.moves_evaled; state.nomoves; state.tablehits; state.maxdepth
    Return res
End Function

Private Function insert_tile_rand(board As ULongint, tile As ULongint) As ULongint
    Dim index As Integer = unif_random(count_empty(board))
    Dim tmp As ULongint = board

    While 1
        While (tmp And &HFULL) <> 0
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

Private Type thrd_context
    board As ULongint
    move As Integer
    res As Double
#ifdef MULTI_THREAD
    thread_id As Any Ptr
#endif
End Type

#ifdef MULTI_THREAD
Private Sub thrd_worker(ByVal state As Any Ptr)
    Dim context As thrd_context Ptr = state
    context->res = score_toplevel_move(context->board, context->move)
End Sub
#endif

Private Function find_best_move(board As ULongint) As Integer
    Dim best As Double = 0.0F
    Dim bestmove As Integer = -1
    Dim move As Integer = 0
    print_board(board)
    Print Using "Current scores: heur &, actual &"; CUInt(score_heur_board(board)); score_board(board)

    Dim context(3) As thrd_context
    For move = 0 To 3
        context(move).board = board
        context(move).move = move
#ifdef MULTI_THREAD
        context(move).thread_id = ThreadCreate(@thrd_worker, @context(move))
#else
        context(move).res = score_toplevel_move(context(move).board, context(move).move)
#endif
    Next

    For move = 0 To 3
#ifdef MULTI_THREAD
        ThreadWait(context(move).thread_id)
#endif
        If context(move).res > best Then
            best = context(move).res
            bestmove = move
        End If
    Next

    Print Using "Selected bestmove: &, result: &"; bestmove; best
    Return bestmove
End Function

Private Sub play_game()
    Dim board As ULongint = initial_board()
    Dim scorepenalty As Integer = 0
    Dim last_score As Integer = 0, current_score As Integer = 0, moveno As Integer = 0
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
        move = find_best_move(board)
        If move < 0 Then Exit While

        newboard = execute_move(board, move)
        If newboard = board Then
            moveno -= 1
            Continue While
        End If

        tile = draw_tile()
        If tile = 2 Then
            scorepenalty += 4
        End If
        board = insert_tile_rand(newboard, tile)
    Wend

    print_board(board)
    Print Using "Game over. Your score is &."; current_score
End Sub

play_game()
