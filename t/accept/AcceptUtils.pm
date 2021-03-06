package AcceptUtils;

use strict;
use warnings;

use Data::Dumper;
use Carp;
use IO::File;
use File::stat;
use File::Copy;
use File::Path;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use Idval;
use Idval::Common;

use FindBin;
our $audiodir = "$FindBin::Bin/../samples";
our $datadir  = "$FindBin::Bin/../accept_data";

my %startfiles = (
    'FLAC' => $audiodir . '/sbeep.flac',
    'MP3'  => $audiodir . '/sbeep.mp3',
    'OGG'  => $audiodir . '/sbeep.ogg',
    );

my @tempfiles = ();

END {
    unlink @tempfiles;
}

sub get_audiodir
{
    my $rest = shift;

    return $audiodir . $rest;
}

sub get_datadir
{
    my $rest = shift;

    return $datadir . $rest;
}

sub are_providers_present
{
    my $provs = Idval::Common::get_common_object('providers');

    my $retval = 1;
    my $reason = '';

    if (!defined($provs->get_provider('reads_tags', 'MP3', 'NULL')))
    {
        $retval = 0;
        $reason .= "MP3 tag reader not found.\n";
    }
    else
    {
        #print STDERR "MP3 tag reader found\n";
    }
    if (!defined($provs->get_provider('writes_tags', 'MP3', 'NULL')))
    {
        $retval = 0;
        $reason .= "MP3 tag writer not found.\n";
    }
    else
    {
        #print STDERR "MP3 tag writer found\n";
    }
    if (!defined($provs->get_provider('reads_tags', 'OGG', 'NULL')))
    {
        $retval = 0;
        $reason .= "OGG tag reader not found.\n";
    }
    else
    {
        #print STDERR "OGG tag reader found\n";
    }
    if (!defined($provs->get_provider('writes_tags', 'OGG', 'NULL')))
    {
        $retval = 0;
        $reason .= "OGG tag writer not found.\n";
    }
    else
    {
        #print STDERR "OGG tag writer found\n";
    }
    if (!defined($provs->get_provider('reads_tags', 'FLAC', 'NULL')))
    {
        $retval = 0;
        $reason .= "FLAC tag reader not found.\n";
    }
    else
    {
        #print STDERR "FLAC tag reader found\n";
    }
    if (!defined($provs->get_provider('writes_tags', 'FLAC', 'NULL')))
    {
        $retval = 0;
        $reason .= "FLAC tag writer not found.\n";
    }
    else
    {
        #print STDERR "FLAC tag writer found\n";
    }

    #print STDERR "returning \"$retval\", \"$reason\"\n";
    return ($retval, $reason);
}

