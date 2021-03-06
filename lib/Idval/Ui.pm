package Idval::Ui;

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
use Storable;
use Config;
use English '-no_match_vars';
use File::Basename;
use File::Path;
use File::Spec;

use Idval::Logger qw(verbose chatty idv_dbg fatal);
use Idval::Common;
use Idval::Config;
use Idval::FileIO;
use Idval::TypeMap;
use Idval::Collection;
use Idval::Record;
use Idval::DataFile;
use Idval::DoDots;

my $srclist;

sub get_sysconfig_file
{
    my $datadir = shift;
    my $cfgname = '';

    if (Idval::FileIO::idv_test_exists("$datadir/idval.xml"))
    {
        $cfgname = "$datadir/idval.xml";
    }
    elsif (Idval::FileIO::idv_test_exists("$datadir/idval.cfg"))
    {
        $cfgname = "$datadir/idval.cfg";
    }
    else
    {
        fatal("No idval configuration file found in \"[_1]\"\n", $datadir);
    }

    return $cfgname;
}

sub get_userconfig_file_choices
{
    my $osname = $Config{'osname'};
    my @choices;

    if ($osname eq 'MSWin32')
    {
        push(@choices, "$ENV{HOME}/idvaluser.cfg") if exists($ENV{HOME});
        push(@choices, "idvaluser.cfg");
    }
    elsif ($osname =~ m/ux$/ix or $osname =~ m/cygwin/ix)
    {
        push(@choices, "$ENV{HOME}/.idvalrc") if exists($ENV{HOME});
        push(@choices, ".idvalrc");
    }
    else
    {
        push(@choices, "$ENV{HOME}/idvaluser.cfg") if exists($ENV{HOME});
        push(@choices, "idvaluser.cfg");
    }

    return @choices;
}

sub get_userconfig_file
{
    my $osname = $Config{'osname'};
    my $cfgname = '';

    if ($osname eq 'MSWin32')
    {
        $cfgname = (exists($ENV{HOME}) && Idval::FileIO::idv_test_exists("$ENV{HOME}/idvaluser.cfg")) ? "$ENV{HOME}/idvaluser.cfg"
                 : Idval::FileIO::idv_test_exists("idvaluser.cfg")                                    ? "idvaluser.cfg"
                 : '';
    }
    elsif ($osname =~ m/ux$/ix or $osname =~ m/cygwin/ix)
    {
        $cfgname = (exists($ENV{HOME}) && Idval::FileIO::idv_test_exists("$ENV{HOME}/.idvalrc")) ? "$ENV{HOME}/.idvalrc"
                 : Idval::FileIO::idv_test_exists(".idvalrc")                                    ? ".idvalrc"
                 : '';
    }
    else
    {
        $cfgname = (exists($ENV{HOME}) && Idval::FileIO::idv_test_exists("$ENV{HOME}/idvaluser.cfg")) ? "$ENV{HOME}/idvaluser.cfg"
                 : Idval::FileIO::idv_test_exists("idvaluser.cfg")                                    ? "idvaluser.cfg"
                 : '';
    }

    chatty("user config file name is: \"[_1]\"\n", $cfgname);
    return $cfgname;
}

# Do a path search for the specified command file
# Allow a default file extension of .idv
sub find_command_file
{
    my $config = shift;
    my $cmd_name = shift;
    my $command_file = '';
    my $dirlist = $config->get_list_value('command_dir');

    if ($cmd_name)
    {
        if ($cmd_name !~ m{\.[^.]+$}x)
        {
            $cmd_name .= '.idv';
        }

        foreach my $dir (@{$dirlist})
        {
            my $cmd = File::Spec->catfile($dir, $cmd_name);
            if (Idval::FileIO::idv_test_exists($cmd))
            {
                $command_file = $cmd;
                last;
            }
        }
    }

    return $command_file;
}
sub make_wanted
{
    my $providers = shift;
    my $config = shift;

    my $typemap = Idval::TypeMap->new($providers);
    my %type_list;
    my %record_creators;

    ###Handle sub-types here: so far the only one is MP3 IDV1 or V2 or ???
    ###@type_list should only have extensions
    ###record_creators needs to deal with sub-types

    # Get a list of all the kinds of files we can read with the currently installed
    # 'reads_tags' providers.
    foreach my $item ($providers->_get_providers({types=>['reads_tags']}))
    {
        # This perly expression will create one entry in the hash %type_list for
        # each extension associated with the filetype handled by this tag reader.
        my $type = $item->get_source();
        @type_list{$typemap->get_exts_from_filetype($type)} = undef;
        $record_creators{$type} = $item;
    }
    
    my @exts = map { '\.' . lc($_) } keys %type_list;

    idv_dbg("UI: exts: <[_1]>\n", join(",", @exts));
    return sub {
        idv_dbg("UI: file is \"[_1]\"\n", $_);
        return if -d $_;
        my($filename, $junk, $suffix) = fileparse(basename($_), @exts);
        idv_dbg("UI: name is [_1], Suffix is: <[_2]>\n", $_, $suffix);
        return unless $suffix;  # It wasn't one of the ones we were looking for

        $suffix = substr($suffix, 1); # Remove the '.'
        my($class, $type) = $typemap->get_class_and_type_from_ext($suffix);

        my $obj = $record_creators{$type};

        $obj->create_records({filename => $_,
                              path     => $File::Find::name,
                              class    => $class,
                              type     => $type,
                              srclist  => $srclist});
    };
}


