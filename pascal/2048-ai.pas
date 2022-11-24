program Game2048;

uses
    {$ifdef MULTI_THREAD}
    {$ifdef unix}
    cthreads,
    cmem,
    {$endif}
    {$endif}
    crt, sysutils, strings, math, generics.collections;

{$macro on}
{$if not defined(FASTMODE)}
{$define FASTMODE := 0}
{$endif}

function unif_random(n : integer) : integer;
begin
    unif_random := random(n);
end;

procedure clear_screen;
begin
    clrscr;
end;

const
    ROW_MASK : qword   = $FFFF;
    COL_MASK : qword   = $000F000F000F000F;
    UP       : integer = 0;
    DOWN     : integer = 1;
    LEFT     : integer = 2;
    RIGHT    : integer = 3;

function unpack_col(row : word) : qword;
var
    tmp : qword;
begin
    tmp := row;
    unpack_col := (tmp or (tmp shl 12) or (tmp shl 24) or (tmp shl 36)) and COL_MASK;
end;

function reverse_row(row : word): word;
begin
    reverse_row := (row shr 12) or ((row shr 4) and $00F0)  or ((row shl 4) and $0F00) or (row shl 12);
end;

procedure print_board(board : qword);
var
    i, j, power_val : integer;
begin
    writeln('-----------------------------');
    for i := 0 to 3 do begin
        for j := 0 to 3 do begin
            power_val := board and $f;
            if power_val = 0 then
                write(format('|%6c', [' ']))
            else
                write(format('|%6d', [1 shl power_val]));
            board := board shr 4;
        end;
        writeln('|');
    end;
    writeln('-----------------------------');
end;

function transpose(x : qword) : qword;
var
    a1, a2, a3, a, b1, b2, b3 : qword;
begin
    a1 := x and $F0F00F0FF0F00F0F;
    a2 := x and $0000F0F00000F0F0;
    a3 := x and $0F0F00000F0F0000;
    a := a1 or (a2 shl 12) or (a3 shr 12);
    b1 := a and $FF00FF0000FF00FF;
    b2 := a and $00FF00FF00000000;
    b3 := a and $00000000FF00FF00;
    transpose := b1 or (b2 shr 24) or (b3 shl 24);
end;

function count_empty(x : qword) : integer;
begin
    x := x or ((x shr 2) and $3333333333333333);
    x := x or (x shr 1);
    x := (not x) and $1111111111111111;
    x := x + (x shr 32);
    x := x + (x shr 16);
    x := x + (x shr 8);
    x := x + (x shr 4);
    count_empty := x and $f;
end;

const
    SCORE_LOST_PENALTY        : real = 200000.0;
    SCORE_MONOTONICITY_POWER  : real = 4.0;
    SCORE_MONOTONICITY_WEIGHT : real = 47.0;
    SCORE_SUM_POWER           : real = 3.5;
    SCORE_SUM_WEIGHT          : real = 11.0;
    SCORE_MERGES_WEIGHT       : real = 700.0;
    SCORE_EMPTY_WEIGHT        : real = 270.0;
    CPROB_THRESH_BASE         : real = 0.0001;
    CACHE_DEPTH_LIMIT                = 15;

type
{$if FASTMODE <> 0}
    trans_table_entry_t = record
         depth : integer;
         heuristic : real;
    end;
    trans_table_t = specialize TDictionary<qword, trans_table_entry_t>;
{$endif}
    eval_state = record
{$if FASTMODE <> 0}
        trans_table  : trans_table_t;
{$endif}
        maxdepth     : integer;
        curdepth     : integer;
        nomoves      : longint;
        tablehits    : longint;
        cachehits    : longint;
        moves_evaled : longint;
        depth_limit  : integer;
    end;

const
    TABLESIZE = 65536;
type
    row_table_t   =  array[0..(TABLESIZE)-1] of word;
    score_table_t =  array[0..(TABLESIZE)-1] of dword;
    heur_table_t  =  array[0..(TABLESIZE)-1] of real;
var
    row_left_table   : row_table_t;
    row_right_table  : row_table_t;
    score_table      : score_table_t;
    score_heur_table : heur_table_t;

procedure init_tables;
var
    row, row_result, rev_row, rev_result : word;
    i, j        : integer;
    row_line    : array[0..3] of byte;
    score, rank : dword;
    sum         : real;
    empty, merges, prev, counter : dword;
    monotonicity_left, monotonicity_right : real;
