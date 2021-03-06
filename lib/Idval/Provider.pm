package Idval::Provider;

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

use Config;
use File::Spec;
use List::Util;
use Data::Dumper;

use Idval::I18N;
use Idval::Logger qw(verbose fatal);
use Idval::Common;
use Idval::FileIO;
use Idval::Record;

sub new
{
    my $class = shift;
    my $config = shift;
    my $name = shift;
    my $self = {};
    bless($self, ref($class) || $class);
    $self->{PARAMS} = {};
    $self->{CONFIG} = $config;
    $self->{NAME} = $name;
    $self->{ENDPOINT_PAIRS}->{PAIRS} = {};
    $self->{ENDPOINT_PAIRS}->{SRCS} = {};
    $self->{ENDPOINT_PAIRS}->{DESTS} = {};

    # Just make sure these keys exist
    $self->{FWD_MAPPING} = {};
    $self->{REV_MAPPING} = {};
    $self->{BYPASS_MAPPING} = 0;

    return $self;
}

sub query
{
    my $self = shift;
    my $key = shift;

    if (exists($self->{PARAMS}->{$key}))
    {
        return $self->{PARAMS}->{$key};
    }
    else
    {
        return;
    }
}

sub set_param
{
    my $self = shift;
    my $key = shift;
    my $value = shift;

    $self->{PARAMS}->{$key} = $value;

    return;
}

sub create_records
{
    my $self = shift;
    my $arglist = shift;

    my $fname   = $arglist->{filename};
    my $path    = $arglist->{path};
    my $class   = $arglist->{class};
    my $type    = $arglist->{type};
    my $srclist = $arglist->{srclist};

    my $rec = Idval::Record->new({FILE=>$path, CLASS=>$class, TYPE=>$type});

    $srclist->add($rec);

    return;
}

# endpoint_pairs are for use by the 'about' command

# make_endpoint_pair is a class method; it does not need an object
sub make_endpoint_pair
{
    my $from = uc shift;
    my $to = uc shift;

    return $from . ':' . $to;
}

sub has_endpoint_pair
{
    my $self = shift;
    my $from = uc shift;
    my $to = uc shift;
    my $endpoint_pair = make_endpoint_pair($from, $to);

    return exists ($self->{ENDPOINT_PAIRS}->{PAIRS}->{$endpoint_pair});
}

sub add_endpoint_pair
{
    my $self = shift;
    my $from = uc shift;
    my $to = uc shift;
    my $endpoint_pair = make_endpoint_pair($from, $to);

    $self->{ENDPOINT_PAIR}->{PAIR} = $endpoint_pair;
    $self->{ENDPOINT_PAIR}->{SRC} = $from;
    $self->{ENDPOINT_PAIR}->{DEST} = $to;

    return $endpoint_pair;
}

sub get_endpoint_pair
{
    my $self = shift;

    return $self->{ENDPOINT_PAIR}->{PAIR};
}

sub get_source
{
    my $self = shift;

    return $self->{ENDPOINT_PAIR}->{SRC};
}

sub get_destination
{
    my $self = shift;

    return $self->{ENDPOINT_PAIR}->{DEST};
}

sub get_source_filepath
{
    my $self = shift;
    my $rec = shift;

    return $rec->get_name();
}

sub get_dest_filename
{
    my $self = shift;
    my $rec = shift;
    my $dest_name = shift;
    my $dest_ext = shift;

    $dest_name =~ s{\.[^.]+$}{.$dest_ext}x;

    return $dest_name;
}

sub _find_exe_path
{
    my $self = shift;
    my $name = shift || $self->{NAME};
    my $file = $name;
    my $exe = '';
    my $testexe;

    if ($^O ne 'VMS')
    {
        if (!Idval::FileIO::idv_test_exists($file))
        {
            $file .= $Config{_exe} unless $file =~ m/$Config{_exe}$/ix;
        }
    }

    foreach my $dir (File::Spec->path())
    {
        $testexe = File::Spec->catfile($dir, $file);
        if (Idval::FileIO::idv_test_exists($testexe))
        {
            $exe = $testexe;
            last;
        }
    }

    if (!$exe)
    {
        # Didn't find it in the path. Did the user specify a path?
        my $exelist = $self->{CONFIG}->get_list_value('command_path', {'command_name' => $name});

        foreach my $testexe (@{$exelist})
        {
            verbose("Checking \"[_1]\n", $testexe); ##debug1
            $testexe = Idval::Common::expand_tilde($testexe);
            if (-e $testexe)
            {
                $exe = $testexe;
                verbose("Found \"[_1]\"\n", $testexe); ##debug1
                last;
            }
        }
    }

    $exe = undef if !$exe;
    #fatal("Could not find program \"[_1]\"\n", $name) if !$exe;
    return $exe;
}

sub find_and_set_exe_path
{
    my $self = shift;
    my $name = shift || $self->{NAME};
    my $lh = Idval::I18N->idv_get_handle() || die "Can't get language handle.";
    $name = $lh->idv_getkey('extern', $name);

    my $path = $self->_find_exe_path($name);

    $self->set_param('path', $path);
    $self->set_param('is_ok', $path ? 1 : 0);
    $self->set_param('status', $path ? $lh->maketext('ok') : $lh->maketext("Program \"[_1]\" not found.", $name));

    return $path;
}

# The idval.cfg file has mappings to go from <whatever> tag names to id3v2 names.

sub set_tagname_mappings
{
    my $self = shift;
    my $config = shift;
    my $type = shift;

    # Forward mapping is XXX to ID3v2
    # Reverse mapping is ID3v2 to XXX
    $self->{FWD_MAPPING} = $config->merge_blocks({'config_group' => 'tag_mappings',
                                                  'TYPE' => $type,
                                                 });

    foreach my $key (keys %{$self->{FWD_MAPPING}})
    {
        $self->{REV_MAPPING}->{$self->{FWD_MAPPING}->{$key}} = $key;
    }

    return;
}

sub map_to_id3v2
{
    my $self = shift;
    my $tagname = shift;
    my $value = $tagname;

    if (exists($self->{FWD_MAPPING}->{$tagname}) and !$self->{BYPASS_MAPPING})
    {
        $value = $self->{FWD_MAPPING}->{$tagname};
    }

    return $value;
}

sub map_from_id3v2
{
    my $self = shift;
    my $tagname = shift;
    my $value = $tagname;

    if (exists($self->{REV_MAPPING}->{$tagname}) and !$self->{BYPASS_MAPPING})
    {
        $value = $self->{REV_MAPPING}->{$tagname};
    }

    return $value;
}

# For any plugin that needs to clean up
sub close
{
    my $self = shift;

    return 0;
}

1;
