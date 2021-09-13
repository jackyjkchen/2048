#!/bin/bash

unif_random() {
    local n=$1
    if [ $((n)) -ne 0 ]
    then
        echo $(($RANDOM % n))
    else
        echo 0
    fi
}

unpack_col() {
    local row=$1
    local board=( 0 0 0 0 )
    board[0]=$(((row & 0xF000) >> 12))
    board[1]=$(((row & 0x0F00) >> 8))
    board[2]=$(((row & 0x00F0) >> 4))
    board[3]=$((row & 0x000F))
    echo ${board[@]}
}

reverse_row() {
    local row=$1
    echo $(((row >> 12) | ((row >> 4) & 0x00F0)  | ((row << 4) & 0x0F00) | (row << 12)))
}

print_board() {
    local board=( $1 $2 $3 $4 )
    local i=0
    local j=0
    echo '-----------------------------'
    while [ $((i)) -lt 4 ]
    do
        j=0
        while [ $((j)) -lt 4 ]
        do
            local power_val=$((board[3-i] & 0xf))
            if [ $((power_val)) -eq 0 ]
            then
                printf '|%6s' ' '
            else
                printf '|%6d'  $((1 << power_val))
            fi
            board[$((3-i))]=$((board[3-i] >> 4))
            j=$((j + 1))
        done
        echo '|'
        i=$((i + 1))
    done
    echo '-----------------------------'
}

transpose() {
    local x=( $1 $2 $3 $4 )
    local r0=0
    local r1=0
    local r2=0
    local r3=0
    local a1_0=$((x[0] & 0xF0F0))
    local a1_1=$((x[1] & 0x0F0F))
    local a1_2=$((x[2] & 0xF0F0))
    local a1_3=$((x[3] & 0x0F0F))
    local a2_1=$((x[1] & 0xF0F0))
    local a2_3=$((x[3] & 0xF0F0))
    local a3_0=$((x[0] & 0x0F0F))
    local a3_2=$((x[2] & 0x0F0F))
    r0=$((a1_0 | (a2_1 >> 4)))
    r1=$((a1_1 | (a3_0 << 4)))
    r2=$((a1_2 | (a2_3 >> 4)))
    r3=$((a1_3 | (a3_2 << 4)))
    local b1_0=$((r0 & 0xFF00))
    local b1_1=$((r1 & 0xFF00))
    local b1_2=$((r2 & 0x00FF))
    local b1_3=$((r3 & 0x00FF))
    local b2_0=$((r0 & 0x00FF))
    local b2_1=$((r1 & 0x00FF))
    local b3_2=$((r2 & 0xFF00))
    local b3_3=$((r3 & 0xFF00))
    x[0]=$((b1_0 | (b3_2 >> 8)))
    x[1]=$((b1_1 | (b3_3 >> 8)))
    x[2]=$((b1_2 | (b2_0 << 8)))
    x[3]=$((b1_3 | (b2_1 << 8)))
    echo ${x[@]}
}

count_empty() {
    local board=( $1 $2 $3 $4 )
    local x=0
    local sum=0
    local i=0
    while [ $((i)) -lt 4 ]
    do
        x=$((board[i]))
        x=$((x | (x >> 2) & 0x3333))
        x=$((x | (x >> 1)))
        x=$((~x & 0x1111))
        x=$((x + (x >> 8)))
        x=$((x + (x >> 4)))
        sum=$((sum + x))
        i=$((i + 1))
    done
    echo $((sum & 0xf))
}

