package CATS::Contest;

use strict;
use warnings;

sub database_fields {qw(
    id title
    start_date finish_date freeze_date defreeze_date
    closed penalty ctype rules
    is_official run_all_tests
    show_all_tests show_test_resources show_checker_comment show_packages
    local_only is_hidden
)}

use fields (database_fields(), qw(server_time time_since_start time_since_finish));

use lib '..';
use CATS::DB;

sub new
{
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}


sub load
{
    my ($self, $cid) = @_;
    my $all_fields = [
        database_fields(),
        'CATS_DATE(CATS_SYSDATE()) AS server_time',
        'CATS_SYSDATE() - start_date AS time_since_start',
        'CATS_SYSDATE() - finish_date AS time_since_finish'];
    my $r;
    if ($cid)
    {
        $r = CATS::DB::select_row(
            'contests', $all_fields, { id => $cid });
    }
    unless ($r)
    {
        # �� ��������� �������� ������������� ������
        $r = CATS::DB::select_row('contests', $all_fields, { ctype => 1 });
    }
    $r or die 'No contest';
    @{%$self}{keys %$r} = values %$r; 
}


sub is_practice
{
    my ($self) = @_;
    defined $self->{ctype} && $self->{ctype} == 1;
}


1;