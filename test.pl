#
# $Id: test.pl,v 1.8 2002/02/26 12:52:27 evilio Exp $
#
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..1\n"; }
END {print "not ok 1\n" unless $loaded;}
use DBIx::Browse; 
use IO::File;
use diagnostics;

my $dir = 'test_dbix';
my $tmp = "$dir/test.out";

my $fout =  new IO::File("> $tmp");

$loaded = 1;
ok(1);

sub ok {
	my $num = shift;
	print "\nok $num\n";
}
1;