sub mktree
{
    my $datafile = shift;
    my $testpath = shift;
    my $idval = shift;

    my %info;
    my $dfh = IO::File->new($datafile, '<') || croak "Can't open input file \"$datafile\" for reading: $!\n";

    while (defined(my $line = <$dfh>))
    {
        $line =~ s/\#.*$//x;
        next if $line =~ m/^\s*$/;

        my ($fname, $type, $title, $artist, $album, $tracknum, $genre, $date) = split(/\s*\|\s*/, $line);
        #print join(",", ($fname, $type, $title, $artist, $album, $tracknum, $genre, $date)), "\n";
        chomp $date;

        my $path = File::Spec->catfile($testpath, "$fname." . lc($type));
        $info{$path}->{TYPE} = uc($type);
        $info{$path}->{TIT2} = $title;
        $info{$path}->{TPE1} = $artist;
        $info{$path}->{TALB} = $album;
        $info{$path}->{TRCK} = $tracknum;
        $info{$path}->{TCON} = $genre;
        $info{$path}->{TYER} = $date;

        # If the generated file exists and it is newer than the datafile (from which it was made),
        # make a new one
        next if (-e $path) and (stat($path)->mtime > stat($datafile)->mtime);
        mkpath([dirname($path)]);
        copy($startfiles{$type}, $path) or croak("Copy of $startfiles{$type} to $path failed: $!\n");
        push(@tempfiles, $path);
        #Set up tags here
    }

    my $taglist = $idval->datastore();
    my $junk;
    ($junk, $junk, $taglist) = run_test_and_get_log({idval_obj=>$idval,
                                                     cmd_sub=>\&Idval::Scripts::gettags,
                                                     tag_source=>$taglist,
                                                     otherargs=>[$testpath]});
    #$taglist = Idval::Scripts::gettags($taglist, $idval->providers(), $testpath);
    #print STDERR "AU: taglist: ", Dumper($taglist);
    my ($fh, $fname) = tempfile();
    push(@tempfiles, $fname);

    my $tag_record;
    my $type;
    my $prov;
    foreach my $key (sort keys %{$taglist->{RECORDS}})
    {
        $tag_record = $taglist->{RECORDS}->{$key};
    
        $tag_record->add_tag('TYPE', $info{$key}->{TYPE});
        $tag_record->add_tag('TIT2', $info{$key}->{TIT2});
        $tag_record->add_tag('TPE1', $info{$key}->{TPE1});
        $tag_record->add_tag('TALB', $info{$key}->{TALB});
        $tag_record->add_tag('TRCK', $info{$key}->{TRCK});
        $tag_record->add_tag('TCON', $info{$key}->{TCON});
        $tag_record->add_tag('TYER', $info{$key}->{TYER});
    }

    ($junk, $junk, $taglist) = run_test_and_get_log({idval_obj=>$idval,
                                                     cmd_sub=>\&Idval::Scripts::print,
                                                     tag_source=>$taglist,
                                                     otherargs=>[$fh]});
    #$taglist = Idval::Scripts::print($taglist, $idval->providers(), $fh);
    #print STDERR "AU: taglist 2: ", Dumper($taglist);
    #print STDERR "AU: xxx\n", qx{cat $fname};
    #print STDERR "ls -l $fname\n";
    #print "Updating tags:\n";
    ($junk, $junk, $taglist) = run_test_and_get_log({idval_obj=>$idval,
                                                     cmd_sub=>\&Idval::Scripts::update,
                                                     tag_source=>$taglist,
                                                     otherargs=>[$fname]});
    #$taglist = Idval::Scripts::update($taglist, $idval->providers(), $fname);
    #print STDERR "AU: taglist 3: ", Dumper($taglist);
    #$taglist = Idval::printlist($taglist, $idval->providers());

    return $taglist;
}

sub run_test_and_get_log
{
    my $argref = shift;
    my $cfg = exists($argref->{cfg}) ? $argref->{cfg} : '';
    my $idval_obj = $argref->{idval_obj};
    my $do_logging = exists($argref->{do_logging}) ? $argref->{do_logging} : 1;
    my $debugmask  = exists($argref->{debugmask}) ? $argref->{debugmask} : '';
    my @otherargs  = exists($argref->{otherargs}) ? @{$argref->{otherargs}} : ();
    my $cmd_sub = $argref->{cmd_sub};
    my $tag_source = $argref->{tag_source};

    my $taglist = ref $tag_source eq 'CODE' ? &$tag_source : $tag_source;

    my $eval_status;

    my ($fh, $fname) = tempfile();
    print $fh $cfg;
    $fh->close();

    push(@tempfiles, $fname);

    my $str_buf = 'nothing here';

    open my $oldout, ">&STDOUT"     or die "Can't dup STDOUT: $!";
    close STDOUT;
    open STDOUT, '>', \$str_buf or die "Can't redirect STDOUT: $!";
    select STDOUT; $| = 1;      # make unbuffered

    #Idval::Logger::get_logger()->str('a_u');
    my $old_settings;
    if ($do_logging)
    {
        $old_settings = Idval::Logger::get_settings();
        Idval::Logger::re_init({log_out => 'STDOUT', debugmask=>$debugmask});
    }

    unshift(@otherargs, $fname) if exists($argref->{cfg});

    eval {$taglist = &$cmd_sub($taglist, $idval_obj->providers(), @otherargs);};
    $eval_status = $@ if $@;

    #print STDERR "eval status is \"$@\"\n";
    if ($do_logging)
    {
        Idval::Logger::re_init($old_settings);
    }

    open STDOUT, ">&", $oldout or die "Can't dup \$oldout: $!";

    my $retval = $eval_status ? $eval_status : $str_buf;
    return wantarray ? ($retval, $str_buf, $taglist) : $retval;
}

1;
