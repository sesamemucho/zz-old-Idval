package Idval::Logger;

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
use IO::Handle;
use Carp qw(croak cluck confess);
use POSIX qw(strftime);
use Memoize qw(memoize flush_cache);
use DB;

use Idval::I18N;

use base qw( Exporter DB);
our @EXPORT_OK = qw( idv_print idv_print_noi18n query silent silent_q quiet info info_q verbose chatty idv_dbg idv_warn fatal
                     would_I_print idv_dumper
                     $L_SILENT $L_QUIET $L_INFO $L_VERBOSE $L_CHATTY $L_DEBUG %level_to_name %name_to_level);
our %EXPORT_TAGS = (vars => [qw($L_SILENT $L_QUIET $L_INFO $L_VERBOSE $L_CHATTY $L_DEBUG %level_to_name %name_to_level)]);

$Carp::CarpLevel = 1;

my $default_output;
my $lo;
my @warnings;
our $depth = 0;

our $optimize = 1;

our $L_SILENT      = -1;
our $L_QUIET       = 0;
our $L_INFO        = 1;
our $L_VERBOSE     = 2;
our $L_CHATTY      = 3;
our $L_DEBUG       = 4;

our %level_to_name;
our %name_to_level;

# use 'our' instead of 'my' for unit tests
our %DEBUG_MACROS;

END {
    if (@warnings and $lo)
    {
        $lo->_log({level=>$L_SILENT, force_match=>1}, "The following warnings occurred:\n");
        $lo->_log({level=>$L_SILENT, force_match=>1}, @warnings);
    }
    }

# Certain modules may want to know when their debug level has been
# changed (for instance, Config and Select).
sub register
{
    my $self = shift;
    my $pkg = shift;
    my $cb  = shift;
    my $userdata = shift;

    $self->{CALLBACKS}->{$pkg}->{old} = 0;
    $self->{CALLBACKS}->{$pkg}->{new} = 0;
    $self->{CALLBACKS}->{$pkg}->{cb}->{$userdata} = $cb;
    # Using $userdata as a key stringifies it. This lets us pass the original
    # data back to the callback. It was, perhaps, an object ref back home.
    $self->{CALLBACKS}->{$pkg}->{userdata}->{$userdata} = $userdata;
    $self->check_for_callbacks();
    return;
}

sub check_for_callbacks
{
    my $self = shift;

    foreach my $pkg (keys %{$self->{CALLBACKS}})
    {
        my($result, $level) = $self->_pkg_matches($pkg);
        $self->{CALLBACKS}->{$pkg}->{new} = $level if $result;

        if ($self->{CALLBACKS}->{$pkg}->{old} ne $self->{CALLBACKS}->{$pkg}->{new})
        {
            # Allow for multiple objects of the same class (i.e. Config)
            foreach my $userdata (keys %{$self->{CALLBACKS}->{$pkg}->{cb}})
            {
                my $cb = $self->{CALLBACKS}->{$pkg}->{cb}->{$userdata};
                no strict 'refs';
                &$cb($self->{CALLBACKS}->{$pkg}->{old},
                     $self->{CALLBACKS}->{$pkg}->{new},
                     # Using $userdata as a key stringifies it. This lets us pass the original
                     # data back to the callback. It was, perhaps, an object ref back home.
                     $self->{CALLBACKS}->{$pkg}->{userdata}->{$userdata});
                use strict;
            }

            $self->{CALLBACKS}->{$pkg}->{old} = $self->{CALLBACKS}->{$pkg}->{new};
        }
    }

    return;
}

sub safe_get
{
    my $argref = shift;
    my $key = shift;
    my $default = shift;
    my $retval = !exists $argref->{$key}        ? $default
               : $argref->{$key}                ? $argref->{$key}
               :                                  $default;
    return $retval;
}

sub new
{
    my $class = shift;
    my $self = {};
    bless($self, ref($class) || $class);
    $self->_init(@_);
    return $self;
}

