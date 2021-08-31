#!/usr/bin/env perl

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

our $TABLESIZE = 65536;
our @row_left_table;
our @row_right_table;
our @score_table;

sub init_tables {
    my $row = 0;
    my $rev_row = 0;
    my $result = 0;
    my $rev_result = 0;

    do {
        my $i = 0;
        my $j = 0;
        my $score = 0;
        my @line;

        @line[0] = ($row >> 0) & 0xf;
        @line[1] = ($row >> 4) & 0xf;
        @line[2] = ($row >> 8) & 0xf;
        @line[3] = ($row >> 12) & 0xf;

        for ($i=0; $i<4; $i++) {
            my $rank = @line[$i];

            if ($rank >= 2) {
                $score += ($rank - 1) * (1 << $rank);
            }
        }
        @score_table[$row] = $score;

        for ($i=0; $i<3; $i++) {
            for ($j=$i+1; $j<4; ++$j) {
                if (@line[$j] != 0) {
                    last;
                }
            }
            if ($j == 4) {
                last;
            }

            if (@line[$i] == 0) {
                @line[$i] = @line[$j];
                @line[$j] = 0;
                $i--;
            } elsif (@line[$i] == @line[$j]) {
                if (@line[$i] != 0xf) {
                    @line[$i]++;
                }
                @line[$j] = 0;
            }
        }

        $result = (@line[0] << 0) | (@line[1] << 4) | (@line[2] << 8) | (@line[3] << 12);
        $rev_result = reverse_row($result);
        $rev_row = reverse_row($row);

        @row_left_table[$row] = $row ^ $result;
        @row_right_table[$rev_row] = $rev_row ^ $rev_result;
    } while ($row++ != ($TABLESIZE - 1));
}

sub execute_move_col {
    my $board = $_[0];
    my $table = $_[1];
    my $ret = $board;
    my $t = transpose($board);

    $ret ^= unpack_col(@$table[($t >> 0) & $ROW_MASK]) << 0;
    $ret ^= unpack_col(@$table[($t >> 16) & $ROW_MASK]) << 4;
    $ret ^= unpack_col(@$table[($t >> 32) & $ROW_MASK]) << 8;
    $ret ^= unpack_col(@$table[($t >> 48) & $ROW_MASK]) << 12;
    return $ret;
}

sub execute_move_row {
    my $board = $_[0];
    my $table = $_[1];
    my $ret = $board;

    $ret ^= (@$table[($board >> 0) & $ROW_MASK]) << 0;
    $ret ^= (@$table[($board >> 16) & $ROW_MASK]) << 16;
    $ret ^= (@$table[($board >> 32) & $ROW_MASK]) << 32;
    $ret ^= (@$table[($board >> 48) & $ROW_MASK]) << 48;
    return $ret;
}

sub execute_move() {
    my $move = $_[0];
    my $board = $_[1];
    if ($move == $UP) {
        return execute_move_col($board, \@row_left_table);
    } elsif ($move == $DOWN) {
        return execute_move_col($board, \@row_right_table);
    } elsif ($move == $LEFT) {
        return execute_move_row($board, \@row_left_table);
    } elsif ($move == $RIGHT) {
        return execute_move_row($board, \@row_right_table);
    } else {
        return 0xFFFFFFFFFFFFFFFF;
    }
}

sub score_helper {
    my $board = $_[0];
    my $table = $_[1];
    return @$table[($board >> 0) & $ROW_MASK] + @$table[($board >> 16) & $ROW_MASK] +
        @$table[($board >> 32) & $ROW_MASK] + @$table[($board >> 48) & $ROW_MASK];
}

sub score_board {
    my $board = $_[0];
    return score_helper($board, \@score_table);
}

$a = 0xABCD;
$a = reverse_row($a);
$b = unpack_col($a);
printf("%016X\n", $a);
printf("%016X\n", $b);
print_board($b);
$b=transpose($b);
print_board($b);
print count_empty($b);




init_tables();
