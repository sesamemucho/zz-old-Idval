package Idval::Select;

# Copyright 2008 Bob Forgey <rforgey@grumpydogconsulting.com>

# This file is part of Idval.

# Idval is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Idval is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with Idval.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Data::Dumper;
use English '-no_match_vars';
use Memoize;
use Scalar::Util;
use List::Util qw(first);

use Idval::Logger qw(verbose fatal);
use Idval::Common;
use Idval::Validate;

#
# Given a list of selectors, constructs a Select object. This object, given a hash of key=>value pairs,
# returns True or False depending on whether the keys and values match the rules in the selectors.
#
# Keys are assumed to be upper case. Value comparisons are case-insensitive.
#

my %compare_function =
    (
     '==' => {FUNC => {NUM => \&Idval::Select::cmp_eq_num,
                       STR => \&Idval::Select::cmp_eq_str},
              NAME => {NUM => 'Idval::Select::cmp_eq_num',
                       STR => 'Idval::Select::cmp_eq_str'}},
     'eq' => {FUNC => {NUM => \&Idval::Select::cmp_eq_num,
                       STR => \&Idval::Select::cmp_eq_str},
              NAME => {NUM => 'Idval::Select::cmp_eq_num',
                       STR => 'Idval::Select::cmp_eq_str'}},
     'has'=> {FUNC => {NUM => \&Idval::Select::cmp_has_str,
                       STR => \&Idval::Select::cmp_has_str},
              NAME => {NUM => 'Idval::Select::cmp_has_str',
                       STR => 'Idval::Select::cmp_has_str'}},
     '!=' => {FUNC => {NUM => \&Idval::Select::cmp_ne_num,
                       STR => \&Idval::Select::cmp_ne_str},
              NAME => {NUM => 'Idval::Select::cmp_ne_num',
                       STR => 'Idval::Select::cmp_ne_str'}},
     'ne' => {FUNC => {NUM => \&Idval::Select::cmp_ne_num,
                       STR => \&Idval::Select::cmp_ne_str},
              NAME => {NUM => 'Idval::Select::cmp_ne_num',
                       STR => 'Idval::Select::cmp_ne_str'}},
     '=~' => {FUNC => {NUM => \&Idval::Select::cmp_re_eq,
                       STR => \&Idval::Select::cmp_re_eq},
              NAME => {NUM => 'Idval::Select::cmp_re_eq',
                       STR => 'Idval::Select::cmp_re_eq'}},
     '!~' => {FUNC => {NUM => \&Idval::Select::cmp_re_ne,
                       STR => \&Idval::Select::cmp_re_ne},
              NAME => {NUM => 'Idval::Select::cmp_re_ne',
                       STR => 'Idval::Select::cmp_re_ne'}},
     '<'  => {FUNC => {NUM => \&Idval::Select::cmp_lt_num,
                       STR => \&Idval::Select::cmp_lt_str},
              NAME => {NUM => 'Idval::Select::cmp_lt_num',
                       STR => 'Idval::Select::cmp_lt_str'}},
     'lt' => {FUNC => {NUM => \&Idval::Select::cmp_lt_num,
                       STR => \&Idval::Select::cmp_lt_str},
              NAME => {NUM => 'Idval::Select::cmp_lt_num',
                       STR => 'Idval::Select::cmp_lt_str'}},
     '>'  => {FUNC => {NUM => \&Idval::Select::cmp_gt_num,
                       STR => \&Idval::Select::cmp_gt_str},
              NAME => {NUM => 'Idval::Select::cmp_gt_num',
                       STR => 'Idval::Select::cmp_gt_str'}},
     'gt' => {FUNC => {NUM => \&Idval::Select::cmp_gt_num,
                       STR => \&Idval::Select::cmp_gt_str},
              NAME => {NUM => 'Idval::Select::cmp_gt_num',
                       STR => 'Idval::Select::cmp_gt_str'}},
     '<=' => {FUNC => {NUM => \&Idval::Select::cmp_le_num,
                       STR => \&Idval::Select::cmp_le_str},
              NAME => {NUM => 'Idval::Select::cmp_le_num',
                       STR => 'Idval::Select::cmp_le_str'}},
     '=<' => {FUNC => {NUM => \&Idval::Select::cmp_le_num,
                       STR => \&Idval::Select::cmp_le_str},
              NAME => {NUM => 'Idval::Select::cmp_le_num',
                       STR => 'Idval::Select::cmp_le_str'}},
     'le' => {FUNC => {NUM => \&Idval::Select::cmp_le_num,
                       STR => \&Idval::Select::cmp_le_str},
              NAME => {NUM => 'Idval::Select::cmp_le_num',
                       STR => 'Idval::Select::cmp_le_str'}},
     '>=' => {FUNC => {NUM => \&Idval::Select::cmp_ge_num,
                       STR => \&Idval::Select::cmp_ge_str},
              NAME => {NUM => 'Idval::Select::cmp_ge_num',
                       STR => 'Idval::Select::cmp_ge_str'}},
     '=>' => {FUNC => {NUM => \&Idval::Select::cmp_ge_num,
                       STR => \&Idval::Select::cmp_ge_str},
              NAME => {NUM => 'Idval::Select::cmp_ge_num',
                       STR => 'Idval::Select::cmp_ge_str'}},
     'ge' => {FUNC => {NUM => \&Idval::Select::cmp_ge_num,
                       STR => \&Idval::Select::cmp_ge_str},
              NAME => {NUM => 'Idval::Select::cmp_ge_num',
                       STR => 'Idval::Select::cmp_ge_str'}},
     'passes' => {FUNC => {NUM => \&Idval::Select::passes,
                       STR => \&Idval::Select::passes},
              NAME => {NUM => 'Idval::Select::passes',
                       STR => 'Idval::Select::passes'}},
     'fails' => {FUNC => {NUM => \&Idval::Select::fails,
                       STR => \&Idval::Select::fails},
              NAME => {NUM => 'Idval::Select::fails',
                       STR => 'Idval::Select::fails'}},
     );