sub _init
{
    my $self = shift;
    my $argref = shift;
    my $lfh;

    # Logger can't include Idval::Common due to circular dependency
    $self->{LH} = Idval::I18N->idv_get_handle() || die "Idval::Logger: Can't get a language handle!";
    #print STDERR "Logger: LH is: ", Dumper($self->{LH});
    #print "Logger: current LH fail is: ", $self->{LH}->fail_with(), "\n";
    my $initial_dbg = 'DBG_STARTUP DBG_PROCESS Command::*';
    my $initial_lvl = exists($ENV{IDV_DEBUGLEVEL}) ? $ENV{IDV_DEBUGLEVEL} : $L_INFO;
    my $initial_trace = exists($ENV{IDV_DEBUGTRACE}) ? $ENV{IDV_DEBUGTRACE} : 1;

    #print STDERR "initial_dbg is: \"$initial_dbg\"\n";
    $self->accessor('LOGLEVEL', exists $argref->{level} ? $argref->{level} : $initial_lvl);
    $self->set_debugmask(exists $argref->{debugmask} ? $argref->{debugmask} : $initial_dbg);
    $self->set_debugmask($ENV{IDV_DEBUGMASK}) if exists $ENV{IDV_DEBUGMASK};
    $self->accessor('SHOW_TRACE', exists $argref->{show_trace} ? $argref->{show_trace} : $initial_trace);
    $self->accessor('SHOW_TIME', exists $argref->{show_time} ? $argref->{show_time} : 0);
    $self->accessor('USE_XML', exists $argref->{xml} ? $argref->{xml} : 0);
    $self->accessor('FROM',  exists $argref->{from} ? $argref->{from} : 'nowhere');

    $self->set_fh('LOG_OUT',  safe_get($argref, 'log_out', $default_output));
    $self->{LOG_OUT}->autoflush(1);
    $self->set_fh('PRINT_TO', safe_get($argref, 'print_to', $default_output));

    $self->{WARNINGS} = ();
    # Certain modules may want to know when their debug level has been
    # changed (for instance, Config and Select).
    $self->{CALLBACKS} = ();

    $self->set_optimization_level($self->_max_debuglevel());
    #$self->str('after init');
    return;
}

sub str
{
    my $self = shift;
    my $title = shift;
    my $io = shift || 'STDERR';

    no strict 'refs';
    print $io "$title\n" if $title;
    print $io "Logger settings:\n";
    printf $io "  log level:  %d\n", $self->accessor('LOGLEVEL');
    printf $io "  show trace: %d\n", $self->accessor('SHOW_TRACE');
    printf $io "  show time:  %d\n", $self->accessor('SHOW_TIME');
    printf $io "  use xml:    %d\n", $self->accessor('USE_XML');
    confess "No log_out?" unless defined($self->accessor('LOG_OUT'));
    printf $io "  output:     %s\n", $self->accessor('LOG_OUT');
    printf $io "  from:       %s\n", $self->accessor('FROM');
    printf $io "  debug mask: %s\n",   $self->str_debugmask('              ');
    use strict;
    return;
}

sub set_fh
{
    my $self = shift;
    my $fhtype = shift;
    my $name = shift;
    my $fh;

  NLOG:
    {
        if ($name eq "STDOUT")
        {
            $fh = *STDOUT{IO};
            last NLOG;
        }

        if ($name eq "STDERR")
        {
            $fh = *STDERR{IO};
            last NLOG;
        }

        $fh = $name;
        #undef $fh;
        #open($fh, ">&=", $name) || croak "Can't duplicate file descriptor \"$name\" for writing: $!\n"; ## no critic (RequireBriefOpen)
    }

    $self->{$fhtype} = $fh;
    $self->{VARS}->{$fhtype} = $fh;

    return $fh;
}

sub _walklist {
    my $list = shift;
    my @result;
    local $depth = $depth;

    croak "mask spec contains a recursive macro" if $depth++ > 10;

    foreach my $item (@{$list})
    {
        if ($item =~ m/^DBG_/)
        {
            croak("unrecognized macro \"$item\" requested for debug mask\n") unless exists($DEBUG_MACROS{$item});
            push(@result, _walklist($DEBUG_MACROS{$item}));
        }
        else
        {
            push(@result, $item);
        }
    }
    return @result;
}

