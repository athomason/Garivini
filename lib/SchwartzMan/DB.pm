package SchwartzMan::DB;
use strict;
use warnings;

use fields ('db_config',
            'dbh_cache',
            'db_avoid',
           );

use Carp qw/croak/;

use List::Util qw/shuffle/;
use DBI;

use constant DB_RETRY_DEFAULT => 30;

sub new {
    my SchwartzMan::DB $self = shift;
    $self = fields::new($self) unless ref $self;
    my %args = @_;

    $self->{dbh_cache} = {};
    # TODO: Configuration verification!
    $self->{db_config} = $args{dbs};
    $self->{db_avoid}  = {};
}

# Avoid DB's that are down for a while.
# TODO: Can we use DBI->connect_cached with a private key? only issue is
# the damn retry avoidance code.
# TODO: Golf this stupid thing down a bunch. Why can I never write these in
# like FOUR lines?
sub get_dbh {
    my $self = shift;
    my $dbid = shift;
    my @dbs  = ();

    # Return a specific database handle if we're looking for one,
    # otherwise return a random one.
    if ($dbid) {
        $dbs[0] = $self->{db_config}{$dbid}
            or die "Uknown database id $dbid";
    } else {
        @dbs = keys %{$self->{db_config}};
        @dbs = shuffle(@dbs);
    }

    for my $db (@dbs) {
        my $dbh = $self->_db_connect($db);
        return ($dbh, $db->{id}) if $dbh;
    }
    return undef;
}

sub _db_connect {
    my $self = shift;
    my $db   = shift;
    return undef if $self->{db_avoid}{$db->{id}} > time();
    return $self->{dbh_cache}{$db->{id}}
        if exists $self->{dbh_cache}{$db->{id}};

    my $dbh  = DBI->connect($db->{dsn}, $db->{user}, $db->{pass},
        { PrintError => 0, PrintWarn => 0, RaiseError => 1 });
    if ($dbh) {
        $self->{dbh_cache}{$db->{id}} = $dbh;
    } else {
        $self->{db_avoid}{$db->{id}} = time() + RETRY_DEFAULT;
    }
    return $dbh;
}

sub do {
    my $self = shift;
    my $dbid = shift;
    my $sql  = shift;
    my @params = @_;

    my ($dbh, $dbid) = $self->get_dbh(dbid => $args{dbid});
    my $return = eval {
        $dbh->do($sql, @params);
    };
    if ($@) {
        # TODO: Only wipe cache on specific errors
        delete $self->{dbh_cache}{$dbid};
        die $@;
    } else {
        return $return;
    }
}

1;
