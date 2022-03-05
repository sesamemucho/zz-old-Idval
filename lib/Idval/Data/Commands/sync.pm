package Idval::Plugins::Command::Sync;

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
use File::Spec;
use File::stat;
use File::Basename;
use File::Temp qw/ tempfile /;
use Time::HiRes qw(gettimeofday tv_interval);
use Getopt::Long;
use English '-no_match_vars';;
use Memoize;
use Storable;

use Idval::Logger qw(info_q verbose chatty idv_dbg);
use Idval::Common;
use Idval::FileIO;
use Idval::DoDots;

my $first = 1;

my $progress_data = {};
my %prov_list;

memoize('get_file_ext');
memoize('get_all_extensions_regexp');
memoize('get_converter');

sub init
{
    set_pod_input();
    %prov_list = ();

    return;
}

sub main
{
    my $datastore = shift;
    my $providers = shift;
    my @args = @_;
    my $status;

    #$Devel::Trace::TRACE = 1;
    # Storable::dclone doesn't work with regexps
    # Make a copy of the config, to restore it at the end of the
    # command.  In particular, any filter converters will need access
    # to the sync data.
    my $config = Idval::Common::get_common_object('config');
    my $old_config = $config->copy();
    $Devel::Trace::TRACE = 0;

    my $typemap = Idval::Common::get_common_object('typemap');
    my $dotmap = $typemap->get_dot_map();
    Idval::DoDots::init();

    my ($syncfile, $should_delete_syncfile) = _parse_args(@args);

    # Now, make a new config object that incorporates the sync file info.
    $config->add_file($syncfile);
    progress_init($progress_data, $datastore);

    my %records_to_process;

    foreach my $key (sort keys %{$datastore->{RECORDS}})
    {
        my $tag_record = $datastore->{RECORDS}->{$key};
        #my $sync_dest = $config->get_single_value('sync_dest', $tag_record);
        my $do_sync = $config->get_single_value('sync', $tag_record);
        if ($do_sync)
        {
            progress_inc_number_to_process($progress_data);
            $records_to_process{$key} = 1;
        }
    }

    progress_print_title($progress_data);

    foreach my $key (sort keys %records_to_process)
    {
        $status = each_item($datastore->{RECORDS}, $key, $config);

        if ($status != 0)
        {
            last;
        }
    }

    unlink $syncfile if $should_delete_syncfile;

    map { $_->close() } values %prov_list;

    Idval::Common::register_common_object('config', $old_config);
    return $datastore;
}

sub ok_to_convert
{
    my $local_pathname = shift;
    my $remote_pathname = shift;

    my $convert_file = 0;
    my $l_st = stat($local_pathname);
    my $r_st = stat($remote_pathname);

    if (not -e $remote_pathname) {
        $convert_file = 1;
        verbose("Remote file \"[_1]\" does not exist. Will create.\n", $remote_pathname);
    } elsif ($r_st->mtime < $l_st->mtime) {
        $convert_file = 1;
        verbose("Remote file \"[_1]\" is older than local file \"[_2]\". Will convert.\n", $remote_pathname, $local_pathname);
    } else {
        $convert_file = 0;
        verbose("Remote file \"[_1]\" is newer than local file \"[_2]\". Will not convert.\n", $remote_pathname, $local_pathname);
    }

    return $convert_file;
}

# If sync_dest is set and looks like a file, the destination path is: $remote_top/$sync_dest
# If sync_dest is set and looks like a directory, the destination path is:
#                      $remote_top/$sync_dest/$source_name.<conversion_extension>
# If sync_dest is not set and do_sync is set, the destination path is:
#                      $remote_top/$source_name.<conversion_extension>
#   Note that is is the same as if sync_dest = ''


#
# if $remote_top/$sync_dest contains the string %LASTDIR%, this string will be replaced by
#    the name of the parent directory of the file indicated by $src_name
#
# $remote_top is a directory path. It may be empty.
# $sync_dir is the directory part of $sync_dest. If $sync_dest appears to be a directory, then
#     $sync_dir = $sync_dest
# $sync_name is the filename part of $sync_dest. If $sync_dest appears to be a directory, then
#     $sync_name = ''
#
# $src_path is the full pathname of the source file.
# $src_dir  is the directory part of $src_path
# $src_name is the filename part of $src_path
# $src_ext  is the extension of $src_name

# $dest_path is the full pathname of the destination file, =
#   $dest_dir + $dest_name + $dest_ext

