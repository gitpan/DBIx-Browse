#
# $Id: test.pl,v 1.10 2002/03/06 17:46:20 evilio Exp $
#
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $max = 8; $| = 1; print "1..$max\n"; }
END {print "not ok 1\n" unless $loaded;}
use CGI;
use DBI;
use DBIx::Browse;
use DBIx::Browse::CGI;
use diagnostics;
use strict;
use vars qw( $test $max $loaded );
my ( $dbh, $dbix, $dbix_cgi);

$loaded = 1;
$test   = 1;
ok($test); #1

#
# other tests
#
if ( $ENV{DBIX_BROWSE_MAKE_TEST} && $ENV{DBI_DSN} ) {
    $dbh  = DBI->connect();
    $dbix = new DBIx::Browse({
	debug         => 1,
	dbh           => $dbh,
	table         => 'item',
	proper_fields => [ qw( name  )],
	linked_fields => [ qw( class )]
	});
    ok(); #2

    # insert
    $dbh->do("INSERT INTO class(name) VALUES('test2')");
    $dbix->insert({
	name  => 'test2',
	class => 'test2'
	});
    ok(); #4

    # prepare 
    my $sth = $dbix->prepare({
	where => ' class = ? '
	});
    $sth->execute('test2');
    my $row = $sth->fetchrow_hashref();
    ok(); #5
    
    # pkey_name
    my $pk = $dbix->pkey_name;
    my $id = $row->{$pk};
    $sth->finish;
    ok(); #6

    # update
    $dbix->update(
	{class => 'test3'},
	"id = ".$dbh->quote($id)
    );
    ok(); #7

    # delete
    $dbix->delete($id);
    ok(); #8
}
else {
    print "Skipping DBI tests (2..$max) on this platform.\n";
    exit(0);
}
#
# clean dbh
#
$dbh->do("DELETE FROM item  WHERE name LIKE 'test%'");
$dbh->do("DELETE FROM class WHERE name LIKE 'test%'");
$dbh->commit();
$dbh->disconnect();
#
# ok
#
sub ok {
	print "\nok $test\n";
	$test++;
}
1;
