program main_2048;

uses crt, sysutils, strings, math, generics.collections;

function unif_random(n : integer) : integer;
begin
    unif_random := random(n);
end;

procedure clear_screen;
begin
    clrscr;
end;

type
    board_t = qword;
    row_t   = word;

const
    ROW_MASK : row_t   = $FFFF;
    COL_MASK : board_t = $000F000F000F000F;
    UP       : integer = 0;
    DOWN     : integer = 1;
    LEFT     : integer = 2;
    RIGHT    : integer = 3;

function unpack_col(row : row_t) : board_t;
var
    tmp : board_t;
begin
    tmp := row;
    unpack_col := (tmp or (tmp shl 12) or (tmp shl 24) or (tmp shl 36)) and COL_MASK;
end;

function reverse_row(row : row_t): row_t;
begin
    reverse_row := (row shr 12) or ((row shr 4) and $00F0)  or ((row shl 4) and $0F00) or (row shl 12);
end;

procedure print_board(board : board_t);
var
    i, j, power_val : integer;
begin
    writeln('-----------------------------');
    for i := 0 to 3 do
    begin
        for j := 0 to 3 do
        begin
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

function transpose(x : board_t) : board_t;
var
    a1, a2, a3, a, b1, b2, b3 : board_t;
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

function count_empty(x : board_t) : integer;
begin
    x := x or ((x shr 2) and $3333333333333333);
    x := x or (x shr 1);
    x := (not x) and $1111111111111111;
    x := x + (x shr 32);
    x := x + (x shr 16);
    x := x + (x shr  8);
    x := x + (x shr  4);
    count_empty := x and $f;
end;

const
    TABLESIZE = 65536;
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
    row_table_t   =  array[0..(TABLESIZE)-1] of word;
    score_table_t =  array[0..(TABLESIZE)-1] of real;

var
    row_left_table   : row_table_t;
    row_right_table  : row_table_t;
    score_table      : score_table_t;
    heur_score_table : score_table_t;

type
    trans_table_entry_t = record
         depth : integer;
         heuristic : real;
    end;
    trans_table_t = specialize TDictionary<board_t, trans_table_entry_t>;
    eval_state = record
        trans_table  : trans_table_t;
        maxdepth     : integer;
        curdepth     : integer;
        cachehits    : longint;
        moves_evaled : longint;
        depth_limit  : integer;
    end;

procedure init_tables;
var
    row, rev_row, row_result, rev_result : row_t;
    i, j, rank : integer;
    row_line   : array[0..3] of byte;
    score      : dword;
    sum        : real;
    empty, merges, prev, counter : integer;
    monotonicity_left, monotonicity_right : real;
begin
    row := 0;
    rev_row := 0;
    row_result := 0;
    rev_result := 0;
    repeat
        score := 0;
        row_line[0] := (row shr  0) and $f;
        row_line[1] := (row shr  4) and $f;
        row_line[2] := (row shr  8) and $f;
        row_line[3] := (row shr 12) and $f;

        for i := 0 to 3 do
        begin
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

        for i := 0 to 3 do
        begin
            rank := row_line[i];

            sum := sum + power(rank, SCORE_SUM_POWER);
            if rank = 0 then
            begin
                empty := empty + 1;
            end else
            begin
                if prev = rank then
                begin
                    counter := counter + 1;
                end
                else if counter > 0 then
                begin
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

        for i := 1 to 3 do
        begin
            if row_line[i - 1] > row_line[i] then
                monotonicity_left := monotonicity_left +
                    power(row_line[i - 1], SCORE_MONOTONICITY_POWER) - power(row_line[i], SCORE_MONOTONICITY_POWER)
            else
                monotonicity_right := monotonicity_right +
                    power(row_line[i], SCORE_MONOTONICITY_POWER) - power(row_line[i - 1], SCORE_MONOTONICITY_POWER);
        end;

        heur_score_table[row] := SCORE_LOST_PENALTY + SCORE_EMPTY_WEIGHT * empty + SCORE_MERGES_WEIGHT * merges -
            SCORE_MONOTONICITY_WEIGHT * min(monotonicity_left, monotonicity_right) - SCORE_SUM_WEIGHT * sum;

        i := 0;
        while i < 3 do
        begin
            j := i + 1;
            while j < 4 do
            begin
                if row_line[j] <> 0 then break;
                j := j + 1;
            end;
            if j = 4 then break;

            if row_line[i] = 0 then
            begin
                row_line[i] := row_line[j];
                row_line[j] := 0;
                i := i - 1;
            end
            else if row_line[i] = row_line[j] then
            begin
                if row_line[i] <> $f then 
                    row_line[i] := row_line[i] + 1;
                row_line[j] := 0;
            end;
            i := i + 1;
        end;

        row_result := (row_line[0] shl  0) or 
                      (row_line[1] shl  4) or 
                      (row_line[2] shl  8) or 
                      (row_line[3] shl 12);

        rev_result := reverse_row(row_result);
        rev_row    := reverse_row(row);

        row_left_table[row]      := row     xor row_result;
        row_right_table[rev_row] := rev_row xor rev_result;

        row := row + 1;
    until row = 0;