sub each_item
{
    my $hash = shift;
    my $key = shift;
    my $config = shift;

    my $tag_record = $hash->{$key};
    my $retval = 0;

    my $do_sync = $config->get_single_value('sync', $tag_record);

    progress_inc_seen($progress_data);

    idv_dbg("Checking [_1]\n", $tag_record->get_name());
    if (! $do_sync)
    {
        return $retval;
    }

    my $src_type = $tag_record->get_value('TYPE');
    my $dest_type = $config->get_single_value('convert', $tag_record);
    my $prov;

    my $filter = $config->get_single_value('filter', $tag_record);
    chatty("source type is \"[_1]\" dest type is \"[_2]\"; filter is \"[_3]\"\n", $src_type, $dest_type, $filter);
    if ($filter and ($filter eq 'sox'))
    {
        $prov = get_converter($src_type, $dest_type, 'filter');
    }
    elsif ($src_type eq $dest_type)
    {
        # Don't get excited. The '*' is just a label. No globbing is involved.
        $prov = get_converter('*', '*');
    }
    else
    {
        $prov = get_converter($src_type, $dest_type);
    }

    chatty("src: [_1] to dest: [_2] yields converter [_3]\n", $src_type, $dest_type, $prov->query('name'));

    # Keep track of all the providers, so we can call close() on them later.
    $prov_list{$prov} = $prov;

    my ($src_path, $dest_path) = get_file_paths($tag_record, $dest_type, $prov, $config);

    if (ok_to_convert($src_path, $dest_path))
    {

        chatty("Converting \"[_1]\" to \"[_2]\"\n", $src_path, $dest_path);
        my $dest_dir = dirname($dest_path);
        if (!Idval::FileIO::idv_test_isdir($dest_dir))
        {
            Idval::FileIO::idv_mkdir($dest_dir);
        }

        # Save the destination path back into the tag record.
        # This tag (since it begins with '__') will not be saved.
        $tag_record->add_tag('__DEST_PATH', $dest_path);

        #print STDERR "tag_record: ", Dumper($tag_record);
        $retval = $prov->convert($tag_record, $dest_path);
        $retval = 0;

        progress_print_line($progress_data);
    }
    else
    {
        chatty("Did not convert \"[_1]\" to \"[_2]\"\n", $src_path, $dest_path);
        $retval = 0;
    }

    return $retval;
}

sub epilog
{
}

sub get_file_ext
{
    my $typemap = Idval::Common::get_common_object('typemap');
    my $type = shift;

    return $typemap->get_output_ext_from_filetype($type);
}

sub get_all_extensions_regexp
{
    my $typemap = Idval::Common::get_common_object('typemap');

    my @exts = $typemap->get_all_extensions();
    my $restring = '\.(' . join('|', @exts) . ')';
    my $re = qr{$restring};

    return $re;
}

sub get_converter
{
    my $providers = Idval::Common::get_common_object('providers');

    my $src_type = shift;
    my $dest_type = shift;
    #idv_dbg("Getting provider for src:[_1] dest:[_2]\n", $src_type, $dest_type);
    return $providers->get_provider('converts', $src_type, $dest_type, @_);
}

sub _parse_args
{
    my @args = @_;

    my $orig_args = join(' ', @args);
    my $mp3 = 0;
    my $ogg = 0;
    my @blocks = ();

    {
        # We need to do our own argument parsing
        local @ARGV = @args;

        my $opts = Getopt::Long::Parser->new();
        my $retval = $opts->getoptions('mp3' => \$mp3,
                                       'ogg' => \$ogg,
                                       'block=s' => \@blocks,
            );

        @args = (@ARGV);
    }

    if ((scalar @args == 0) && (scalar @blocks == 0))
    {
        Idval::Common::get_logger()->fatal("Sync: Need at least one argument to sync\n");
        # Should print out Synopsis here
    }
    elsif (scalar @args == 1)
    {
        return ($args[0], 0);
    }
    elsif (scalar @args == 2)
    {
        $blocks[0] = $args[0] . ':' . $args[1];
    }
    elsif (scalar @blocks == 0)
    {
        # We're going to need a Help module...
        Idval::Common::get_logger()->fatal("Sync: Need at least one argument to sync\n");
        # Should print out Synopsis here
    }

    # Else, assume it's src/dest specs

    my $convert_type = $ogg            ? 'OGG'
                     : $mp3            ? 'MP3'
                     : 'MP3';

    my $syncfile = "{\n";
    foreach my $blockspec (@blocks)
    {
        my ($selectors, $remote_top) = split(/:/, $blockspec);
        if (!(defined($selectors) && defined($remote_top)))
        {
            Idval::Common::get_logger()->fatal("Sync: argument error ($orig_args)\n");
            # Should print out Synopsis here
        }

        $syncfile .= "convert    = $convert_type\n";

        $syncfile .= "}\n{\n";
        $syncfile .= "\tremote_top = $remote_top\n";
        foreach my $src (split(/;/, $selectors))
        {
            # A src argument that is just a file name is assumed to be a FILE parameter

            if (-e $src)
            {
                $syncfile .= "\tFILE has $src\n";
            }
            else
            {
                $syncfile .= "\t$src\n";
            }
        }

        $syncfile .= "\tsync=1\n}\n\n";
    }

    # Write it to temp file...
    my ($fh, $filename) = tempfile();

    print $fh $syncfile;
    $fh->close();

    return $filename;
}

sub progress_init
{
    my $this = shift;
    my $datastore = shift;

    $this->{total_number_to_process} = 0;
    $this->{number_of_seen_records} = 0;
    $this->{number_of_processed_records} = 0;
    $this->{total_number_of_records} = scalar(keys %{$datastore->{RECORDS}});

    $this->{start_time} = [gettimeofday];
    return;
}

