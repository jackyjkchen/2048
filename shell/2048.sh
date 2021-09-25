#!/bin/bash

ROW_MASK=$((0xFFFF))
COL_MASK=$((0x000F000F000F000F))

function unif_random() {
    local n=$1
    if [ $((n)) -ne 0 ]; then
        echo $(($RANDOM % n))
    else
        echo 0
    fi
}

function unpack_col() {
    local row=$1
    echo $(((row | (row << 12) | (row << 24) | (row << 36)) & COL_MASK))
}

function reverse_row() {
    local row=$1
    echo $((((row >> 12) | ((row >> 4) & 0x00F0)  | ((row << 4) & 0x0F00) | (row << 12)) & $ROW_MASK ))
}

function print_board() {
    local board=$1
    local i=0
    local j=0
    echo '-----------------------------'
    while [ $((i)) -lt 4 ]; do
        j=0
        while [ $((j)) -lt 4 ]; do
            local power_val=$((board & 0xf))
            if [ $((power_val)) -eq 0 ]; then
                printf '|%6s' ' '
            else
                printf '|%6d'  $((1 << power_val))
            fi
            board=$((board >> 4))
            j=$((j + 1))
        done
        echo '|'
        i=$((i + 1))
    done
    echo '-----------------------------'
}

function transpose() {
    local x=$1
    local a
    local a1=$((x & 0xF0F00F0FF0F00F0F))
    local a2=$((x & 0x0000F0F00000F0F0))
    local a3=$((x & 0x0F0F00000F0F0000))
    a=$((a1 | (a2 << 12) | (a3 >> 12)))
    local b1=$((a & 0xFF00FF0000FF00FF))
    local b2=$((a & 0x00FF00FF00000000))
    local b3=$((a & 0x00000000FF00FF00))
    echo $((b1 | (b2 >> 24) | (b3 << 24)))
}

function count_empty() {
    local x=$1
    x=$((x | ((x >> 2) & 0x3333333333333333)))
    x=$((x | (x >> 1)))
    x=$((~x & 0x1111111111111111))
    x=$((x + (x >> 32)))
    x=$((x + (x >> 16)))
    x=$((x + (x >> 8)))
    x=$((x + (x >> 4)))
    echo $((x & 0xf))
}

function execute_move_helper() {
    local row=$1
    local line=( $((row & 0xf)) $(((row >> 4) & 0xf)) $(((row >> 8) & 0xf)) $(((row >> 12) & 0xf)) )
    local i=0
    local j=0

    while [ $((i)) -lt 3 ]; do
        j=$((i + 1))
        while [ $((j)) -lt 4 ]; do
            if [ $((line[j])) -ne 0 ]; then
                break
            fi
            j=$((j + 1))
        done
        if [ $((j)) -eq 4 ]; then
            break
        fi

        if [ $((line[i])) -eq 0 ]; then
            line[$((i))]=$((line[j]))
            line[$((j))]=0
            i=$((i - 1))
        elif [ $((line[i])) -eq $((line[j])) ]; then
            if [ $((line[i])) -ne $((0xf)) ]; then
                line[$((i))]=$((line[i] + 1))
            fi
            line[$((j))]=0
        fi
        i=$((i + 1))
    done

    echo $((line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12)))
}

function execute_move_col() {
    local board=$1
    local move=$2
    local ret=$((board))
    local t=$(transpose $((board)))
    local row
    local rev_row
    local i=0

    while [ $((i)) -lt 4 ]; do
        row=$(((t >> (i << 4)) & ROW_MASK))
        if [ $((move)) -eq 0 ]; then
            ret=$((ret ^ ($(unpack_col $((row ^ $(execute_move_helper $((row)))))) << (i << 2))))
        elif [ $((move)) -eq 1 ]; then
            rev_row=$(reverse_row $((row)))
            ret=$((ret ^ ($(unpack_col $((row ^ $(reverse_row $(execute_move_helper $((rev_row))))))) << (i << 2))))
        fi
        i=$((i + 1))
    done
    echo $((ret))
}

function execute_move_row() {
    local board=$1
    local move=$2
    local ret=$((board))
    local row
    local rev_row
    local i=0

    while [ $((i)) -lt 4 ]; do
        row=$(((board >> (i << 4)) & ROW_MASK))
        if [ $((move)) -eq 2 ]; then
            ret=$((ret ^ ((row ^ $(execute_move_helper $((row)))) << (i << 4))))
        elif [ $((move)) -eq 3 ]; then
            rev_row=$(reverse_row $((row)))
            ret=$((ret ^ ((row ^ $(reverse_row $(execute_move_helper $((rev_row))))) << (i << 4))))
        fi
        i=$((i + 1))
    done
    echo $((ret))
}

function execute_move() {
    local move=$1
    local board=$2

    if [[ ($((move)) -eq 0) || ($((move)) -eq 1) ]]; then
        echo $(execute_move_col $((board)) $((move)))
        return
    elif [[ ($((move)) -eq 2) || ($((move)) -eq 3) ]]; then
        echo $(execute_move_row $((board)) $((move)))
        return
    else
        echo $((0xFFFFFFFFFFFFFFFF))
        return
    fi
}

