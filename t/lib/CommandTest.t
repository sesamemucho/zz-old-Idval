package Idval::Command::Test;

use strict;
use warnings;
use lib qw{t/lib};

use base qw(Test::Class);
use Test::More;

use Data::Dumper;

use TestUtils;
use Idval::Config;
use Idval::ProviderMgr;
use Idval::ServiceLocator;

#my $tree1 = {'testdir' => {}};
my $provs;

INIT { Test::Class->runtests } # here's the magic!

sub begin : Test(startup) {
    # your state for fixture here
    # Tell the system to use the string-based filesystem services (i.e., the unit-testing version)
    Idval::ServiceLocator::provide('io_type', 'FileString');
    return;
}

sub end : Test(shutdown) {
    return;
}


sub before : Test(setup) {
    # provide fixture
    my $tree1 = {'testdir' => {}};
    Idval::FileString::idv_set_tree($tree1);

    return;
}

sub after : Test(teardown) {
    # clean up after test
    Idval::FileString::idv_clear_tree();
    #TestUtils::unload_packages($provs);

    return;
}

sub get_converter : Test(1)
{
    my $self = shift;

    #print STDERR "Hello from test_get_converter\n";
    Idval::FileString::idv_add_file('/testdir/gt1.txt', "\nprovider_dir = /testdir/Idval\n\n");
    #print STDERR "Hello 1 from test_get_converter\n";
    add_UserPlugin3_up1();
    #print STDERR "Hello 2 from test_get_converter\n";

    my $fc = Idval::Config->new("/testdir/gt1.txt");
    #print STDERR "Hello 3 from test_get_converter\n";
    $provs = Idval::ProviderMgr->new($fc);
    #print STDERR "provs is:", Dumper($provs);
    my $conv = $provs->_get_command('/testdir/Idval/goober.pm');

    ok($conv);

    return;
}

##-------------------------------------------------##

sub add_UserPlugin3_up1
{
    my $plugin =<<'EOF';
package Idval::Plugins::Up1;
use Idval::Common;
use base qw(Idval::Provider);
no warnings qw(redefine);

#Idval::Common::register_provider({provides=>'command', name=>'goober'});

sub init
{

    return;
}

sub main
{
    my $self = shift;
    my $datastore = shift;

    return $datastore;
}

1;
EOF

    Idval::FileString::idv_add_file('/testdir/Idval/goober.pm', $plugin);

    return;
}

1;