execute_move_helper() {
    local row=$1
    local line=( $((row & 0xf)) $(((row >> 4) & 0xf)) $(((row >> 8) & 0xf)) $(((row >> 12) & 0xf)) )
    local i=0
    local j=0

    while [ $((i)) -lt 3 ]
    do
        j=$((i + 1))
        while [ $((j)) -lt 4 ]
        do
            if [ $((line[j])) -ne 0 ]
            then
                break
            fi
            j=$((j + 1))
        done
        if [ $((j)) -eq 4 ]
        then
            break
        fi

        if [ $((line[i])) -eq 0 ]
        then
            line[$((i))]=$((line[j]))
            line[$((j))]=0
            i=$((i - 1))
        elif [ $((line[i])) -eq $((line[j])) ]
        then
            if [ $((line[i])) -ne $((0xf)) ]
            then
                line[$((i))]=$((line[i] + 1))
            fi
            line[$((j))]=0
        fi
        i=$((i + 1))
    done

    echo $((line[0] | (line[1] << 4) | (line[2] << 8) | (line[3] << 12)))
}

execute_move_col() {
    local board=( $1 $2 $3 $4 )
    local move=$5
    local ret=( ${board[@]} )
    local t=( $(transpose ${board[@]}) )
    local row
    local rev_row
    local i=0
    local tmp

    while [ $((i)) -lt 4 ]
    do
        row=$((t[3-i]))
        if [ $((move)) -eq 0 ]
        then
            tmp=( $(unpack_col $((row ^ $(execute_move_helper $((row)))))) )
        elif [ $((move)) -eq 1 ]
        then
            rev_row=$(reverse_row $((row)))
            tmp=( $(unpack_col $((row ^ $(reverse_row $(execute_move_helper $((rev_row))))))) )
        fi
        ret[0]=$((ret[0] ^ (tmp[0] << (i << 2))))
        ret[1]=$((ret[1] ^ (tmp[1] << (i << 2))))
        ret[2]=$((ret[2] ^ (tmp[2] << (i << 2))))
        ret[3]=$((ret[3] ^ (tmp[3] << (i << 2))))
        i=$((i + 1))
    done
    echo ${ret[@]}
}

execute_move_row() {
    local ret=( $1 $2 $3 $4 )
    local move=$5
    local row
    local rev_row
    local i=0

    while [ $((i)) -lt 4 ]
    do
        row=$((ret[3-i]))
        if [ $((move)) -eq 2 ]
        then
            ret[$((3-i))]=$((ret[3-i] ^ (row ^ $(execute_move_helper $((row))))))
        elif [ $((move)) -eq 3 ]
        then
            rev_row=$(reverse_row $((row)))
            ret[$((3-i))]=$((ret[3-i] ^ (row ^ $(reverse_row $(execute_move_helper $((rev_row)))))))
        fi
        i=$((i + 1))
    done
    echo ${ret[@]}
}

execute_move() {
    local move=$1
    local board=( $2 $3 $4 $5 )

    if [[ ($((move)) -eq 0) || ($((move)) -eq 1) ]]
    then
        echo $(execute_move_col ${board[@]} $((move)))
        return
    elif [[ ($((move)) -eq 2) || ($((move)) -eq 3) ]]
    then
        echo $(execute_move_row ${board[@]} $((move)))
        return
    else
        echo -1
        return
    fi
}

score_helper() {
    local board=( $1 $2 $3 $4 )
    local score=0
    local row
    local rank
    local i=0
    local j=0

    while [ $((j)) -lt 4 ]
    do
        row=$((board[3-j]))
        i=0
        while [ $((i)) -lt 4 ]
        do
            rank=$(((row >> (i << 2)) & 0xf))
            if [ $((rank)) -ge 2 ]
            then
                score=$((score + (rank - 1) * (1 << rank)))
            fi
            i=$((i + 1))
        done
        j=$((j + 1))
    done
    echo $((score))
}

score_board() {
    local board=( $1 $2 $3 $4 )
    echo $(score_helper ${board[@]})
}

