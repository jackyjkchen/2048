program main_2048;

uses crt, strings;

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
    board_t = array[0..3] of word;
    row_t   = word;

const
    UP       : integer = 0;
    DOWN     : integer = 1;
    LEFT     : integer = 2;
    RIGHT    : integer = 3;
    RETRACT  : integer = 4;

procedure unpack_col(row : row_t; var board : board_t);
begin
    board[0] := (row and $F000) shr 12;
    board[1] := (row and $0F00) shr 8;
    board[2] := (row and $00F0) shr 4;
    board[3] := row and $000F;
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
    for i := 0 to 3 do begin
        for j := 0 to 3 do begin
            power_val := board[3-i] and $f;
            if power_val = 0 then
                write('|', ' ':6)
            else
                write('|', (1 shl power_val):6);
            board[3-i] := board[3-i] shr 4;
        end;
        writeln('|');
    end;
    writeln('-----------------------------');
end;

procedure transpose(var x : board_t);
var
    a1_0, a1_1, a1_2, a1_3, a2_1, a2_3, a3_0, a3_2, r0, r1, r2, r3, b1_0, b1_1, b1_2, b1_3, b2_0, b2_1, b3_2, b3_3 : word;
begin
    a1_0 := x[0] and $F0F0;
    a1_1 := x[1] and $0F0F;
    a1_2 := x[2] and $F0F0;
    a1_3 := x[3] and $0F0F;
    a2_1 := x[1] and $F0F0;
    a2_3 := x[3] and $F0F0;
    a3_0 := x[0] and $0F0F;
    a3_2 := x[2] and $0F0F;
    r0 := a1_0 or (a2_1 shr 4);
    r1 := a1_1 or (a3_0 shl 4);
    r2 := a1_2 or (a2_3 shr 4);
    r3 := a1_3 or (a3_2 shl 4);
    b1_0 := r0 and $FF00;
    b1_1 := r1 and $FF00;
    b1_2 := r2 and $00FF;
    b1_3 := r3 and $00FF;
    b2_0 := r0 and $00FF;
    b2_1 := r1 and $00FF;
    b3_2 := r2 and $FF00;
    b3_3 := r3 and $FF00;
    x[0] := b1_0 or (b3_2 shr 8);
    x[1] := b1_1 or (b3_3 shr 8);
    x[2] := b1_2 or (b2_0 shl 8);
    x[3] := b1_3 or (b2_1 shl 8);
end;

function count_empty(board : board_t) : integer;
var
    sum, x, i : word;
begin
    sum := 0;
    x := 0;
    for i := 0 to 3 do begin
        x := board[i];
        x := x or ((x shr 2) and $3333);
        x := x or ((x shr 1));
        x := (not x) and $1111;
        x := x + (x shr 8);
        x := x + (x shr 4);
        sum := sum + x;
    end;
    count_empty := sum and $f;
end;

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

    execute_move_helper := row_line[0] or (row_line[1] shl 4) or (row_line[2] shl 8) or (row_line[3] shl 12);
end;

procedure execute_move_col(var board : board_t; _move : integer);
var
    tran, tmp : board_t;
    i : integer;
    row, rev_row : row_t;
begin
    move(board, tran, sizeof(board_t));
    transpose(tran);
    for i := 0 to 3 do begin
        row := tran[3-i];
        if _move = UP then begin
            unpack_col(row xor execute_move_helper(row), tmp);
        end else if _move = DOWN then begin
            rev_row := reverse_row(row);
            unpack_col(row xor reverse_row(execute_move_helper(rev_row)), tmp);
        end;
        board[0] := board[0] xor (tmp[0] shl (i shl 2));
        board[1] := board[1] xor (tmp[1] shl (i shl 2));
        board[2] := board[2] xor (tmp[2] shl (i shl 2));
        board[3] := board[3] xor (tmp[3] shl (i shl 2));
    end;
end;

procedure execute_move_row(var board : board_t; _move : integer);
var
    i : integer;
    row, rev_row : row_t;
begin
    for i := 0 to 3 do begin
        row := board[3-i];
        if _move = LEFT then begin
            board[3-i] := board[3-i] xor (row xor execute_move_helper(row));
        end else if _move = RIGHT then begin
            rev_row := reverse_row(row);
            board[3-i] := board[3-i] xor (row xor reverse_row(execute_move_helper(rev_row)));
        end;
    end;
end;

procedure execute_move(_move : integer; var board : board_t);
begin
    if (_move = UP) or (_move = DOWN) then
        execute_move_col(board, _move)
    else if (_move = LEFT) or (_move = RIGHT) then
        execute_move_row(board, _move);