begin
    row := 0;
    row_result := 0;
    repeat
        score := 0;
        row_line[0] := row and $f;
        row_line[1] := (row shr 4) and $f;
        row_line[2] := (row shr 8) and $f;
        row_line[3] := (row shr 12) and $f;

        for i := 0 to 3 do begin
            rank := row_line[i];
            if rank >= 2 then
                score := score + ((rank - 1) * (1 shl rank));
        end;
        score_table[row] := score;

        sum := 0.0;
        empty := 0;
        merges := 0;
        prev := 0;
        counter := 0;

        for i := 0 to 3 do begin
            rank := row_line[i];

            sum := sum + power(rank, SCORE_SUM_POWER);
            if rank = 0 then begin
                empty := empty + 1;
            end else begin
                if prev = rank then begin
                    counter := counter + 1;
                end else if counter > 0 then begin
                    merges := merges + 1 + counter;
                    counter := 0;
                end;
                prev := rank;
            end;
        end;
        if counter > 0 then
            merges := merges + 1 + counter;

        monotonicity_left := 0.0;
        monotonicity_right := 0.0;

        for i := 1 to 3 do begin
            if row_line[i - 1] > row_line[i] then
                monotonicity_left := monotonicity_left +
                    power(row_line[i - 1], SCORE_MONOTONICITY_POWER) - power(row_line[i], SCORE_MONOTONICITY_POWER)
            else
                monotonicity_right := monotonicity_right +
                    power(row_line[i], SCORE_MONOTONICITY_POWER) - power(row_line[i - 1], SCORE_MONOTONICITY_POWER);
        end;

        score_heur_table[row] := SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges -
            SCORE_MONOTONICITY_WEIGHT * min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum;

        i := 0;
        while i < 3 do begin
            j := i + 1;
            while j < 4 do begin
                if row_line[j] <> 0 then break;
                j := j + 1;
            end;
            if j = 4 then break;

            if row_line[i] = 0 then begin
                row_line[i] := row_line[j];
                row_line[j] := 0;
                i := i - 1;
            end else if row_line[i] = row_line[j] then begin
                if row_line[i] <> $f then 
                    row_line[i] := row_line[i] + 1;
                row_line[j] := 0;
            end;
            i := i + 1;
        end;
        row_result := row_line[0] or (row_line[1] shl 4) or (row_line[2] shl 8) or (row_line[3] shl 12);

        rev_row := reverse_row(row);
        rev_result := reverse_row(row_result);
        row_left_table[row] := row xor row_result;
        row_right_table[rev_row] := rev_row xor rev_result;

        row := row + 1;
    until row = 0;
end;

function execute_move(board : qword; _move : integer) : qword;
var
    ret : qword;
begin
    ret := board;
    if _move = UP then begin
        board := transpose(board);
        ret := ret xor unpack_col(row_left_table[board and ROW_MASK]);
        ret := ret xor (unpack_col(row_left_table[(board shr 16) and ROW_MASK]) shl 4);
        ret := ret xor (unpack_col(row_left_table[(board shr 32) and ROW_MASK]) shl 8);
        ret := ret xor (unpack_col(row_left_table[(board shr 48) and ROW_MASK]) shl 12);
    end else if _move = DOWN then begin
        board := transpose(board);
        ret := ret xor unpack_col(row_right_table[board and ROW_MASK]);
        ret := ret xor (unpack_col(row_right_table[(board shr 16) and ROW_MASK]) shl 4);
        ret := ret xor (unpack_col(row_right_table[(board shr 32) and ROW_MASK]) shl 8);
        ret := ret xor (unpack_col(row_right_table[(board shr 48) and ROW_MASK]) shl 12);
    end else if _move = LEFT then begin
        ret := ret xor qword(row_left_table[board and ROW_MASK]);
        ret := ret xor (qword(row_left_table[(board shr 16) and ROW_MASK]) shl 16);
        ret := ret xor (qword(row_left_table[(board shr 32) and ROW_MASK]) shl 32);
        ret := ret xor (qword(row_left_table[(board shr 48) and ROW_MASK]) shl 48);
    end else if _move = RIGHT then begin
        ret := ret xor qword(row_right_table[board and ROW_MASK]);
        ret := ret xor (qword(row_right_table[(board shr 16) and ROW_MASK]) shl 16);
        ret := ret xor (qword(row_right_table[(board shr 32) and ROW_MASK]) shl 32);
        ret := ret xor (qword(row_right_table[(board shr 48) and ROW_MASK]) shl 48);
    end;
    execute_move := ret;
end;

function score_helper(board : qword) : dword;
begin
    score_helper := score_table[board and ROW_MASK] + score_table[(board shr 16) and ROW_MASK] +
        score_table[(board shr 32) and ROW_MASK] + score_table[(board shr 48) and ROW_MASK];