sub progress_inc_seen
{
    my $this = shift;

    $this->{number_of_seen_records}++;
    return;
}

sub progress_inc_number_to_process
{
    my $this = shift;

    $this->{total_number_to_process}++;
    return;
}

sub progress_print_title
{
    my $this = shift;

    info_q("processed remaining  total  percent  elapsed  remaining    total\n");
    info_q("[sprintf,%5d %9d %9d %5.0f%%     %8s  %8s  %8s,_1,_2,_3,_4,_5,_6]\n",
                    0,
                    $this->{total_number_to_process},
                    $this->{total_number_to_process},
                    0.0,
                    '00:00:00',
                    '00:00:00',
                    '',
            );
    return;
}

sub progress_print_line
{
    my $this = shift;

    $this->{number_of_processed_records}++;
    my $fraction = ($this->{number_of_processed_records} / $this->{total_number_to_process});

    my $safe_frac = $fraction < 0.001 ? 0.001 : $fraction;

    my $elapsed_time = tv_interval($this->{start_time});

    my $est_time = $elapsed_time / $safe_frac;
    my $est_time_remaining = $est_time - $elapsed_time;

    info_q("[sprintf,%5d %9d %9d %5.0f%%     %8s  %8s  %8s,_1,_2,_3,_4,_5,_6]\n",
                     $this->{number_of_processed_records},
                     $this->{total_number_to_process} - $this->{number_of_processed_records},
                     $this->{total_number_to_process},
                     $fraction  * 100.0,
                     progress_format_time($elapsed_time),
                     progress_format_time($est_time_remaining),
                     progress_format_time($est_time),
           );
    return;
}

sub progress_format_time
{
    my $fsec = shift;

    my $sec = int($fsec);
    $sec = 0 if $sec < 0;

    my $hrs = int($sec / 3600);
    my $mins = int(int ($sec - int ($hrs * 3600)) / 60);
    my $secs = $sec % 60;
    my $minspec;

    if ($hrs != 0)
    {
        $hrs = sprintf("%2d:", $hrs);
        $mins = ($mins != 0) ? sprintf("%02d", $mins) : '  ';
    }
    else
    {
        $hrs = '   ';
        $mins = ($mins != 0) ? sprintf("%2d", $mins) : '  ';
    }
    $secs = sprintf(":%02d", $secs);

    return $hrs . $mins . $secs;
}

sub get_file_paths
{
    my $tag_record = shift;
    my $dest_type = shift;
    my $prov = shift;
    my $config = shift;

    my $src_path = $prov->get_source_filepath($tag_record);
    my ($volume, $src_dir, $src_name) = File::Spec->splitpath($src_path);
    chatty("For [_1]\n", $src_path);
    my $remote_top = Idval::Common::mung_to_unix($config->get_single_value('remote_top', $tag_record));
    chatty("   remote top is \"[_1]\"\n", $remote_top);
    my $dest_name = $prov->get_dest_filename($tag_record, $src_name, get_file_ext($dest_type));
    chatty("   dest name is \"[_1]\" ([_2])\n", $dest_name, $prov->query('name'));
    my $sync_dest = Idval::Common::mung_to_unix($config->get_single_value('sync_dest', $tag_record));

    my $extre = get_all_extensions_regexp();
    if ($sync_dest !~ m/$extre/)
    {
        # sync_dest is a directory, so to get the destination name just append dest_name
        $sync_dest = File::Spec->catfile($sync_dest, $dest_name);
        chatty("sync_dest is a directory: sync dest is \"[_1]\"\n", $sync_dest);
    }

    my $dest_path = File::Spec->catfile($remote_top, $sync_dest);
    $dest_path = Idval::Common::mung_to_unix($dest_path);

    if ($dest_path =~ m{%LASTDIR%})
    {
        my $lastdir = (File::Spec->splitdir(File::Spec->canonpath($src_dir)))[-1];
        $dest_path =~ s{%LASTDIR%}{$lastdir};
    }

    # Do we have any tagname expansions?
    if (my @tags = ($dest_path =~ m/%([^%]+)%/g))
    {
        idv_dbg("Found tags to expand: [_1]\n", join(',', @tags));
        foreach my $tag (@tags)
        {
            $dest_path =~ s{%$tag%}{$tag_record->{$tag}} if exists($tag_record->{$tag});
        }
        idv_dbg("dest path is now: \"[_1]\"\n", $dest_path);
    }

    $dest_path = File::Spec->canonpath($dest_path); # Make sure the destination path is nice and clean

    return ($src_path, $dest_path);
}

sub set_pod_input
{
    my $help_file = Idval::Common::get_common_object('help_file');

    my $pod_input =<<"EOD";

=head1 NAME

sync - Synchronizes a remote directory to the local directory

=head1 SYNOPSIS

sync sync-data-file

sync-data-file is a cascading configuration file that tells the program which files to synchronize
and how to do it.

=head1 OPTIONS

This command has no options.

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do something
useful with the contents thereof.

=cut

EOD
    $help_file->set_man_info('sync', $pod_input);

    return;
}

1;