sub set_debugmask
{
    my $self = shift;
    my $dbglist = shift;

    flush_cache('_pkg_matches');

    if (ref $dbglist eq 'HASH')
    {
        # We are restoring it
        $self->{MODULE_HASH} = $dbglist;

        $self->set_optimization_level($self->_max_debuglevel());
        $self->check_for_callbacks();

        # Now make a regular expression to match packages
        my $mod_re = '^((' . join(')|(', keys %{$dbglist}) . '))$';
        $self->{MODULE_REGEXP} = qr/$mod_re/; # Don't compile it; because then it will never change (even if reassigned)
        return sort keys %{$dbglist};
    }

    my $loglevel = $self->accessor('LOGLEVEL');
    $depth = 0;

    my @modlist = eval {_walklist([split(/,|\s+/, $dbglist)])};
    croak "Error: For debug mask spec \"$dbglist\", $@\n" if $@;
    #print STDERR "modlist from walkies is: ", join(",", @modlist), "\n";
    my @rev;
    my $quad;
    my %modules = exists $self->{MODULE_HASH} ? %{$self->{MODULE_HASH}} : ();
    #print STDERR "init modules is: ", Dumper(\%modules);

    my @replacements;
    my @additions;
    my @removals;
    # First, split the list into replacements, additions, and removals

    foreach my $item (@modlist)
    {
        push(@removals, $1), next if $item =~ m/^-(.*)$/;
        push(@additions, $1), next if $item =~ m/^\+(.*)$/;
        push(@replacements, $item);
    }

    #print STDERR "Replacements: <", join(',', @replacements), ">\n";
    #print STDERR "Additions: <", join(',', @additions), ">\n";
    #print STDERR "Removals: <", join(',', @removals), ">\n";
    # If we have any replacements, do that
    if (@replacements)
    {
        %modules = ();
        foreach my $mod (@replacements)
        {
            # split module name and log level (if present). Also remove colon from log level.
            my ($item, $level) = ($mod =~ m/^(.*?)(?::(\d+))?$/);
            #print STDERR "rep: from \"$mod\", got \"$item\" and ", defined($level) ? "\"$level\"" : "undef", "\n";
            @rev = reverse split(/::/, $item);
            #print STDERR "rev is: <", join(',', @rev), ">\n";
            push(@rev, qw(* * * *)); # Make sure we have at least four items
            $quad = join('::', @rev[0..3]); # Exactly four
            $quad =~ s/\*/\.\*\?/g;

            $modules{$quad}->{LEVEL} = defined($level) ? $level : $self->accessor('LOGLEVEL');
            $modules{$quad}->{STR} = $item;
        }
    }

    # Do additions
    if (@additions)
    {
        #print STDERR "additions: modules is: ", Dumper(\%modules);
        foreach my $mod (@additions)
        {
            # split module name and log level (if present). Also remove colon from log level.
            my ($item, $level) = ($mod =~ m/^(.*?)(?::(\d+))?$/);
            #print STDERR "add: from \"$mod\", got \"$item\" and ", defined($level) ? "\"$level\"" : "undef", "\n";
            my @rev = reverse split(/::/, $item);
            push(@rev, qw(* * * *)); # Make sure we have at least four items
            my $quad = join('::', @rev[0..3]); # Exactly four
            $quad =~ s/\*/\.\*\?/g;
            #print STDERR "additions: rev is: <", join(',', @rev), ">, quad is: \"$quad\"\n";

            $modules{$quad}->{LEVEL} = defined($level) ? $level : $self->accessor('LOGLEVEL');
            $modules{$quad}->{STR} = $item;
        }
    }

    # Do removals
    if (@removals)
    {
        #print STDERR "Removals: modules is: ", Dumper(\%modules);
        foreach my $mod (@removals)
        {
            # Really, we don't need to extract the log level here, but for symmetry...
            my ($item, $level) = ($mod =~ m/^(.*?)(?::(\d+))?$/);
            #print STDERR "rem: from \"$mod\", got \"$item\" and ", defined($level) ? "\"$level\"" : "undef", "\n";
            my @rev = reverse split(/::/, $item);
            push(@rev, qw(* * * *)); # Make sure we have at least four items
            my $quad = join('::', @rev[0..3]); # Exactly four
            $quad =~ s/\*/\.\*\?/g;
            #print STDERR "removals: rev is: <", join(',', @rev), ">, quad is: \"$quad\"\n";

            delete $modules{$quad} if exists $modules{$quad};
        }
    }

    $self->{MODULE_HASH} = \%modules;

    # Here's a quick way to make more-specific specifications take
    # precedence over more general ones. Consider
    # '.*?::Command::.*?::.*?' and 'Sync::.*?::.*?::.*?' in the
    # context of checking the debug mask for Idval::Command::Sync.
    # We want 'Sync::.*?::.*?::.*?' to match before
    # '.*?::Command::.*?::.*?'. Since the wildcard '.*?' sorts before
    # any letters, just sort %module's keys in reverse, and there you
    # go.
    my @regexlist = sort { $b cmp $a } keys %modules;

    $self->{MODULE_LIST} = \@regexlist;
    # Now make a regular expression to match packages
    my $mod_re = '^(?:(' . join(')|(', @regexlist) . '))$';
    $self->{MODULE_REGEXP} = qr/$mod_re/i; # Don't compile it; it will never change (even if reassigned)

    $self->set_optimization_level($self->_max_debuglevel());
    $self->check_for_callbacks();

    #print STDERR "module_regexp is: \"$self->{MODULE_REGEXP}\"\n";
    #print STDERR "module_hash: ", Dumper($self->{MODULE_HASH});
    #print STDERR "Returning: ", join(", ", sort keys %modules), "\n";
    return \%modules;
}

