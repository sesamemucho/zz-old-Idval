package Idval::SysPlugins::Abc;

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

#use Idval::Setup;
use strict;
use warnings;
no  warnings qw(redefine);
use Class::ISA;
use Carp;

use Idval::FileIO;
use base qw(Idval::Plugin);

our $name = 'abc';
our $type = 'ABC';

Idval::Common::register_provider({provides=>'reads_tags', name=>$name, type=>$type});
Idval::Common::register_provider({provides=>'writes_tags', name=>$name, type=>$type});

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    bless($self, ref($class) || $class);
    $self->init();
    return $self;
}

sub init
{
    my $self = shift;

    $self->set_param('name', $self->{NAME});
    $self->set_param('dot_map', {'ABC' => [qw{ a }]});
    $self->set_param('filetype_map', {'ABC' => [qw{ abc }]});
    $self->set_param('classtype_map', {'MUSIC' => [qw( ABC )]});
    $self->set_param('type', $type);

    #my $path = $self->find_exe_path();
    $self->set_param('path', '(Builtin)');
    $self->set_param('is_ok', 1);
    $self->set_param('status', 'ok');
}

sub read_tags
{
    my $self = shift;
    my $record = shift;
    my $line;
    my $current_tag;
    my $retval = 0;

    my $filename = $record->get_value('FILE');

    return $retval;
    
    my $path = $self->query('path');

    #$filename =~ s{/cygdrive/(.)}{$1:}; # Tag doesn't deal well with cygdrive pathnames
    foreach $line (`$path --export-tags-to=- "$filename" 2>&1`) {
        chomp $line;
        $line =~ s/\r//;
        #print "<$line>\n";

        next if $line =~ /^\s*$/;

        $line =~ m/ERROR: reading metadata/ and do {
            print 'Getters::BadFlac', $line, $filename, "\n";
            print "ref record: ", ref $record, "\n";
            #delete $record;
            $retval = 1;
            last;
        };

        $line =~ m/^(\S+)\s*=\s*(.*)/ and do {
            $current_tag = uc($1);
            $record->add_tag($current_tag, $2);
            next;
        };

        $record->add_to_tag($current_tag, "\n$line");
    }

    #print "\nGot tag:\n";
    #print join("\n", $record->format_record());

    $record->commit_tags();

    return $retval;
}

sub write_tags
{
    my $self = shift;
    my $record = shift;

    return 0 if !$self->query('is_ok');

    my $filename = $record->get_value('FILE');
    my $path = $self->query('path');

    Idval::Common::run($path, '--remove-all-tags', $filename);
    my @taglist;
    foreach my $tagname ($record->get_all_keys())
    {
        push(@taglist, $record->get_value_as_arg('--set-tag=' . $tagname . '=', $tagname));
    }

    my $status = Idval::Common::run($path,
                                    @taglist,
                                    $filename);

    return $status;
}

sub create_records
{
    my $self = shift;
    my $fname = shift;
    my $path = shift;
    my $class = shift;
    my $type = shift;
    my $srclist = shift;

    my $fh = Idval::FileIO->new($fname, "r") || croak "Can't open \"$fname\" for reading: $!\n";
    my $text .= do { local $/; <$fh> };
    $fh->close();

    my $item;

    foreach my $line (split("\n", $text))
    {
        $line =~ m/^X:(\d+)/ and do {
            $item = $1;

            my $rec = Idval::Record->new($path . '%%' . $item);
            $rec->add_tag('CLASS', $class);
            $rec->add_tag('TYPE', $type);

            $srclist->add($rec);
        };
    }

}

1;