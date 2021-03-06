package Idval::DataFile;

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
use IO::File;
use Text::Balanced qw (
                       extract_tagged
                      );
use Idval::Logger qw(fatal);
use Idval::Common;
use Idval::Record;
use Idval::Collection;

sub new
{
    my $class = shift;
    my $self = {};
    bless($self, ref($class) || $class);
    $self->_init(@_);
    return $self;
}

sub _init
{
    my $self = shift;
    $self->{DATAFILE} = shift;
    $self->{TYPEMAP} = Idval::Common::get_common_object('typemap');
    $self->{BLOCKS} = $self->parse();

    return;
}

sub parse
{
    my $self = shift;

    my $datafile = $self->{DATAFILE};
    my $collection = Idval::Collection->new({'source' => $datafile});
    if (not $datafile)
    {
        $self->{BLOCKS} = $collection;
        return $collection;
    }

    my $fh = Idval::FileIO->new($datafile, "r") || fatal("Can't open tag data file \"[_1]\" for reading: [_2]\n", $datafile, $!);

    my $line;

    # Get the data related to the collection itself
    while(defined($line = <$fh>))
    {
        chomp $line;
        next if $line =~ m/^\#/x;
        # A blank line delimits this header information block
        last if $line =~ m/^\s*$/;

        $line =~ m{ ^created_on:\s+(.*?)$ }x and do {
            $collection->{CREATIONDATE} = $1;
            next;
        };

        $line =~ m{ ^source:\s+(.*?)$ }x and do {
            $collection->{SOURCE} = $1;
            next;
        };

        $line =~ m{ ^encoding:\s+(.*?)$ }x and do {
            $collection->{ID3_ENCODING} = $1;
            next;
        };
    }

    my $str = do { local $/; <$fh> };
    $fh->close();

    # Split the file up into blocks. Each block (of tag definitions)
    # must start with a 'FILE ='.
    my @blocks = ($str =~ m{(^FILE\s*=.*?)(?=^FILE\s*=|\z)}gms);

    # Now massage each block so we have one tag definition per item
    foreach my $block (@blocks)
    {
        my $accumulate_line = '';
        my @tagdefs = ();
        $block =~ s/\n\r/\n/g;
        $block =~ s/\r//g;
        foreach my $line (split(/\n/, $block))
        {
            chomp $line;
            next if $line =~ m/^\#/mx;

            if ($line =~ m/^ ?$/)
            {
                push(@tagdefs, $accumulate_line) if $accumulate_line;
                $accumulate_line = '';
                next;
            }

            if ($line =~ m/^  (.*)/)
            {
                $accumulate_line .= "\n" . $1;
            }
            else
            {
                push(@tagdefs, $accumulate_line) if $accumulate_line;
                $accumulate_line = $line;
            }
        }
        push(@tagdefs, $accumulate_line) if $accumulate_line;

        $collection->add($self->parse_tagdefs(\@tagdefs));
    }

    $self->{BLOCKS} = $collection;
    return $collection;
}

#sub parse_block
sub parse_tagdefs
{
    my $self = shift;
    my $blockref = shift;
    my %hash;

    foreach my $line (@{$blockref})
    {
        if ($line =~ m/\A([^=\s]+)\s*\+=\s*(.*)\z/msx)
        {
            if (!exists ($hash{$1}))
            {
                fatal("\"Append\" line too early in tag data file (no previous value): \"[_1]\"\n", $line);
            }
            elsif (ref $hash{$1} ne 'ARRAY')
            {
                $hash{$1} = [$hash{$1}, $2];
            }
            else
            {
                push(@{$hash{$1}}, $2);
            }
        }
        elsif ($line =~ m/\A([^=\s]+)\s*=\s*(.*)\z/msx)
        {
            $hash{$1} = $2;
        }
        else
        {
            $line =~ s/\r/\<CR\>/g;
            fatal("Unrecognized line in tag data file: \"[_1]\"\n", $line);
        }
    }

    if (!exists($hash{FILE}))
    {
        fatal("No FILE tag in tag data record \"[_1]\"\n", join("\n", @{$blockref}));
    }

    my $rec = Idval::Record->new({FILE=>$hash{FILE}});

    if (!exists($hash{TYPE}))
    {
        # Make a guess
        my $filetype = $self->{TYPEMAP}->get_filetype_from_file($hash{FILE});
        #print STDERR "DataFile: type guess from \"$hash{FILE}\" is \"$filetype\"\n";
        if ($filetype)
        {
            #print STDERR "DataFile: Adding TYPE and CLASS to $hash{FILE}\n";
            $rec->add_tag('TYPE', $filetype);
            $rec->add_tag('CLASS', $self->{TYPEMAP}->get_class_from_filetype($filetype));
        }
    }
    elsif (!exists($hash{CLASS}))
    {
        # TYPE exists, but not CLASS, so fill it in
        #print STDERR "DataFile: Adding TYPE to $hash{FILE}\n";
        $rec->add_tag('CLASS', $self->{TYPEMAP}->get_class_from_filetype($hash{TYPE}));
    }
    # A CLASS tag without a TYPE tag is anomalous, but don't deal with it here.

    foreach my $key (keys %hash)
    {
        # The key already exists, so don't add it
        next if ($key eq 'FILE');
        #print STDERR "DataFile: Adding key \"$key\", value \"$hash{$key}\"\n";
        $rec->add_tag($key, $hash{$key});
    }

    #print STDERR "DataFile: hash is: ", Dumper(\%hash);
    #print STDERR "DataFile: Returning ", Dumper($rec);
    return $rec;
}

sub get_reclist
{
    my $self = shift;

    #print STDERR "2: ", Dumper($self);
    #print STDERR "2: ref ", ref $self->{BLOCKS}, "\n";
    return $self->{BLOCKS};
}

1;