end;

function score_heur_helper(board : qword) : real;
begin
    score_heur_helper := score_heur_table[board and ROW_MASK] + score_heur_table[(board shr 16) and ROW_MASK] +
        score_heur_table[(board shr 32) and ROW_MASK] + score_heur_table[(board shr 48) and ROW_MASK];
end;

function score_board(board : qword) : dword;
begin
    score_board := score_helper(board);
end;

function score_heur_board(board : qword) : real;
begin
    score_heur_board := score_heur_helper(board) + score_heur_helper(transpose(board));
end;

function draw_tile : word;
var
    ret : integer;
begin
    ret := unif_random(10);
    if ret < 9 then
        ret := 1
    else
        ret := 2;
    draw_tile := ret;
end;

function insert_tile_rand(board : qword; tile : qword) : qword;
var
    index : integer;
    tmp : qword;
begin
    index := unif_random(count_empty(board));
    tmp := board;
    while true do begin
        while (tmp and $f) <> 0 do begin
            tmp := tmp shr 4;
            tile := tile shl 4;
        end;
        if index = 0 then break;
        index := index - 1;
        tmp := tmp shr 4;
        tile := tile shl 4;
    end;
    insert_tile_rand := board or tile;
end;

function initial_board : qword;
var
    board : qword;
begin
    board := qword((draw_tile) shl (unif_random(16) shl 2));
    initial_board := insert_tile_rand(board, draw_tile);
end;

function get_depth_limit(board : qword) : integer;
var
    bitset    : word;
    max_limit : integer;
    count     : integer;
begin
    bitset := 0;
    max_limit := 0;
    while board <> 0 do begin
        bitset := bitset or (1 shl (board and $f));
        board := board shr 4;
    end;

    if bitset <= 2048 then
        exit(3)
    else if bitset <= 2048 + 1024 then
        max_limit := 4
{$if FASTMODE <> 0}
    else if bitset <= 4096 then
        max_limit := 5
    else if bitset <= 4096 + 1024 then
        max_limit := 6;
{$else}
    else
        max_limit := 5;
{$endif}

    bitset := bitset shr 1;
    count := 0;
    while bitset <> 0 do begin
        bitset := bitset and (bitset - 1);
        count := count + 1;
    end;
    count := count - 2;
    count := max(count, 3);
    if max_limit <> 0 then
        count := min(count, max_limit);
    get_depth_limit := count;
end;

function score_move_node(var state : eval_state; board : qword; cprob : real) : real; forward;

function score_tilechoose_node(var state : eval_state; board : qword; cprob : real) : real;
var
    res   : real;
{$if FASTMODE <> 0}
    entry : trans_table_entry_t;
{$endif}
    tile_2, tmp : qword;
    num_open    : integer;
begin
    if (cprob < CPROB_THRESH_BASE) or (state.curdepth >= state.depth_limit) then begin
        state.maxdepth := max(state.curdepth, state.maxdepth);
        state.tablehits := state.tablehits + 1;
        exit(score_heur_board(board));
    end;
{$if FASTMODE <> 0}
    if state.curdepth < CACHE_DEPTH_LIMIT then begin
        if state.trans_table.ContainsKey(board) then begin
            entry := state.trans_table[board];
            if entry.depth <= state.curdepth then begin
                state.cachehits := state.cachehits + 1;
                exit(entry.heuristic);
            end;
        end;
    end;
{$endif}

    num_open := count_empty(board);
    cprob := cprob / num_open;
    res := 0.0;
    tmp := board;
    tile_2 := 1;
    while tile_2 <> 0 do begin
        if (tmp and $f) = 0 then begin
            res := res + score_move_node(state, board or tile_2, cprob * 0.9) * 0.9;
            res := res + score_move_node(state, board or (tile_2 shl 1), cprob * 0.1) * 0.1;
        end;
        tmp := tmp shr 4;
        tile_2 := tile_2 shl 4;
    end;
    res := res / num_open;

{$if FASTMODE <> 0}
    if state.curdepth < CACHE_DEPTH_LIMIT then begin
        entry.depth := state.curdepth;
        entry.heuristic := res;
        state.trans_table.AddOrSetValue(board, entry);
    end;
{$endif}

    score_tilechoose_node := res;
end;

function score_move_node(var state : eval_state; board : qword; cprob : real) : real;
var
    _move : integer;
    best, tmp : real;
    newboard : qword;