sub get_source_from_dirs
{
    my $providers = shift;
    my $config = shift;
    my @dirs = map {Idval::Common::expand_tilde($_) }  @_;

    #local $srclist = {};
    $srclist = Idval::Collection->new({source => 'gettags command'});
    my $wanted = make_wanted($providers, $config);

    Idval::FileIO::idv_find($wanted, @dirs);

    return $srclist;
}

# Given the name of a data file (which may be blank), and the name of the
# default data store file, return a list of records.

sub get_source_from_file
{
    my $dat_file = shift;
    my $reclist;

    my $dat = Idval::DataFile->new($dat_file);
    $reclist = $dat->get_reclist();
    return $reclist;
}

sub get_source_from_cache
{
    my $data_store = shift;
    my $dat_file_name = shift;
    my $reclist;

    $reclist = eval {retrieve(Idval::Common::expand_tilde($data_store))};
    fatal("Tag info cache is corrupted; you will need to regenerate it (with 'gettags'):\n[_1]\n", $@) if $@;
    my $ds = Idval::Collection->new({contents => $reclist});
    $ds->source($dat_file_name);

    return $ds;
}

sub put_source_to_file
{
    my $argref = shift;

    my $datastore  = $argref->{datastore};
    my $reclist    = $datastore->{RECORDS};
    my $source_name = $datastore->{SOURCE};
    my $data_store_file = $argref->{datastore_file};

    my $dat_file   = exists $argref->{outputfile} ? $argref->{outputfile} : '';
    my $usecache   = exists $argref->{usecache} ? $argref->{usecache} : 1;

    $datastore->purge();                     # Remove all strictly calculated keys

    # First (unless specifically told not to), opaquely to the data store
    if ($usecache)
    {
        my $ds_base = Idval::Common::expand_tilde($data_store_file);
        my $ds_bin = $ds_base . '.bin';
        my $ds_dat = $ds_base . '.dat';
        # Make sure the path exists
        my $path = dirname($ds_bin);
        mkpath($path) unless -d $path;

        # Save both the binary cache and the equivalent readable file
        $datastore->source('STORED DATA CACHE'); # First, adjust the SOURCE descriptor
        store($datastore, $ds_bin);
        my $out = Idval::FileIO->new($ds_dat, '>') or 
            fatal("Can't open [_1] for writing: [_2]\n", $ds_dat, $ERRNO);

        $out->print(join("\n", @{$datastore->stringify()}), "\n");
        $out->close();
    }

    # Next, write to output file if requested
    if ($dat_file)
    {
        my $fname = $dat_file;
        my $out = Idval::FileIO->new($fname, '>') or fatal("Can't open \"[_1]\" for writing: [_1]\n", $fname, $ERRNO);

        $datastore->source($fname);
        my @outstrs = @{$datastore->stringify()};
        my $ftag = '';
        foreach my $line (@outstrs)
        {
            $ftag = $line if $line =~ m/^FILE/;
            foreach my $char (split(//, $line))
            {
                verbose("Wide char in \"[_1]\" from \"[_2]\"\n", $line, $ftag) if ord($char) > 255;
            }
        }
        $out->print(join("\n", @outstrs), "\n");
        $out->close();
    }

    return;
}

# Given two record lists (Idval::Collection) or two records (Idval::Record) (a & b),
# return three hash refs:
# all items in a that are not in b
# all items common to a and b
# all items in b that are not in a
sub get_rec_diffs
{
    my $rec_a = shift;
    my $rec_b = shift;

    my %a_not_b;
    my %a_and_b;
    my %b_not_a;

    foreach my $item ($rec_a->get_diff_keys())
    {
        if ($rec_b->key_exists($item))
        {
            $a_and_b{$item} = $rec_a->get_value($item);
        }
        else
        {
            $a_not_b{$item} = $rec_a->get_value($item);
        }
    }

    foreach my $item ($rec_b->get_diff_keys())
    {
        if (! $rec_a->key_exists($item))
        {
            $b_not_a{$item} = $rec_b->get_value($item);
        }
    }

    return (\%a_not_b, \%a_and_b, \%b_not_a);
}

1;
