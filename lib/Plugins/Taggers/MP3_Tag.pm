package Idval::SysPlugins::MP3_Tag;

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

use base qw(Idval::Plugin);

my $req_status = eval {require MP3::Tag};
my $req_msg = !defined($req_status) ? "$!" : 
                   $req_status == 0 ? "$@" :
                                       "Load OK";

if ($req_msg ne 'Load OK')
{
    print "Oops; let's try again for MP3::Tag\n";
    use lib Idval::Common::get_top_dir('lib/perl/MP3-Tag');

    $req_status = eval {require MP3::Tag};
    $req_msg = 'Load OK' if (defined($req_status) && ($req_status != 0));
}

my $name = 'MP3_Tag';
my $type = 'MP3';

Idval::Common::register_provider({provides=>'reads_tags', name=>$name, type=>$type, weight=>50});

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

    $self->set_param('path', "(Perl module}");
    $self->set_param('is_ok', $req_msg eq "Load OK");
    if ($req_msg eq "No such file or directory")
    {
        $req_msg = "Perl module MP3::Tag not found";
    }
    $self->set_param('status', $req_msg);

    return;
}

sub read_tags
{
    my $self = shift;
    my $tag_record = shift;
    my $line;
    my $current_tag;
    my $retval = 0;

    return $retval if !$self->query('is_ok');

    my $filename = $tag_record->get_value('FILE');

    my $mp3 = MP3::Tag->new($filename);
    my ($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();

    $tag_record->add_tag('TITLE', $title);
    $tag_record->add_tag('TRACKNUMBER', $track);
    $tag_record->add_tag('ARTIST', $artist);
    $tag_record->add_tag('ALBUM', $album);
    $tag_record->add_tag('COMMENT', $comment);
    $tag_record->add_tag('DATE', $year);
    $tag_record->add_tag('GENRE', $genre);

    #print join("\n", $tag_record->format_record());
    if (exists $mp3->{ID3v2})
    {
        my $h = $mp3->get_id3v2_frame_ids();
        my $name;
        my $info;
        foreach my $key (keys %$h)
        {
            ($info, $name) = $mp3->{ID3v2}->get_frame($key);

            if (ref $info eq 'HASH')
            {
                print "$name:\n";
                foreach my $infokey (keys %$info)
                {
                    print "   $infokey => ", substr($infokey, 0, 1) eq '_' ? 'Binary' : $info->{$infokey}, "\n";
                }
            }
            else
            {
                print "$name, $info\n";
            }
        }
    }

    return $retval;
}

1;
