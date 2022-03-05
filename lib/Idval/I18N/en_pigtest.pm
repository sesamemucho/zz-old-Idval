
package Idval::I18N::en_pigtest;
use base qw(Idval::I18N::en);
use Data::Dumper;

sub topigtest1
{
    print "Hello from topigtest1\n";
    my $handle = shift;

    print "topigtest1: tossing \"$handle\"\n";
    return topigtest(@_);
}

sub topigtest
{
    my $key = shift;
    my @params = @_;

    print "topigtest: key is \"$key\"\n";
    print "topigtest: params are: <", join('|', @params), ">\n";
    my $result = '';
    my $foo = $key;

  LOOP:
    {
        $result .= to_pigtest($1),            redo LOOP if $foo =~ m/\G(\w+)/gc;
        $result .= $1,              redo LOOP if $foo =~ m/\G(\W+)/gc;
    }


    return $result . "\n";
}

sub to_pigtest
{
    my $eng = shift;

    my $cap = ($eng =~ m/^[A-Z]/);
    $eng = lc $eng;

    if ($eng =~ m/^[aeiou]/i)
    {
        $eng = $eng . 'way';
    }
    else
    {
        $eng =~ s/^([^aeiou]+)(.\w*)(.*)/$2${1}ay$3/i;
    }

    $eng = ucfirst $eng if $cap;

    return $eng;
}

sub init {
    my $lh = $_[0];  # a newborn handle
    $lh->SUPER::init();
    #$lh->{'frail'} = 'topigtest';
    #$lh->{'fail'} = 'topigtest';
    $lh->fail_with('topigtest');
    $lh->{'yumma gumma'} = 'barfo';
    print "Hello from en_pigtest init, self is", Dumper($lh);
    return;
}

%Lexicon = (
    '_AUTO' => 0,
    #"hello from foo\n" => "Below from poo\n",
    #"hello from foo\n" => \&topigtest1,

    # set.pm
    "set_cmd=conf" => "set_cmd=onfcay",
    "set_cmd=debug" => "set_cmd=ebugday",
    "set_cmd=level" => "set_cmd=evelay",

    "set commands are: conf, debug, level\n" =>
    "etsay ommandscay areway: onfcay, ebugday, evelay\n",

    "\nCurrent level is: [_1] ([_2])\n" =>
    "\nUrrentcay evelay isway: [_1] ([_2])\n",
);


1;