function score_helper() {
    local board=$1
    local score=0
    local row
    local rank
    local i=0
    local j=0

    while [ $((j)) -lt 4 ]; do
        row=$(((board >> (j << 4)) & ROW_MASK))
        i=0
        while [ $((i)) -lt 4 ]; do
            rank=$(((row >> (i << 2)) & 0xf))
            if [ $((rank)) -ge 2 ]; then
                score=$((score + (rank - 1) * (1 << rank)))
            fi
            i=$((i + 1))
        done
        j=$((j + 1))
    done
    echo $((score))
}

function score_board() {
    local board=$1
    echo $(score_helper $((board)))
}

function strindex() {
  local x="${1%%$2*}"
  [[ $x = $1 ]] && echo -1 || echo $((${#x} + 1))
}

function draw_tile() {
    local rd=$(unif_random 10)
    if [ $((rd)) -lt 9 ]; then
       echo 1
    else
       echo 2
    fi
}

function insert_tile_rand() {
    local board=$1
    local tile=$2
    local index=$(unif_random $(count_empty $((board))))
    local tmp=$board

    while true; do
        while [ $((tmp & 0xf)) -ne 0 ]; do
            tmp=$((tmp >> 4))
            tile=$((tile << 4))
        done
        if [ $((index)) -eq 0 ]; then
            break
        fi
        index=$((index - 1))
        tmp=$((tmp >> 4))
        tile=$((tile << 4))
    done
    echo $((board | tile))
}

function initial_board() {
    local board
    board=$(($(draw_tile) << ($(unif_random 10) << 2)))
    echo $(insert_tile_rand $((board)) $(draw_tile))
}

function ask_for_move() {
    local allmoves="wsadkjhl"
    local movechar
    local pos=0

    while true; do
        movechar=`dd if=/dev/tty bs=1 count=1 2>/dev/null`

        if [[ $movechar == 'q' ]]; then
            echo -1
            return
        elif [[ $movechar == 'r' ]]; then
            echo 4
            return
        fi
        pos=$(strindex $allmoves $movechar)
        if [ $((pos)) -ne -1 ]; then
            echo $(((pos - 1) % 4))
            return
        fi
    done
}

function play_game() {
    local board=$(initial_board)
    local scorepenalty=0
    local last_score=0
    local current_score=0
    local moveno=0
    local move=0
    local newboard=0
    local MAX_RETRACT=64
    local retract_vec=()
    local retract_penalty_vec=()
    local retract_pos=0
    local retract_num=0

    while true; do
        printf "\033[2J\033[H"
        move=0
        while [ $((move)) -lt 4 ]; do
            if [ $(($(execute_move $move $board))) -ne $((board)) ]; then
                break
            fi
            move=$((move + 1))
        done
        if [ $((move)) -eq 4 ]; then
            break
        fi

        current_score=$(($(score_board $((board))) - scorepenalty))
        moveno=$((moveno + 1))
        printf 'Move #%d, current score=%d(+%d)\n' $((moveno)) $((current_score)) $((current_score - last_score))
        last_score=$((current_score))

        print_board $((board))
        move=$(ask_for_move)
        if [ $((move)) -lt 0 ]; then
            break
        fi

        if [ $((move)) -eq 4 ]; then
            if [[ ($((moveno)) -le 1) || ($((retract_num)) -le 0) ]]; then
                moveno=$((moveno - 1))
                continue
            fi
            moveno=$((moveno - 2))
            if [[ ($((retract_pos)) -eq 0) && ($((retract_num)) -gt 0) ]]; then
                retract_pos=64
            fi
            retract_pos=$((retract_pos - 1))
            board=$((retract_vec[retract_pos]))
            scorepenalty=$((scorepenalty - retract_penalty_vec[retract_pos]))
            retract_num=$((retract_num - 1))
            continue
        fi

        newboard=$(execute_move $((move)) $((board)))
        if [ $((newboard)) -eq $((board)) ]; then
            moveno=$((moveno - 1))
            continue
        fi

        tile=$(draw_tile)
        if [ $((tile)) -eq 2 ]; then
            scorepenalty=$((scorepenalty + 4))
            retract_penalty_vec[$((retract_pos))]=4
        else
            retract_penalty_vec[$((retract_pos))]=0
        fi
        retract_vec[$((retract_pos))]=$((board))
        retract_pos=$((retract_pos + 1))
        if [ $((retract_pos)) -eq 64 ]; then
            retract_pos=0
        fi
        if [ $((retract_num)) -lt 64 ]; then
            retract_num=$((retract_num + 1))
        fi

        board=$(insert_tile_rand $((newboard)) $((tile)))
    done
    print_board $((board))
    printf 'Game over. Your score is %d.\n' $((current_score))
}

stty -echo cbreak </dev/tty >/dev/tty 2>&1
play_game
stty echo -cbreak </dev/tty >/dev/tty 2>&1
