use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	      'NAME'      => 'DBIx::Browse',
	      'PREREQ_PM' => {
		  'CGI'		=> '2.00',
		  'DBI'		=> '1.00'
		  },
	      'VERSION_FROM' => 'Browse.pm', # finds $VERSION
);