sub get_debugmask
{
    my $self = shift;
    my $dbglist = shift;
    my %retval = (%{$self->{MODULE_HASH}});

    $self->set_debugmask($dbglist) if defined($dbglist);
    return \%retval;
}

sub str_debugmask
{
    my $self = shift;
    my $lead = shift;
    my $lead2 = shift || "\n";

    #my $str = $lead . join($lead2 . $lead, sort keys %{$self->{MODULE_HASH}});
    my $str = Dumper($self->{MODULE_HASH});

    return $lead . $str;
}

sub accessor
{
    my $self = shift;
    my $key = shift;
    my $value = shift;
    my $retval = $self->{VARS}->{$key};

    $self->{VARS}->{$key} = $value if defined($value);
    return $retval;
}

# sub ok
# {
#     my $self = shift;
#     my $level = shift;

#     confess "level is undef" unless defined($level);
#     confess "loglevel is undef" unless defined($self->accessor('LOGLEVEL'));
#     return $level <= $self->accessor('LOGLEVEL');
# }

sub _pkg_matches
{
    my $self = shift;
    my $pkg = shift;
    my @rev = reverse split(/::/, $pkg);
    #print STDERR "rev is: <", join(',', @rev), ">\n";
    push(@rev, qw(* * * *)); # Make sure we have at least four items
    my $quad = join('::', @rev[0..3]); # Exactly four

    #my @foo;
    #print STDERR "Matching \"$quad\" to \"", $self->{MODULE_REGEXP}, "\"\n";
    #@foo = ($quad =~ m/$self->{MODULE_REGEXP}/);
    #print STDERR "pm Results are: ", Dumper(\@foo);
    my $result = $quad =~ m/$self->{MODULE_REGEXP}/;
    # Use @- to find which exp matched
    #print STDERR $result ? "Got match (result is \"$result\"\n" : "no match\n";
    #print STDERR "match id: ", $#-, "\n";
    #print STDERR "match module: ", ${$self->{MODULE_LIST}}[$#- - 1], "\n";
    #print STDERR "-: ", Dumper(\@-);
    #print STDERR "+: ", Dumper(\@+);

    my $matched_module = ${$self->{MODULE_LIST}}[$#- - 1];
    $result += 0;               # Force it to be numeric
    my $loglevel = $result ? $self->{MODULE_HASH}->{$matched_module}->{LEVEL} : $self->accessor('LOGLEVEL');
    #print STDERR "pm: for $pkg, returning ($result, $loglevel)\n";
    return ($result, $loglevel);
}

sub _max_debuglevel
{
    my $self = shift;
    my $max_level = $self->accessor('LOGLEVEL');
    my $level;

    foreach my $quad (keys %{$self->{MODULE_HASH}})
    {
        $level = $self->{MODULE_HASH}->{$quad}->{LEVEL};
        $level = $L_SILENT unless defined($level);
        $max_level = $level > $max_level ? $level : $max_level;
    }

    return $max_level;
}

sub _log
{
    my $self = shift;
    my $call_args = shift;

    # If caller passes in an argref as the first parameter, allow override of the defaults by the caller
    my %caller_args;
    %caller_args = %{$_[0]}, shift if ref $_[0] eq 'HASH';

    my %argref = (
        decorate => 1,
        call_depth => 1,
        query => 0,
        package => '',
        force_match => 0,
        i18n => 1,

        %{$call_args},          # Logger call customization
        %caller_args,           # Caller customization
        );

    #print STDERR "Logger:_log: argref is:", Dumper(\%argref);
    #print STDERR "Logger:_log: caller is: <", join(',',caller(2)), ">\n" unless exists($argref{level});
    #print STDERR "Logger:_log: call_depth is: ", $argref{call_depth}, " caller: ", (caller($argref{call_depth}))[0], "\n";
    my $level = exists $argref{level} ? $argref{level} : 0;
    my $isquery = $argref{query};
    my $force_match = $argref{force_match} || $isquery;

    # The caller can supply a package name. Otherwise, determine it automatically
    my $package = $argref{package} ? $argref{package} : (caller($argref{call_depth}))[0];
    my ($got_match, $l_level) = $self->_pkg_matches($package);
    my $debugmask_ok = $force_match || $got_match;

    #if ($package =~ m/sync/i)
    #{
    #    print STDERR "ok if ($level <= $l_level), q: $isquery, fm: $force_match, dmok: $debugmask_ok, $package (", join(' ', @_), ")\n";
    #}
    return if ($level > $l_level) and !$isquery and !$force_match;
    return if !$debugmask_ok;

    my $fh = $self->{LOG_OUT};
    my $decorate = $argref{decorate};
    my $i18n_lookup = $argref{i18n};

    my $prepend = '';

    #print STDERR "modlist: ", Dumper($self->{MODULE_HASH}) if $package =~ m/Validate/;
    #print STDERR "Log: should print\n";
    if ($self->accessor('USE_XML'))
    {
        my $type = $isquery ? 'QUERY' : 'MSG';
        print "<LOGMESSAGE>\n";
        print "<LEVEL>", $level_to_name{$level}, "</LEVEL>\n";
        print "<SOURCE>$package</SOURCE>\n" if $decorate;
        print "<TIME>", strftime("%y-%m-%d %H:%M:%S ", localtime), "</TIME>\n" if $decorate;
        if ($i18n_lookup)
        {
            print "<$type>", $self->{LH}->maketext(@_), "</$type>\n";
        }
        else
        {
            print "<$type>", @_, "</$type>\n";
        }
        print "</LOGMESSAGE>\n";
    }
    else
    {
        return unless $fh;

        if ($decorate)
        {
            my $time = $self->accessor('SHOW_TIME') ? strftime("%y-%m-%d %H:%M:%S ", localtime) : '';
            $prepend = $time . $package . ': ';
        }

        if ($i18n_lookup)
        {
            print $fh ($prepend, $self->{LH}->maketext(@_));
        }
        else
        {
            print $fh ($prepend, @_);
        }
    }

    my $ans = '';
    if ($isquery)
    {
        $ans = <>;
        if( defined $ans ) {
            chomp $ans;
        }
        else { # user hit ctrl-D
            $self->silent_q({force_match=>1}, "\n");
        }

    }

    return $ans;
}

sub would_I_print
{
    my $desired_level = shift;
    my $self = get_logger();

    #my $package = $argref{package} ? $argref{package} : caller(1);
    my $package = caller(1);
    my ($got_match, $l_level) = $self->_pkg_matches($package);

    return ($got_match && ($desired_level <= $l_level)) + 0;
}

sub idv_null
{
    return;
}

# Really, a replacement for 'print'
sub idv_print
{
    return get_logger()->_log({level => $L_SILENT, decorate => 0, force_match => 1}, @_);
}

sub idv_print_noi18n
{
    # Text is already translated.
    return get_logger()->_log({level => $L_SILENT, decorate => 0, force_match => 1, i18n => 0}, @_);
}

sub query
{
    # It is assumed that all query text has already been translated.
    my $ans = get_logger()->_log({level => $L_SILENT, decorate => 0, query => 1, i18n => 0}, @_);
    #print STDERR "Logger::query returning <$ans>\n";
    return $ans;
}

sub silent
{
    return get_logger()->_log({level => $L_SILENT}, @_);
}

sub silent_q
{
    return get_logger()->_log({level => $L_SILENT, decorate => 0}, @_);
}

sub quiet
{
    return get_logger()->_log({level => $L_QUIET}, @_);
}

sub info
{
    return get_logger()->_log({level => $L_INFO}, @_);
}

sub info_q
{
    return get_logger()->_log({level => $L_INFO, decorate => 0}, @_);
}

sub verbose
{
    return _verbose_sub(@_);
}

sub chatty
{
    return _chatty_sub(@_);
}

sub idv_dbg
{
    return _idv_dbg_sub(@_);
}

sub idv_dumper
{
    return _idv_dumper_sub(@_);
}

sub verbose_real
{
    return get_logger()->_log({level => $L_VERBOSE, call_depth => 2}, @_);
}

sub chatty_real
{
    return get_logger()->_log({level => $L_CHATTY, call_depth => 2}, @_);
}

sub idv_dbg_real
{
    return get_logger()->_log({level => $L_DEBUG, call_depth => 2}, @_);
}

sub idv_warn
{
    push(@warnings, join("", @_));
    return get_logger()->_log({level => $L_QUIET, force_match => 1}, @_);
}

sub _warn
{
    my $self = shift;

    push(@warnings, join("", @_));
    return $self->_log({level => $L_QUIET, force_match => 1, call_depth => 2}, @_);
}

sub fatal
{
    # If caller passes in an argref as the first parameter, allow override of the defaults by the caller
    my %caller_args;
    %caller_args = %{$_[0]}, shift if ref $_[0] eq 'HASH';
    my $show_trace = exists $caller_args{show_trace} ? $caller_args{show_trace} : get_logger()->accessor('SHOW_TRACE');

    get_logger()->_log({level => $L_QUIET, force_match => 1, call_depth => 2}, @_);

    if ($show_trace)
    {
        Carp::confess(get_logger()->{LH}->maketext(@_));
    }
    else
    {
        Carp::croak(get_logger()->{LH}->maketext(@_));
    }
}

sub get_warnings
{
    my $self = shift;

    return @warnings;
}

sub make_custom_logger
{
    my $self = shift;
    my $argref = shift;

    #print STDERR "Making custom logger with: ", Dumper($argref);
    return sub {
        return $self->_log($argref, @_)
    }
}

# Not for general use - should only be used (once) by the driver program, after
# enough options are known.

sub re_init
{
    my $argref = shift;

    #print STDERR "re_init: ", Dumper($argref);
    $lo->accessor('LOGLEVEL', $argref->{level}) if exists $argref->{level};
    $lo->set_debugmask($argref->{debugmask}) if exists $argref->{debugmask};
    $lo->accessor('SHOW_TRACE', $argref->{show_trace})if exists $argref->{show_trace};
    $lo->accessor('SHOW_TIME', $argref->{show_time}) if exists $argref->{show_time};
    $lo->accessor('USE_XML', $argref->{xml}) if exists $argref->{xml};
    $lo->accessor('FROM', $argref->{from}) if exists $argref->{from};

    $lo->set_fh('LOG_OUT',  safe_get($argref, 'log_out', $default_output)) if exists $argref->{log_out};
    $lo->set_fh('PRINT_TO', safe_get($argref, 'print_to', $default_output)) if exists $argref->{print_to};

    flush_cache('_pkg_matches');
    #$lo->str("after end of re_init");
    return;
}

sub get_logger
{
    return $lo;
}

sub get_settings
{
    my %settings;

    $settings{level} = $lo->accessor('LOGLEVEL');
    $settings{debugmask} = $lo->get_debugmask();
    $settings{show_trace} = $lo->accessor('SHOW_TRACE');
    $settings{show_time} = $lo->accessor('SHOW_TIME');
    $settings{use_xml} = $lo->accessor('USE_XML');
    $settings{from} = $lo->accessor('FROM');
    $settings{log_out} = $lo->accessor('LOG_OUT');
    $settings{print_to} = $lo->accessor('PRINT_TO');

    return \%settings;
}

sub set_optimization_level
{
    my $self = shift;
    my $level = shift;

    print STDERR "Logger::set_optimization_level level is $level\n";
    no warnings 'redefine';
    if ($level < $L_VERBOSE)
    {
        *_verbose_sub = \&idv_null;
        *_chatty_sub = \&idv_null;
        *_idv_dbg_sub = \&idv_null;
        *_idv_dumper_sub = \&idv_null;
    }
    elsif ($level == $L_VERBOSE)
    {
        *_verbose_sub = \&verbose_real;
        *_chatty_sub = \&idv_null;
        *_idv_dbg_sub = \&idv_null;
        *_idv_dumper_sub = \&idv_null;
    }
    elsif ($level == $L_CHATTY)
    {
        *_verbose_sub = \&verbose_real;
        *_chatty_sub = \&chatty_real;
        *_idv_dbg_sub = \&idv_null;
        *_idv_dumper_sub = \&Dumper;
    }
    else #($level >= $L_DEBUG)
    {
        *_verbose_sub = \&verbose_real;
        *_chatty_sub = \&chatty_real;
        *_idv_dbg_sub = \&idv_dbg_real;
        *_idv_dumper_sub = \&Dumper;
    }

    return;
}

sub _create_logger
{
    $L_SILENT      = -1;
    $L_QUIET       = 0;
    $L_INFO        = 1;
    $L_VERBOSE     = 2;
    $L_CHATTY      = 3;
    $L_DEBUG       = 4;

    %DEBUG_MACROS =
        ( 'DBG_STARTUP' => [qw(ProviderMgr)],
          'DBG_PROCESS' => [qw(Common Converter DoDots Provider ServiceLocator)],
          'DBG_CONFIG'  => [qw(Config Select Validate)],
          'DBG_PROVIDERS' => [qw(ProviderMgr)],
        );

    %level_to_name = (-1 => 'silent',
                      0  => 'quiet',
                      1  => 'info',
                      2  => 'verbose',
                      3  => 'chatty',
                      4  => 'debug',
    );

    foreach my $key (keys %level_to_name)
    {
        $name_to_level{$level_to_name{$key}} = $key;
    }

    memoize('_pkg_matches');

    #$default_output = 'STDOUT';
    $default_output = 'STDERR';
    *_verbose_sub = \&idv_null;
    *_chatty_sub = \&idv_null;
    *_idv_dbg_sub = \&idv_null;
    *_idv_dumper_sub = \&idv_null;
    $lo = Idval::Logger->new({development => 0,
                              log_out => 'STDERR'});

}

BEGIN {
    _create_logger();
}

1;
