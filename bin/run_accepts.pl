#!/usr/bin/perl -w

use strict;
use warnings;

use Getopt::Long;
use Test::Unit::Debug qw(debug_pkgs);
use Test::Unit::TestRunner;
use File::Glob ':glob';
use File::Path;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/../t/accept");
use Cwd qw(abs_path);

# Get the top directory of the idv tree and make it look pretty
our $topdir = abs_path("$FindBin::Bin/..");

use Idval::Logger;
use Idval::Common;

my @standard_options =
    (
     'verbose+',
     'quiet+',
     'debug=i',
     'development',
     'log_out=i',
     'no-delete',
    );

my %options;
$options{'no-delete'} = 0;

my $opts = Getopt::Long::Parser->new();
my $retval = $opts->getoptions(\%options, @standard_options);

$options{'verbose'} = 0;
$options{'quiet'} = 0;
$options{'development'} = 0;
$options{'log_out'} = undef;

# We now know enough to fire up the error logger
my @logger_args = Idval::Common::mkarglist(
    'level' => $options{'verbose'} - $options{'quiet'},
    defined($options{'debug'}) ? ('debug' => $options{'debug'}) : '',
    $options{'development'} ? ('show_trace' => 1, 'show_time' => 1) : '',
    defined($options{'log_out'}) ? ('log_out' => $options{'log_out'}) : '',
    );

Idval::Logger::initialize_logger(@logger_args);
my $log = Idval::Logger::get_logger();
#print STDERR $log->str(), "\n";

Idval::Common::register_common_object('options', \%options);

my @exceptions;
my @inclusions;
foreach my $item (@ARGV)
{
    if ($item =~ m/^-(\S*)/)
    {
        push(@exceptions, $1);
        next;
    }

    push(@inclusions, $item);
}

$inclusions[0] = '*' unless @inclusions;

my @pkgs;
my %candidates;
my %bums;

foreach my $item (@inclusions)
{
    map {$candidates{$_} = $_} bsd_glob("$FindBin::Bin/../t/accept/${item}Test.pm");
}

foreach my $item (@exceptions)
{
    map {$bums{$_} = $_} bsd_glob("$FindBin::Bin/../t/accept/${item}Test.pm");
}

foreach my $item (keys %candidates)
{
    delete $candidates{$item} if exists $bums{$item};
}

@pkgs = keys %candidates;

die "No tests found for args \"+", join(' +', @inclusions), "\" \"-", join(' -', @exceptions), "\"\n" unless @pkgs;

print "Get some coffee...\n";
foreach my $pkg (@pkgs)
{
    my $testrunner = Test::Unit::TestRunner->new();
    $testrunner->start($pkg);
}

rmtree([$topdir . '/t/accept_data/ValidateTest/t']) unless $options{'no-delete'};