strindex() {
  local x="${1%%$2*}"
  [[ $x = $1 ]] && echo -1 || echo $((${#x} + 1))
}

ask_for_move() {
    local allmoves="wsadkjhl"
    local movechar
    local pos=0

    while true
    do
        movechar=`dd if=/dev/tty bs=1 count=1 2>/dev/null`

        if [[ $movechar == 'q' ]]
        then
            echo -1
            return
        fi
        pos=$(strindex $allmoves $movechar)
        if [ $((pos)) -ne -1 ]
        then
            echo $(((pos - 1) % 4))
            return
        fi
    done
}

draw_tile() {
    local rd=$(unif_random 10)
    if [ $((rd)) -lt 9 ]
    then
       echo 1
    else
       echo 2
    fi
}

insert_tile_rand() {
    local board=( $1 $2 $3 $4 )
    local tile=$5
    local orig_tile=$tile
    local index=$(unif_random $(count_empty ${board[@]}))
    local tmp=${board[3]}
    local shift=0

    while true
    do
        while [ $((tmp & 0xf)) -ne 0 ]
        do
            tmp=$((tmp >> 4))
            tile=$((tile << 4))
            shift=$((shift + 4))
            if [ $((shift % 16)) -eq 0 ]
            then
                tmp=$((board[3-(shift>>4)]))
                tile=$orig_tile
            fi
        done
        if [ $((index)) -eq 0 ]
        then
            break
        fi
        index=$((index - 1))
        tmp=$((tmp >> 4))
        tile=$((tile << 4))
        shift=$((shift + 4))
        if [ $((shift % 16)) -eq 0 ]
        then
            tmp=$((board[3-(shift>>4)]))
            tile=$orig_tile
        fi
    done
    board[$((3-(shift>>4)))]=$((board[3-(shift>>4)] | tile))
    echo ${board[@]}
}

initial_board() {
    local board=( 0 0 0 0 )
    local shift=0
    shift=$(($(unif_random 10) << 2))
    board[$((3-(shift>>4)))]=$(($(draw_tile) << (shift % 16)))
    echo $(insert_tile_rand ${board[@]} $(draw_tile))
}

play_game() {
    local board=( $(initial_board) )
    local scorepenalty=0
    local last_score=0
    local current_score=0
    local moveno=0
    local move=0
    local newboard=0
    local i=0
    local tmp

    while true
    do
        printf "\033[2J\033[H"
        move=0
        while [ $((move)) -lt 4 ]
        do
            tmp=( $(execute_move $move ${board[@]}) )
            i=0
            while [ $((i)) -lt 4 ]
            do
                if [ $((tmp[i])) -ne $((board[i])) ]
                then
                    break
                fi
                i=$((i + 1))
            done
            if [ $((i)) -ne 4 ]
            then
                break
            fi
            move=$((move + 1))
        done
        if [ $((move)) -eq 4 ]
        then
            break
        fi

        current_score=$(($(score_board ${board[@]}) - scorepenalty))
        moveno=$((moveno + 1))
        printf 'Move #%d, current score=%d(+%d)\n' $((moveno)) $((current_score)) $((current_score - last_score))
        last_score=$((current_score))

        print_board ${board[@]}
        move=$(ask_for_move)
        if [ $((move)) -lt 0 ]
        then
            break
        fi

        newboard=( $(execute_move $((move)) ${board[@]}) )
        i=0
        while [ $((i)) -lt 4 ]
        do
            if [ $((newboard[i])) -ne $((board[i])) ]
            then
                break
            fi
            i=$((i + 1))
        done
        if [ $((i)) -eq 4 ]
        then
            moveno=$((moveno - 1))
            continue
        fi

        tile=$(draw_tile)
        if [ $((tile)) -eq 2 ]
        then
            scorepenalty=$((scorepenalty + 4))
        fi

        board=( $(insert_tile_rand ${newboard[@]} $((tile))) )
    done
    print_board ${board[@]}
    printf 'Game over. Your score is %d.\n' $((current_score))
}

stty -echo cbreak </dev/tty >/dev/tty 2>&1
play_game
stty echo -cbreak </dev/tty >/dev/tty 2>&1