end;

function score_helper(board : board_t) : longint;
var
    i, j : integer;
    score : longint;
    row : row_t;
    rank : byte;
begin
    score := 0;
    for j := 0 to 3 do begin
        row := board[3-j];
        for i := 0 to 3 do begin
            rank := (row shr (i shl 2)) and $f;
            if rank >= 2 then
                score := score + ((rank - 1) * (1 shl rank));
        end;
    end;
    score_helper := score;
end;

function score_board(board : board_t) : longint;
begin
    score_board := score_helper(board);
end;

function ask_for_move(board : board_t) : integer;
var
    movechar : char;
    _pos     : pchar;
    ret      : integer;
const
    allmoves : pchar = 'wsadkjhl';
begin
    print_board(board);
    while true do begin
        movechar := get_ch;
        if movechar = 'q' then begin
            ret := -1;
            break;
        end else if movechar = 'r' then begin
            ret :=RETRACT;
            break;
        end;
        _pos := strscan(allmoves, movechar);
        if _pos <> nil then begin
            ret := (_pos - allmoves) mod 4;
            break;
        end;
    end;
    ask_for_move := ret;
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

procedure insert_tile_rand(var board : board_t; tile : word);
var
    index, shift : integer;
    tmp, orig_tile : word;
begin
    index := unif_random(count_empty(board));
    shift := 0;
    tmp := board[3];
    orig_tile := tile;
    while true do begin
        while (tmp and $f) <> 0 do begin
            tmp := tmp shr 4;
            tile := tile shl 4;
            shift := shift + 4;
            if (shift mod 16) = 0 then begin
                tmp := board[3 - (shift shr 4)];
                tile := orig_tile;
            end;
        end;
        if index = 0 then break;
        index := index - 1;
        tmp := tmp shr 4;
        tile := tile shl 4;
        shift := shift + 4;
        if (shift mod 16) = 0 then begin
            tmp := board[3 - (shift shr 4)];
            tile := orig_tile;
        end;
    end;
    board[3 - (shift shr 4)] := board[3 - (shift shr 4)] or tile;
end;

procedure initial_board(var board : board_t);
var
    shift : word;
begin
    shift := unif_random(16) shl 2;
    fillchar(board, sizeof(board_t), 0);
    board[3 - (shift shr 4)] := draw_tile shl (shift mod 16);
    insert_tile_rand(board, draw_tile);
end;

function compare_board(var b1 : board_t; var b2 : board_t) : boolean;
var
    ret : boolean;
    i   : integer;
begin
    ret := true;
    for i := 0 to 3 do begin
        if b1[i] <>  b2[i] then begin
            ret := false;
            break;
        end;
    end;
    compare_board := ret;
end;

procedure play_game;
const
    MAX_RETRACT = 64;
var
    board               : board_t;
    newboard            : board_t;
    scorepenalty        : longint;
    current_score       : longint;
    last_score          : longint;
    moveno              : longint;
    _move               : integer;
    tile                : longint;
    retract_vec         : array[0..(MAX_RETRACT)-1] of board_t;
    retract_penalty_vec : array[0..(MAX_RETRACT)-1] of byte;
    retract_pos         : integer;
    retract_num         : integer;
begin
    initial_board(board);
    scorepenalty := 0;
    current_score := 0;
    last_score := 0;
    moveno := 0;
    fillchar(retract_vec, sizeof(retract_vec), 0);
    fillchar(retract_penalty_vec, sizeof(retract_penalty_vec), 0);
    retract_pos := 0;
    retract_num := 0;

    while true do begin
        clear_screen;
        _move := 0;
        while _move < 4 do begin
            move(board, newboard, sizeof(board_t));
            execute_move(_move, newboard);
            if not compare_board(board, newboard) then
                break;
            _move := _move + 1;
        end;
        if _move = 4 then break;

        current_score := score_board(board) - scorepenalty;
        moveno := moveno + 1;
        writeln('Move #', moveno, ', current score=', current_score, '(+', current_score - last_score, ')');
        last_score := current_score;

        _move := ask_for_move(board);
        if _move < 0 then break;

        if _move = RETRACT then begin
            if (moveno <= 1) or (retract_num <= 0) then begin
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

        move(board, newboard, sizeof(board_t));
        execute_move(_move, newboard);
        if compare_board(board, newboard) then
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
        move(newboard, board, sizeof(board_t));
        insert_tile_rand(board, tile);
    end;
    print_board(board);
    writeln('Game over. Your score is ', current_score, '.');
end;

begin
    randomize;
    play_game;
end.