begin
    best := 0.0;
    state.curdepth := state.curdepth + 1;
    for _move := 0 to 3 do begin
        newboard := execute_move(board, _move);
        state.moves_evaled := state.moves_evaled + 1;
        if board <> newboard then begin
            tmp := score_tilechoose_node(state, newboard, cprob);
            if best < tmp then
                best := tmp;
        end else begin
            state.nomoves := state.nomoves + 1;
        end;
    end;
    state.curdepth := state.curdepth - 1;
    score_move_node := best;
end;

function score_toplevel_move(board : qword; _move : integer; var msg : string) : real;
var
    state : eval_state;
    res : real;
    newboard : qword;
begin
{$if FASTMODE <> 0}
    state.trans_table := trans_table_t.Create();
{$endif}
    state.maxdepth := 0;
    state.curdepth := 0;
    state.cachehits := 0;
    state.moves_evaled := 0;
    state.depth_limit := get_depth_limit(board);

    newboard := execute_move(board, _move);
    if board = newboard then
        res := 0.0
    else
        res := score_tilechoose_node(state, newboard, 1.0) + 0.000001;
{$if FASTMODE <> 0}
    msg := format('Move %d: result %f: eval''d %d moves (%d no moves, %d table hits, %d cache hits, %d cache size) (maxdepth=%d)', [_move, res,
           state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, state.trans_table.Count, state.maxdepth]);
    state.trans_table.Free();
{$else}
    msg := format('Move %d: result %f: eval''d %d moves (%d no moves, %d table hits, %d cache hits, %d cache size) (maxdepth=%d)', [_move, res,
           state.moves_evaled, state.nomoves, state.tablehits, state.cachehits, 0, state.maxdepth]);
{$endif}
{$ifndef MULTI_THREAD}
    writeln(msg);
{$endif}
    score_toplevel_move := res;
end;

type
    thrd_context = record
        board : qword;
        _move : integer;
        res : real;
        msg : string;
    end;

function thrd_worker(param : pointer) : ptrint;
var
    pcontext : ^thrd_context;
begin
    pcontext := param;
    pcontext^.res := score_toplevel_move(pcontext^.board, pcontext^._move, pcontext^.msg);
    thrd_worker := 0
end;

function find_best_move(board : qword) : integer;
var
    _move, bestmove : integer;
    best : real;
{$ifdef MULTI_THREAD}
    thrd_ids : array[0..3] of TThreadID;
{$endif}
    context : array[0..3] of thrd_context;
begin
    _move := 0;
    bestmove := -1;
    best := 0.0;

    print_board(board);
    writeln(format('Current scores: heur %d, actual %d', [round(score_heur_board(board)), score_board(board)]));

    for _move := 0 to 3 do begin
        context[_move].board := board;
        context[_move]._move := _move;
        context[_move].res := 0.0;
{$ifdef MULTI_THREAD}
        thrd_ids[_move] := BeginThread(@thrd_worker, @context[_move]);
{$else}
        thrd_worker(@context[_move]);
{$endif}
    end;

    for _move := 0 to 3 do begin
{$ifdef MULTI_THREAD}
        WaitForThreadTerminate(thrd_ids[_move], 2147483647);
        writeln(context[_move].msg);
{$endif}
        if context[_move].res > best then begin
            best := context[_move].res;
            bestmove := _move;
        end;
    end;
    writeln(format('Selected bestmove: %d, result: %f', [bestmove, best]));

    find_best_move := bestmove;
end;

type
    get_move_func_t = function(board : qword) : integer;

procedure play_game(get_move : get_move_func_t);
var
    board               : qword;
    newboard            : qword;
    scorepenalty        : longint;
    current_score       : longint;
    last_score          : longint;
    moveno              : dword;
    _move               : integer;
    tile                : word;
begin
    board := initial_board;
    scorepenalty := 0;
    current_score := 0;
    last_score := 0;
    moveno := 0;

    randomize;
    init_tables;
    while true do begin
        clear_screen;
        _move := 0;
        while _move < 4 do begin
            if execute_move(board, _move) <> board then
                break;
            _move := _move + 1;
        end;
        if _move = 4 then break;

        current_score := score_board(board) - scorepenalty;
        moveno := moveno + 1;
        writeln(format('Move #%d, current score=%d(+%d)', [moveno, current_score, current_score - last_score]));
        last_score := current_score;

        _move := get_move(board);
        if _move < 0 then break;

        newboard := execute_move(board, _move);
        if newboard = board then begin
            moveno := moveno - 1;
            continue;
        end;

        tile := draw_tile;
        if tile = 2 then
            scorepenalty := scorepenalty + 4;

        board := insert_tile_rand(newboard, tile);
    end;
    print_board(board);
    writeln(format('Game over. Your score is %d.', [current_score]));
end;

begin
    play_game(@find_best_move);
end.