my %assignments =
    (
     '=' => 1,                  # For now...
     '+=' => 1,
    );

sub cmp_re_eq { my ($aref, $val) = @_; return first { "$_" =~ m{$val}i } @{$aref}; }
sub cmp_re_ne { my ($aref, $val) = @_; return first { "$_" !~ m{$val}i } @{$aref}; }

sub cmp_eq_num { my ($aref, $val) = @_; return first { $_ == $val } @{$aref}; }
sub cmp_ne_num { my ($aref, $val) = @_; return first { $_ != $val } @{$aref}; }
sub cmp_lt_num { my ($aref, $val) = @_; return first { ($_ eq "" ? 0 : $_) < ($val eq "" ? 0 : $val) } @{$aref}; }
sub cmp_gt_num { my ($aref, $val) = @_; return first { ($_ eq "" ? 0 : $_) > ($val eq "" ? 0 : $val) } @{$aref}; }
sub cmp_le_num { my ($aref, $val) = @_; return first { ($_ eq "" ? 0 : $_) <= ($val eq "" ? 0 : $val) } @{$aref}; }
sub cmp_ge_num { my ($aref, $val) = @_; return first { ($_ eq "" ? 0 : $_) >= ($val eq "" ? 0 : $val) } @{$aref}; }

sub cmp_eq_str { my ($aref, $val) = @_; return first { lc $_ eq lc $val } @{$aref}; }
sub cmp_ne_str { my ($aref, $val) = @_; return first { lc $_ ne lc $val } @{$aref}; }
sub cmp_lt_str { my ($aref, $val) = @_; return first { lc $_ lt lc $val } @{$aref}; }
sub cmp_gt_str { my ($aref, $val) = @_; return first { lc $_ gt lc $val } @{$aref}; }
sub cmp_le_str { my ($aref, $val) = @_; return first { lc $_ le lc $val } @{$aref}; }
sub cmp_ge_str { my ($aref, $val) = @_; return first { lc $_ ge lc $val } @{$aref}; }

sub cmp_has_str { my ($aref, $val) = @_; return first { (index(lc "$_", lc "$val") != -1) } @{$aref}; }

# sub cmp_re_eq { return "$_[0]" =~ m{$_[1]}i; }
# sub cmp_re_ne { return "$_[0]" !~ m{$_[1]}i; }

# sub cmp_eq_num { return $_[0] == $_[1]; }
# sub cmp_ne_num { return $_[0] != $_[1]; }
# sub cmp_lt_num { return ($_[0] eq "" ? 0 : $_[0]) < ($_[1] eq "" ? 0 : $_[1]); }
# sub cmp_gt_num { return ($_[0] eq "" ? 0 : $_[0]) > ($_[1] eq "" ? 0 : $_[1]); }
# sub cmp_le_num { return ($_[0] eq "" ? 0 : $_[0]) <= ($_[1] eq "" ? 0 : $_[1]); }
# sub cmp_ge_num { return ($_[0] eq "" ? 0 : $_[0]) >= ($_[1] eq "" ? 0 : $_[1]); }

