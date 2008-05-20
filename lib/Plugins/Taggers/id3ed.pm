package Idval::SysPlugins::Id3ed;

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
use Idval::Common;
use Class::ISA;

use base qw(Idval::Plugin);

our $name = 'id3ed';
our $type = 'MP3';
our %xlat_tags = 
    ( TIME => 'DATE',
      YEAR => 'DATE',
      NAME => 'TITLE',
      TRACK => 'TRACKNUMBER',
      TRACKNUM => 'TRACKNUMBER'
    );

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
    $self->set_param('dot_map', {'MP3' => [qw{ m }]});
    $self->set_param('filetype_map', {'MP3' => [qw{ mp3 }]});
    $self->set_param('classtype_map', {'MUSIC' => [qw( MP3 )]});
    $self->set_param('type', $type);

    $self->find_and_set_exe_path();
}

sub read_tags
{
    my $self = shift;
    my $record = shift;
    my $line;
    my $current_tag;
    my $retval = 0;

    return $retval if !$self->query('is_ok');

    my $filename = $record->get_value('FILE');
    my $path = $self->query('path');

    $filename =~ s{/cygdrive/(.)}{$1:}; # Tag doesn't deal well with cygdrive pathnames
    foreach $line (`$path --hideinfo --hidenames "$filename" 2>&1`) {
        chomp $line;
        $line =~ s/\r//;
        #print "<$line>\n";

        next if $line =~ /^Tag /;
        next if $line =~ /^Copyright /;
        next if $line =~ /^Version /;
        next if $line =~ /^\s*$/;

        $line =~ m/^File has no known tags./ and do {
            $retval = 1;
            last;
        };

        $line =~ m/^(\S+):\s+(.*)/ and do {
            $current_tag = $1;
            $current_tag = $xlat_tags{$current_tag} if exists $xlat_tags{$current_tag};
            $record->add_tag($current_tag, $2);
            next;
        };

        $line =~ m/^(\S+)\s*=\s*(.*)/ and do {
            $current_tag = $1;
            $current_tag = $xlat_tags{$current_tag} if exists $xlat_tags{$current_tag};
            $record->add_tag($current_tag, $2);
            next;
        };

        $record->add_to_tag($current_tag, "$line");
    }

    $record->commit_tags();

    return $retval;
}

sub write_tags
{
    my $self = shift;
    my $record = shift;

    return 0 if !$self->query('is_ok');

    my $filename = $record->get_name();
    my $path = $self->query('path') . " ";

    Idval::Common::run($path, '--remove', $filename);

    my $status = Idval::Common::run($path,
                                    $record->get_value_as_arg('--title ', 'TITLE'),
                                    $record->get_value_as_arg('--artist ', 'ARTIST'),
                                    $record->get_value_as_arg('--album ', 'ALBUM'),
                                    $record->get_value_as_arg('--year ', 'DATE'),
                                    $record->get_value_as_arg('--comment ', 'COMMENT'),
                                    $record->get_value_as_arg('--track ', 'TRACKNUMBER'),
                                    $record->get_value_as_arg('--genre ', 'GENRE'),
                                    $filename);

    return $status;
}

1;