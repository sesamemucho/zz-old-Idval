package Idval::Converter;

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
#use File::Temp qw/ tmpnam /;
use File::Temp qw/ :POSIX /;

use Idval::Logger qw(idv_dbg fatal);
use Idval::Common;
use base qw(Idval::Provider);

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    bless($self, ref($class) || $class);
    return $self;
}

package Idval::Converter::Smoosh;
use strict;
use warnings;
use Data::Dumper;
use Memoize;

use Idval::Logger qw(verbose idv_dbg);
use Idval::Common;
use base qw(Idval::Converter);

memoize('get_typemap');

sub new
{
    my $class = shift;
    my $from = shift;
    my $to = shift;
    my @cnv_list = @_;
    fatal("No converters in smoosh?") unless @_ and defined($_[0]);
    my $name = join('/', map{$_->query('name')} @cnv_list);
    my $config = $cnv_list[0]->{CONFIG}; # They all have the same CONFIG object.
    my $self = $class->SUPER::new($config, $name);
    bless($self, ref($class) || $class);
    $self->init($from, $to, @cnv_list);
    return $self;
}

sub init
{
    my $self = shift;
    my $from = shift;
    my $to = shift;
    my @converters = @_;

    $self->{CONVERTERS} = [@converters];
    $self->{FIRSTCONVERTER} = $converters[0];
    $self->{LASTCONVERTER} = $converters[-1];

    verbose("Smooshing: ", join(" -> ", map { $_->query('name') } @{$self->{CONVERTERS}}), "\n");
    $self->{TO} = $to;
    $self->add_endpoint($from, $to);
    $self->set_param('name', $self->{NAME});
    $self->set_param('attributes', $self->{LASTCONVERTER}->query('attributes'));

    my $is_ok = 1;
    map { $is_ok &&= $_->query('is_ok') } @{$self->{CONVERTERS}};

    $self->set_param('is_ok', $is_ok);

    return;
}

sub convert
{
    my $self = shift;
    my $rec = shift;
    my $dest = shift;

    my $src = $rec->get_name();

    return 0 if !$self->query('is_ok');

    my $from_file = $src;
    my $first_time_through = 1;
    my $to_type;
    my $to_file;
    my $ext;
    my @temporary_files;
    my $retval;
    # Make a copy of the input record so we can fool with it
    my $tag_record = Idval::Record->new({Record=>$rec});
    #print "Dump of record is:", Dumper($tag_record);

    foreach my $conv (@{$self->{CONVERTERS}})
    {

        if ($conv == $self->{LASTCONVERTER})
        {
            $to_file = $dest;
        }
        else
        {
            $to_type = $conv->query('to');
            $to_file = File::Temp::tmpnam() . '.' . $self->get_typemap()->get_output_ext_from_filetype($to_type);
            push(@temporary_files, $to_file);
        }

        verbose("Converting ", $tag_record->get_name(), " to $to_file using ", $conv->query('name'), "\n");
        $retval = $conv->convert($tag_record, $to_file);
        last if $retval != 0;

        $tag_record->set_name($to_file);
    }

    unlink @temporary_files;

    return $retval;
}

sub get_source_filepath
{
    my $self = shift;
    my $rec = shift;

     
    return $self->{FIRSTCONVERTER}->get_source_filepath($rec);
}

sub get_dest_filename
{
    my $self = shift;
    my $rec = shift;
    my $dest_name = shift;
    my $dest_ext = shift;

    idv_dbg("First dest name: [_1], dest ext: [_2]\n", $dest_name, $dest_ext); ##debug1
    foreach my $conv (@{$self->{CONVERTERS}})
    {
        $dest_name = $conv->get_dest_filename($rec, $dest_name, $dest_ext);
        idv_dbg("Dest name is now \"[_1]\" ([_2])\n", $dest_name, $conv->query('name')); ##debug1
    }

    return $dest_name;

}

sub get_typemap
{
    my $self = shift;

    return Idval::Common::get_common_object('typemap');
}

1;
