#
# $Id: test.pl,v 1.12 2002/04/27 11:21:44 evilio Exp $
#
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $max = 11; $| = 1; print "1..$max\n"; }
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

    my $dbh_single = new DBIx::Browse({dbh => $dbh, table => 'class'});
    ok(); # 3
    # this must fail:
    eval {
    my $dbh_bad = new DBIx::Browse({
        dbh           => $dbh,
        table         => 'item',
        proper_fields => [ qw( name  )],
        linked_fields => [ qw( class )],
	linked_tables => [ qw( class class ) ]
			});
	};
	die "Bad parameter checking" unless ($@);
	print "DBIx::Browse->new() failed OK (!): $@";
	ok(); # parameter check

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
    # cgi tests
    $dbix_cgi = new DBIx::Browse::CGI({
	debug         => 1,
	dbh           => $dbh,
	table         => 'item',
	proper_fields => [ qw( name  )],
	linked_fields => [ qw( class )],
	no_print      => 1
	});
    $dbix_cgi->insert({
	name  => 'test4',
	class => 'test2'
	});
    ok(); #  9
    # list_form
    my $lf = $dbix_cgi->list_form;
    ok(); # 10
    # edit_form
    my $ef = $dbix_cgi->edit_form(0);
    ok(); # 11
    my $bf = $dbix_cgi->browse;
    ok(); # 12
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
	print "ok $test\n";
	$test++;
}
1;
