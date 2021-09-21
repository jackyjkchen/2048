#!/usr/bin/env perl

use bigint;
use Term::ReadKey;
use Term::ANSIScreen;

sub clear_screen {
    my $console = Term::ANSIScreen->new;
    $console->Cls();
    $console->Cursor(0, 0);
    $console->Display();
}

sub get_ch {
    my $key;
    ReadMode 4;
    while (not defined ($key = ReadKey(-1))) {}
    ReadMode 0;
    return $key;
}

sub unif_random {
    my $n = $_[0];
    return int(rand($n));
}

our $ROW_MASK = 0xFFFF;
our $COL_MASK = 0x000F000F000F000F;

our $UP = 0;
our $DOWN = 1;
our $LEFT = 2;
our $RIGHT = 3;
our $RETRACT = 4;

sub unpack_col {
    my $row = $_[0];
    return ($row | ($row << 12) | ($row << 24) | ($row << 36)) & $COL_MASK;
}

sub reverse_row {
    my $row = $_[0];
    return (($row >> 12) | (($row >> 4) & 0x00F0)  | (($row << 4) & 0x0F00) | ($row << 12)) & $ROW_MASK;
}

sub print_board {
    my $board = $_[0];
    printf("-----------------------------\n");
    for (my $i=0; $i<4; $i++) {
        for (my $j=0; $j<4; $j++) {
            my $power_val = $board & 0xf;
            if ($power_val == 0) {
                printf("|%6s", " ");
            } else {
                printf("|%6u", 1 << $power_val);
            }
            $board >>= 4;
        }
        printf("|\n");
    }
    printf("-----------------------------\n");
}

sub transpose {
    my $x = $_[0];
    my $a1 = $x & 0xF0F00F0FF0F00F0F;
    my $a2 = $x & 0x0000F0F00000F0F0;
    my $a3 = $x & 0x0F0F00000F0F0000;
    my $a = $a1 | ($a2 << 12) | ($a3 >> 12);
    my $b1 = $a & 0xFF00FF0000FF00FF;
    my $b2 = $a & 0x00FF00FF00000000;
    my $b3 = $a & 0x00000000FF00FF00;
    return $b1 | ($b2 >> 24) | ($b3 << 24);
}

sub count_empty {
    my $x = $_[0];
    $x |= ($x >> 2) & 0x3333333333333333;
    $x |= ($x >> 1);
    $x = ~$x & 0x1111111111111111;
    $x += $x >> 32;
    $x += $x >> 16;
    $x += $x >> 8;
    $x += $x >> 4;
    return $x & 0xf;
}

sub execute_move_helper {
    my $row = $_[0];
    my @line;
    my $i = 0;
    my $j = 0;

    $line[0] = $row & 0xf;
    $line[1] = ($row >> 4) & 0xf;
    $line[2] = ($row >> 8) & 0xf;
    $line[3] = ($row >> 12) & 0xf;

    for ($i=0; $i<3; ++$i) {
        for ($j=$i+1; $j<4; ++$j) {
            if ($line[$j] != 0) {
                last;
            }
        }
        if ($j == 4) {
            last;
        }

        if ($line[$i] == 0) {
            $line[$i] = $line[$j];
            $line[$j] = 0;
            $i--;
        } elsif ($line[$i] == $line[$j]) {
            if ($line[$i] != 0xf) {
                $line[$i] += 1;
            }
            $line[$j] = 0;
        }
    }
    return $line[0] | ($line[1] << 4) | ($line[2] << 8) | ($line[3] << 12);
}

sub execute_move_col {
    my $board = $_[0];
    my $move = $_[1];
    my $ret = $board;
    my $t = transpose($board);

    for (my $i=0; $i<4; ++$i) {
        my $row = ($t >> ($i << 4)) & $ROW_MASK;
        if ($move == $UP) {
            $ret ^= unpack_col($row ^ execute_move_helper($row)) << ($i << 2);
        } elsif ($move == $DOWN) {
            my $rev_row = reverse_row($row);
            $ret ^= unpack_col($row ^ reverse_row(execute_move_helper($rev_row))) << ($i << 2);
        }
    }
    return $ret;
}