# sub cmp_eq_str { return lc $_[0] eq lc $_[1]; }
# sub cmp_ne_str { return lc $_[0] ne lc $_[1]; }
# sub cmp_lt_str { return lc $_[0] lt lc $_[1]; }
# sub cmp_gt_str { return lc $_[0] gt lc $_[1]; }
# sub cmp_le_str { return lc $_[0] le lc $_[1]; }
# sub cmp_ge_str { return lc $_[0] ge lc $_[1]; }

# sub cmp_has_str { return (index(lc "$_[0]", lc "$_[1]") != -1); }

# Check to see if we have a valid function in the package space 'Idval::ValidateFuncs'
sub check_function
{
    my $funcname = shift;

    return 0 unless exists $Idval::ValidateFuncs::{$funcname};

    my $func = $Idval::ValidateFuncs::{$funcname};

    return defined(*$func{CODE});
}

sub passes
{
    my $selectors = $_[0];
    #my $aref = $_[1];
    my $tagname = $_[1];
    my $funcname = $_[2];
    fatal("Unknown function Idval::ValidateFuncs::[_1]", $funcname) unless check_function($funcname);
    my $func = \&{"Idval::ValidateFuncs::$funcname"};
    # The commas are for (in case someone wants to use multiple ... (figure out why or remove) XXX
    #print STDERR "funcname is \"$funcname\", aref is ", Dumper($aref);
    #return first { &$func($selectors, $_) } @{$aref};
    #print STDERR "funcname is \"$funcname\", tagname is \"$tagname\"\n";
    return &$func($selectors, $tagname);
}

sub fails
{
    return !passes(@_);
}

sub get_compare_function
{
    my $operand = shift;
    my $compare_value = shift;
    my $func_type = Scalar::Util::looks_like_number($compare_value) ? 'NUM' : 'STR';

    return $compare_function{$operand}->{FUNC}->{$func_type};
}

sub get_compare_function_name
{
    my $operand = shift;
    my $compare_value = shift;
    my $func_type = Scalar::Util::looks_like_number($compare_value) ? 'NUM' : 'STR';

    return $compare_function{$operand}->{NAME}->{$func_type};
}

# Operators that are *not* composed of metacharacters (such as 'gt',
# 'le', etc.) need to have spaces around them, so (say) "file=goo"
# isn't parsed as "fi le =goo". Also, longer operators should be
# matched for before shorter operators, so that "foo =~ boo" isn't
# matched as "foo = ~boo".

memoize('get_op_regex');
memoize('get_cmp_regex');
memoize('get_assign_regex');

sub get_regex
{
    my @op_hash_refs = @_;

    #my @op_set = map(quotemeta, (keys %compare_function, keys %assignments));
    my @op_set = map {quotemeta $_} map {keys %{$_}} @_;
    my @ops_that_dont_need_spaces = grep {/\\/} @op_set;
    my @ops_that_need_spaces = grep {!/\\/} @op_set;
    # Sort in reverse order of length so that (for instance) 'foo =~ boo' doesn't
    # get matched as (foo)(=)(~ boo)
    #my $op_string_no_spaces = join('|',  sort {length($b) <=> length($a)} @ops_that_dont_need_spaces);
    my $op_string_no_spaces  = @ops_that_dont_need_spaces ? 
        '\s*' . join('\s*|\s*',  sort {length($b) <=> length($a)} @ops_that_dont_need_spaces) . '\s*' :
        '';
    my $op_string_with_spaces = @ops_that_need_spaces ?
        '\s+' . join('\s+|\s+',  sort {length($b) <=> length($a)} @ops_that_need_spaces) . '\s+' :
        '';

    my $combo;
    if ($op_string_with_spaces and $op_string_no_spaces)
    {
        $combo = $op_string_with_spaces . '|' . $op_string_no_spaces;
    }
    elsif ($op_string_with_spaces)
    {
        $combo = $op_string_with_spaces;
    }
    else
    {
        $combo = $op_string_no_spaces;
    }

    verbose("\n\nregex is: \"[_1]\"\n\n\n", $combo);
    return qr/$combo/;
}

sub get_op_regex
{
    return get_regex(\%compare_function, \%assignments);
}

sub get_cmp_regex
{
    return get_regex(\%compare_function);
}

sub get_assign_regex
{
    return get_regex(\%assignments);
}

1;
