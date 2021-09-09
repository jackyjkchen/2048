program main_2048;

uses crt, sysutils, strings;

function unif_random(n : integer) : integer;
begin
    unif_random := random(n);
end;

procedure clear_screen;
begin
    clrscr;
end;

function get_ch : char;
begin
    get_ch := ReadKey;
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
    RETRACT  : integer = 4;

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
    x := x + (x shr 8);
    x := x + (x shr 4);
    count_empty := x and $f;
end;

{$macro on}
{$if (not defined(FASTMODE)) or (defined(FASTMODE) and FASTMODE <> 0)}
{$define FASTMODE := 1}
{$endif}

{$if FASTMODE <> 0}
const
    TABLESIZE = 65536;
type
    row_table_t   =  array[0..(TABLESIZE)-1] of word;
    score_table_t =  array[0..(TABLESIZE)-1] of dword;

var
    row_table   : row_table_t;
    score_table : score_table_t;

procedure init_tables;
var
    row, row_result : row_t;
    i, j, rank : integer;
    row_line   : array[0..3] of byte;
    score      : dword;
begin
    row := 0;
    row_result := 0;
    repeat
        score := 0;
        row_line[0] := row and $f;
        row_line[1] := (row shr 4) and $f;
        row_line[2] := (row shr 8) and $f;
        row_line[3] := (row shr 12) and $f;

        for i := 0 to 3 do
        begin
            rank := row_line[i];
            if rank >= 2 then
                score := score + ((rank - 1) * (1 shl rank));
        end;
        score_table[row] := score;

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

        row_result := row_line[0] or (row_line[1] shl 4) or (row_line[2] shl 8) or (row_line[3] shl 12);
        row_table[row] := row xor row_result;

        row := row + 1;
    until row = 0;
end;

function execute_move_col(board : board_t; _move : integer) : board_t;
var
    ret, t : board_t;
begin
    ret := board;
    t := transpose(board);
    if _move = UP then begin
        ret := ret xor unpack_col(row_table[t and ROW_MASK]);
        ret := ret xor (unpack_col(row_table[(t shr 16) and ROW_MASK]) shl 4);
        ret := ret xor (unpack_col(row_table[(t shr 32) and ROW_MASK]) shl 8);
        ret := ret xor (unpack_col(row_table[(t shr 48) and ROW_MASK]) shl 12);
    end else if _move = DOWN then begin
        ret := ret xor unpack_col(reverse_row(row_table[reverse_row(t and ROW_MASK)]));
        ret := ret xor (unpack_col(reverse_row(row_table[reverse_row((t shr 16) and ROW_MASK)])) shl 4);
        ret := ret xor (unpack_col(reverse_row(row_table[reverse_row((t shr 32) and ROW_MASK)])) shl 8);
        ret := ret xor (unpack_col(reverse_row(row_table[reverse_row((t shr 48) and ROW_MASK)])) shl 12);
    end;
    execute_move_col := ret;
end;

function execute_move_row(board : board_t; _move : integer) : board_t;
var
    ret : board_t;
begin
    ret := board;
    if _move = LEFT then begin
        ret := ret xor board_t(row_table[board and ROW_MASK]);
        ret := ret xor (board_t(row_table[(board shr 16) and ROW_MASK]) shl 16);
        ret := ret xor (board_t(row_table[(board shr 32) and ROW_MASK]) shl 32);
        ret := ret xor (board_t(row_table[(board shr 48) and ROW_MASK]) shl 48);
    end else if _move = RIGHT then begin
        ret := ret xor board_t(reverse_row(row_table[reverse_row(board and ROW_MASK)]));
        ret := ret xor (board_t(reverse_row(row_table[reverse_row((board shr 16) and ROW_MASK)])) shl 16);
        ret := ret xor (board_t(reverse_row(row_table[reverse_row((board shr 32) and ROW_MASK)])) shl 32);
        ret := ret xor (board_t(reverse_row(row_table[reverse_row((board shr 48) and ROW_MASK)])) shl 48);
    end;
    execute_move_row := ret;
end;

function score_helper(board : board_t) : dword;
begin
    score_helper := score_table[board and ROW_MASK] + score_table[(board shr 16) and ROW_MASK] +
        score_table[(board shr 32) and ROW_MASK] + score_table[(board shr 48) and ROW_MASK];
end;
{$else}
function execute_move_helper(row : row_t) : row_t;
var
    i, j     : integer;
    row_line : array[0..3] of byte;
begin
    row_line[0] := row and $f;
    row_line[1] := (row shr 4) and $f;
    row_line[2] := (row shr 8) and $f;
    row_line[3] := (row shr 12) and $f;

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

    execute_move_helper := row_line[0] or (row_line[1] shl 4) or (row_line[2] shl 8) or (row_line[3] shl 12);
end;

function execute_move_col(board : board_t; _move : integer) : board_t;
var
    ret ,t : board_t;
    i : integer;
    row, rev_row : row_t;