end;

function execute_move_col(board : board_t; var table : row_table_t) : board_t;
var
    ret, t : board_t;
begin
    ret := board;
    t := transpose(board);
    ret := ret xor (unpack_col(table[(t shr  0) and ROW_MASK]) shl  0);
    ret := ret xor (unpack_col(table[(t shr 16) and ROW_MASK]) shl  4);
    ret := ret xor (unpack_col(table[(t shr 32) and ROW_MASK]) shl  8);
    ret := ret xor (unpack_col(table[(t shr 48) and ROW_MASK]) shl 12);
    execute_move_col := ret;
end;

function execute_move_row(board : board_t; var table : row_table_t) : board_t;
var
    ret : board_t;
begin
    ret := board;
    ret := ret xor (board_t(table[(board shr  0) and ROW_MASK]) shl  0);
    ret := ret xor (board_t(table[(board shr 16) and ROW_MASK]) shl 16);
    ret := ret xor (board_t(table[(board shr 32) and ROW_MASK]) shl 32);
    ret := ret xor (board_t(table[(board shr 48) and ROW_MASK]) shl 48);
    execute_move_row := ret;
end;

function execute_move(_move : integer; board : board_t) : board_t;
var
    ret : board_t;
begin
    if _move = UP then
        ret := execute_move_col(board, row_left_table)
    else if _move = DOWN then
        ret := execute_move_col(board, row_right_table)
    else if _move = LEFT then
        ret := execute_move_row(board, row_left_table)
    else if _move = RIGHT then
        ret := execute_move_row(board, row_right_table)
    else
        ret := not board_t(0);
    execute_move := ret
end;

function count_distinct_tiles(board : board_t) : integer;
var
    bitset : word;
    count  : integer;
begin
    bitset := 0;
    while board <> 0 do
    begin
        bitset := bitset or (1 shl (board and $f));
        board := board shr 4;
    end;

    bitset := bitset shr 1;
    count := 0;
    while bitset <> 0 do
    begin
        bitset := bitset and (bitset - 1);
        count := count + 1;
    end;
    count_distinct_tiles := count;
end;

function score_helper(board : board_t; var table : score_table_t) : real;
begin
    score_helper := table[(board shr  0) and ROW_MASK] +
                    table[(board shr 16) and ROW_MASK] +
                    table[(board shr 32) and ROW_MASK] +
                    table[(board shr 48) and ROW_MASK];
end;

function score_heur_board(board : board_t) : real;
begin
    score_heur_board := score_helper(board, heur_score_table) + score_helper(transpose(board), heur_score_table);
end;

function score_board(board : board_t) : dword;
begin
    score_board := round(score_helper(board, score_table));
end;

function score_move_node(var state : eval_state; board : board_t; cprob : real) : real; forward;

function score_tilechoose_node(var state : eval_state; board : board_t; cprob : real) : real;
var
    res   : real;
    entry : trans_table_entry_t;
    tile_2, tmp : board_t;
    num_open    : integer;