sub execute_move_row {
    my $board = $_[0];
    my $move = $_[1];
    my $ret = $board;

    for (my $i=0; $i<4; ++$i) {
        my $row = ($board >> ($i << 4)) & $ROW_MASK;
        if ($move == $LEFT) {
            $ret ^= ($row ^ execute_move_helper($row)) << ($i << 4);
        } elsif ($move == $RIGHT) {
            my $rev_row = reverse_row($row);
            $ret ^= ($row ^ reverse_row(execute_move_helper($rev_row))) << ($i << 4);
        }
    }
    return $ret;
}

sub execute_move {
    my $move = $_[0];
    my $board = $_[1];
    if ($move == $UP || $move == $DOWN) {
        return execute_move_col($board, $move);
    } elsif ($move == $LEFT || $move == $RIGHT) {
        return execute_move_row($board, $move);
    } else {
        return 0xFFFFFFFFFFFFFFFF;
    }
}

sub score_helper {
    my $board = $_[0];
    my $score = 0;

    for (my $j=0; $j<4; ++$j) {
        my $row = ($board >> ($j << 4)) & $ROW_MASK;
        for (my $i=0; $i<4; ++$i) {
            my $rank = ($row >> ($i << 2)) & 0xf;
            if ($rank >= 2) {
                $score += ($rank - 1) * (1 << $rank);
            }
        }
    }
    return $score;
}

sub score_board {
    my $board = $_[0];
    return score_helper($board);
}

sub ask_for_move {
    my $board = $_[0];
    print_board($board);

    while (1) {
        my $allmoves = "wsadkjhl";
        my $pos = 0;
        my $movechar = get_ch();

        if ($movechar eq "q") {
            return -1;
        } elsif ($movechar eq "r") {
            return $RETRACT;
        }
        $pos = index($allmoves, $movechar);
        if ($pos != -1) {
            return $pos % 4;
        }
    }
}

sub draw_tile {
    return (unif_random(10) < 9) ? 1 : 2;
}

sub insert_tile_rand {
    my $board = $_[0];
    my $tile = $_[1];
    my $index_ = unif_random(count_empty($board));
    my $tmp = $board;

    while (1) {
        while (($tmp & 0xf) != 0) {
            $tmp >>= 4;
            $tile <<= 4;
        }
        if ($index_ == 0) {
            last;
        }
        --$index_;
        $tmp >>= 4;
        $tile <<= 4;
    }
    return $board | $tile;
}

sub initial_board {
    my $board = draw_tile() << (unif_random(16) << 2);
    return insert_tile_rand($board, draw_tile());
}

sub play_game {
    my $MAX_RETRACT = 64;
    my $board = initial_board();
    my $scorepenalty = 0;
    my $last_score = 0;
    my $current_score = 0;
    my $moveno = 0;
    my @retract_vec;
    my @retract_penalty_vec;
    my $retract_pos = 0;
    my $retract_num = 0;

    while (1) {
        my $move = 0;
        my $tile = 0;
        my $newboard;

        clear_screen();
        for ($move=0; $move<4; $move++) {
            if (execute_move($move, $board) != $board) {
                last;
            }
        }
        if ($move == 4) {
            last;
        }

        $current_score = score_board($board) - $scorepenalty;
        printf("Move #%d, current score=%d(+%d)\n", ++$moveno, $current_score, $current_score - $last_score);
        $last_score = $current_score;

        $move = ask_for_move($board);
        if ($move < 0) {
            last;
        }

        if ($move == $RETRACT) {
            if ($moveno <= 1 || $retract_num <= 0) {
                $moveno--;
                next;
            }
            $moveno -= 2;
            if ($retract_pos == 0 && $retract_num > 0) {
                $retract_pos = $MAX_RETRACT;
            }
            $board = $retract_vec[--$retract_pos];
            $scorepenalty -= $retract_penalty_vec[$retract_pos];
            $retract_num--;
            next;
        }

        $newboard = execute_move($move, $board);
        if ($newboard == $board) {
            $moveno--;
            next;
        }

        $tile = draw_tile();
        if ($tile == 2) {
            $scorepenalty += 4;
            $retract_penalty_vec[$retract_pos] = 4;
        } else {
            $retract_penalty_vec[$retract_pos] = 0;
        }
        $retract_vec[$retract_pos++] = $board;
        if ($retract_pos == $MAX_RETRACT) {
            $retract_pos = 0;
        }
        if ($retract_num < $MAX_RETRACT) {
            $retract_num++;
        }

        $board = insert_tile_rand($newboard, $tile);
    }

    print_board($board);
    printf("Game over. Your score is %d.\n", $current_score);
}

play_game();