begin
    ret := board;
    t := transpose(board);
    for i := 0 to 3 do
    begin
        row := (t shr (i shl 4)) and ROW_MASK;
        if _move = UP then begin
            ret := ret xor (unpack_col(row xor execute_move_helper(row)) shl (i shl 2));
        end else if _move = DOWN then begin
            rev_row := reverse_row(row);
            ret := ret xor (unpack_col(row xor reverse_row(execute_move_helper(rev_row))) shl (i shl 2));
        end;
    end;
    execute_move_col := ret;
end;

function execute_move_row(board : board_t; _move : integer) : board_t;
var
    ret : board_t;
    i : integer;
    row, rev_row : row_t;
begin
    ret := board;
    for i := 0 to 3 do
    begin
        row := (board shr (i shl 4)) and ROW_MASK;
        if _move = LEFT then begin
            ret := ret xor (board_t(row xor execute_move_helper(row)) shl (i shl 4));
        end else if _move = RIGHT then begin
            rev_row := reverse_row(row);
            ret := ret xor (board_t(row xor reverse_row(execute_move_helper(rev_row))) shl (i shl 4));
        end;
    end;
    execute_move_row := ret;
end;

function score_helper(board : board_t) : dword;
var
    i, j : integer;
    score : dword;
    row : row_t;
    rank : byte;
begin
    score := 0;
    for j := 0 to 3 do
    begin
        row := (board shr (j shl 4)) and ROW_MASK;
        for i := 0 to 3 do
        begin
            rank := (row shr (i shl 2)) and $f;
            if rank >= 2 then
                score := score + ((rank - 1) * (1 shl rank));
        end;
    end;
    score_helper := score;
end;
{$endif}

function execute_move(_move : integer; board : board_t) : board_t;
var
    ret : board_t;
begin
    if (_move = UP) or (_move = DOWN) then
        ret := execute_move_col(board, _move)
    else if (_move = LEFT) or (_move = RIGHT) then
        ret := execute_move_row(board, _move)
    else
        ret := not board_t(0);
    execute_move := ret
end;

function score_board(board : board_t) : dword;
begin
    score_board := score_helper(board);
end;

function ask_for_move(board : board_t) : integer;
var
    movechar : char;
    _pos     : pchar;
const
    allmoves : pchar = 'wsadkjhl';
begin
    print_board(board);
    while true do
    begin
        movechar := get_ch;
        if movechar = 'q' then
            exit(-1);
        if movechar = 'r' then 
            exit(RETRACT);
        _pos := strscan(allmoves, movechar);
        if _pos <> nil then
            exit((_pos - allmoves) mod 4);
    end;
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
const
    MAX_RETRACT = 64;
var
    board               : board_t;
    newboard            : board_t;
    scorepenalty        : longint;
    current_score       : longint;
    last_score          : longint;
    moveno              : dword;
    _move               : integer;
    tile                : word;
    retract_vec         : array[0..(MAX_RETRACT)-1] of board_t;
    retract_penalty_vec : array[0..(MAX_RETRACT)-1] of byte;
    retract_pos         : integer;
    retract_num         : integer;
begin
    board := initial_board;
    scorepenalty := 0;
    current_score := 0;
    last_score := 0;
    moveno := 0;
    fillbyte(retract_vec, sizeof(retract_vec), 0);
    fillbyte(retract_penalty_vec, sizeof(retract_penalty_vec), 0);
    retract_pos := 0;
    retract_num := 0;

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

        if _move = RETRACT then
        begin
            if (moveno <= 1) or (retract_num <= 0) then
            begin
                moveno := moveno - 1;
                continue;
            end;
            moveno := moveno - 2;
            if (retract_pos = 0) and (retract_num > 0) then
                retract_pos := MAX_RETRACT;
            retract_pos := retract_pos - 1;
            board := retract_vec[retract_pos];
            scorepenalty := scorepenalty - retract_penalty_vec[retract_pos];
            retract_num := retract_num - 1;
            continue;
        end;

        newboard := execute_move(_move, board);
        if newboard = board then
        begin
            moveno := moveno - 1;
            continue;
        end;

        tile := draw_tile;
        if tile = 2 then begin
            scorepenalty := scorepenalty + 4;
            retract_penalty_vec[retract_pos] := 4;
        end else begin
            retract_penalty_vec[retract_pos] := 0;
        end;
        retract_vec[retract_pos] := board;
        retract_pos := retract_pos + 1;
        if retract_pos = MAX_RETRACT then
            retract_pos := 0;
        if retract_num < MAX_RETRACT then
            retract_num := retract_num + 1;
        board := insert_tile_rand(newboard, tile);
    end;
    print_board(board);
    writeln(format('Game over. Your score is %d.', [current_score]));
end;

begin
    randomize;
{$if FASTMODE <> 0}
    init_tables;
{$endif}
    play_game(@ask_for_move);
end.