begin
    if (cprob < CPROB_THRESH_BASE) or (state.curdepth >= state.depth_limit) then
    begin
        state.maxdepth := max(state.curdepth, state.maxdepth);
        exit(score_heur_board(board));
    end;
    if state.curdepth < CACHE_DEPTH_LIMIT then
    begin
        if state.trans_table.ContainsKey(board) then
        begin
            entry := state.trans_table[board];
            if entry.depth <= state.curdepth then
            begin
                state.cachehits := state.cachehits + 1;
                exit(entry.heuristic);
            end;
        end;
    end;

    num_open := count_empty(board);
    cprob := cprob / num_open;
    res := 0.0;
    tmp := board;
    tile_2 := 1;

    while tile_2 <> 0 do
    begin
        if (tmp and $f) = 0 then
        begin
            res := res + score_move_node(state, board or tile_2, cprob * 0.9) * 0.9;
            res := res + score_move_node(state, board or (tile_2 shl 1), cprob * 0.1) * 0.1;
        end;
        tmp := tmp shr 4;
        tile_2 := tile_2 shl 4;
    end;
    res := res / num_open;

    if state.curdepth < CACHE_DEPTH_LIMIT then
    begin
        entry.depth := state.curdepth;
        entry.heuristic := res;
        state.trans_table.AddOrSetValue(board, entry);
    end;

    score_tilechoose_node := res;
end;

function score_move_node(var state : eval_state; board : board_t; cprob : real) : real;
var
    _move : integer;
    best, tmp : real;
    newboard : board_t;
begin
    best := 0.0;

    state.curdepth := state.curdepth + 1;
    for _move := 0 to 3 do
    begin
        newboard := execute_move(_move, board);
        state.moves_evaled := state.moves_evaled + 1;

        if board <> newboard then
        begin
            tmp := score_tilechoose_node(state, newboard, cprob);
            if best < tmp then
                best := tmp;
        end;
    end;
    state.curdepth := state.curdepth - 1;

    score_move_node := best;
end;

function _score_toplevel_move(var state : eval_state; board : board_t; _move : integer) : real;
var
    newboard : board_t;
begin
    newboard := execute_move(_move, board);

    if board = newboard then
        _score_toplevel_move := 0.0
    else
        _score_toplevel_move := score_tilechoose_node(state, newboard, 1.0) + 0.000001;
end;

function score_toplevel_move(board : board_t; _move : integer) : real;
var
    state : eval_state;
    res : real;
begin
    state.trans_table := trans_table_t.Create();
    state.maxdepth := 0;
    state.curdepth := 0;
    state.cachehits := 0;
    state.moves_evaled := 0;
    state.depth_limit := count_distinct_tiles(board) - 2;
    if state.depth_limit < 3 then
        state.depth_limit := 3;

    res := _score_toplevel_move(state, board, _move);

    writeln(format('Move %d: result %f: eval''d %d moves (%d cache hits, %d cache size) (maxdepth=%d)', [_move, res,
           state.moves_evaled, state.cachehits, state.trans_table.Count, state.maxdepth]));

    score_toplevel_move := res;
end;

function find_best_move(board : board_t) : integer;
var
    _move, bestmove : integer;
    best : real;
    res : array[0..3] of real;
begin
    _move := 0;
    bestmove := -1;
    best := 0.0;

    print_board(board);
    writeln(format('Current scores: heur %d, actual %d', [round(score_heur_board(board)), score_board(board)]));

    for _move := 0 to 3 do
    begin
        res[_move] := score_toplevel_move(board, _move);
    end;

    for _move := 0 to 3 do
    begin
        if res[_move] > best then
        begin
            best := res[_move];
            bestmove := _move;
        end;
    end;
    writeln(format('Selected bestmove: %d, result: %f', [bestmove, best]));

    find_best_move := bestmove;
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

function insert_tile_rand(board : board_t; tile : board_t) : board_t;
var
    index : integer;
    tmp : board_t;
begin
    index := unif_random(count_empty(board));
    tmp := board;
    while true do
    begin
        while (tmp and $f) <> 0 do
        begin
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

function initial_board : board_t;
var
    board : board_t;
begin
    board := board_t((draw_tile) shl (unif_random(16) shl 2));
    initial_board := insert_tile_rand(board, draw_tile);
end;

type
    get_move_func_t = function(board : board_t) : integer;

procedure play_game(get_move : get_move_func_t);
var
    board               : board_t;
    newboard            : board_t;
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

    while true do
    begin
        clear_screen;
        _move := 0;
        while _move < 4 do
        begin
            if execute_move(_move, board) <> board then
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

        newboard := execute_move(_move, board);
        if newboard = board then
        begin
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
    randomize;
    init_tables;
    play_game(@find_best_move);
end.
