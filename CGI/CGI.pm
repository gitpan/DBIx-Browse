#
# $Id: CGI.pm,v 0.3 2002/03/07 13:45:34 evilio Exp $
#
package DBIx::Browse::CGI;

use strict;
use diagnostics;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

use CGI;
use CGI::Carp;

require Exporter;
require DBIx::Browse;

@ISA = qw( DBIx::Browse  Exporter);

@EXPORT = qw(
);
#
# Keep Revision from CVS and Perl version in paralel.
#
$VERSION = do { my @r=(q$Revision: 0.3 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

#
# init
#
sub init {
    my $self  = shift;
    my $param = shift;

    my ( $cgi, $maxrows, $maxflength, $default_action,
	 $styles, $form_params);

    $cgi        = $param->{cgi} || new CGI;
    $maxrows    = $param->{max_rows} || 10;
    $maxflength =  $param->{max_flength} || 40;
    $default_action = $param->{default_action} || 'List';
    $form_params    = $param->{form_params} || {};
    $styles         = $param->{styles} || [ 'Even','Odd'];

    $self->{cgi}   = $cgi;
    $self->{max_rows}    = $maxrows;
    $self->{max_flength} = $maxflength;
    $self->{actions}     = {
	'List' => \&DBIx::Browse::CGI::list_form,
	'Edit' => \&DBIx::Browse::CGI::edit_form
	};
    $self->{default_action} = $default_action;
    $self->{form_params}    = $form_params;
    $self->{styles}         = $styles;
    #
    # This must be last
    #
    $self->SUPER::init( $param );

}

#
# list_form
#
sub list_form {
    my $self  = shift;
    my $param = shift || {};
    my $q = $self->{cgi};
    my @columns;
    my @fnames;
    my @forder;
    my @flength;
    my $where ='';
    my $row;
    my $rec = $q->param('record_number') || 0;

    if ($q->param('nextrec')) {
	$rec += 10;
    }

    if ($q->param('prevrec')) {
	$rec -= 10;
    }

    if ($q->param('firstrec')) {
	$rec = 0;
    }
 

    @columns = ( @{$self->{aliases}} );

    if ( $param->{field_names} &&
	 (scalar @{$param->{field_names}} == scalar @columns )) {
	@fnames = @{$param->{field_names}};
    } else {
	@fnames = @columns;
    }

    for (my $f = 0; $f < scalar( @columns ); $f++) {
	my $c = $columns[$f];
	#if ( grep( /^$c$/, @{$self->{aliases}} )) {
	#    my $i = $f - scalar(@{$self->{non_linked}});
	#    $c = $self->{table_aliases}->[$i+1].'.'.$self->{linked_values}->[$i]; 
	#}
	#else {
	#    $c = $self->{table_aliases}->[0].'.'.$c;
	#}
	if ( $q->param('search.'.$columns[$f]) ) {
	    $where .= $c; 
	    $where .= $self->{syntax}->{ilike};
	    $where .= $self->{dbh}->quote(
					  $self->{syntax}->{glob}.
					  $q->param('search.'.$columns[$f]).
					  $self->{syntax}->{glob}
					  );
	    $where .= ' AND ';
	}
    }
    $where =~ s/AND $//;

    $q->param(-name => 'where_clause', -value => "$where");
    
    my $last = $self->count( {where  => "$where"})-1;

    if ($q->param('lastrec')) {
	$rec = $last - $self->{max_rows} + 1;
    }

    $rec = ($rec <= ($last-$self->{max_rows}+1)) ? $rec : $last-$self->{max_rows}+1;
    $rec = ($rec < 0 ) ? 0 : $rec;

    my $sth = $self->prepare({
	where  => "$where",
	order  => $self->pkey_name.' ASC ',
	limit  => $self->{max_rows},
	offset => "$rec"
	});
    $sth->execute();


    $q->param(-name => 'record_number', -value => "$rec" );



    if ( $param->{field_order} && 
	 (scalar @{$param->{field_order}} == scalar @columns) ) {
	@forder = @{$param->{field_order}};
    }
    else {
	@forder = (0..(scalar(@columns)-1));
    }

    if ( $param->{field_length} && 
	 (scalar @{$param->{field_length}} == scalar @columns) ) {
	@flength = @{$param->{field_length}};
    }
    else {
	
	@flength = map 
	{
	    if ($_){ ( $_ < $self->{max_flength}) ? $_ : $self->{max_flength}}
	    else { 0; }
	} 
	@{ $sth->{PRECISION} };
    }

    $self->debug('Number of rows: '.$sth->rows());


    print
	$self->open_form($rec),
	$q->hidden( -name  => 'where_clause' ),
	$q->start_table,"\n";

    print
	$q->script({-language => 'JavaScript'},
		   "
function set_rc(f, i) {f.record_number.value = Number(f.record_number.value)+i; return true;}
function zero_rec(f) {f.record_number.value = 0;}\n" 
		   );

    print
	$q->start_Tr,"\n",
	$q->td('&nbsp;');
    foreach my $f ( @forder ) {
	print $q->th(ucfirst($fnames[$f])),"\n";
    }
    print
	$q->end_Tr,"\n";

    my $style;
    for (my $i = 0; $i < $sth->rows && $i < $self->{max_rows}; $i++) {
	$style = $self->style_class($i);
	if ( $row = $sth->fetchrow_hashref('NAME_lc') ) {
	    print $q->start_Tr(),"\n";
	    print $q->td({-class => 'Bar'},
			 $q->submit(
				    -name    => 'Page',
				    -value   => 'Edit',
				    -onClick => "set_rc(this.form, $i);"
				    )
				    
			 );
	    foreach my $f ( @forder ) {
		print
		    $q->td( { -class => "$style"},
			   $row->{$columns[$f]} || ''
			   ),"\n";
	    }
	    print $q->end_Tr(),"\n";
	}
    }

    
    print
	$q->start_Tr,"\n",
	$q->td('&nbsp');

    foreach my $f ( @forder ) {
	my $tf = {-name => 'search.'.$columns[$f],
		  -onChange => 'zero_rec(this.form); this.form.submit();',
		  };
	if ($flength[$f]) {$tf->{'-size'} = $flength[$f]};

	print $q->td(
		     $q->textfield($tf)
		     ),"\n";
    }
    print
	$q->end_Tr,"\n";

    print
	$q->start_Tr,
	$q->td('&nbsp'),
	$q->start_td( {
	    -colspan => scalar @fnames,
	    -align   => 'center'
		       }),"\n";

    $self->navigator('List');

    print
	$q->end_td,
	$q->end_Tr;

    print
	$q->end_table,"\n";
	$self->close_form;
}

#
# edit_form
#
sub edit_form {
    my $self   = shift;
    my $param  = shift || {};
    my $rownum;
    if ( ref($param) ne 'HASH') {
	$rownum = $param;
	$param  = {};
    } 
    else {
	$rownum = shift;
    }
    my $where  = shift || $self->{cgi}->param('where_clause');


    my @columns;
    my @fnames;
    my @flength;
    my @forder;

    my $q = $self->{cgi};

    my $rec = ($rownum || $q->param('record_number') || 0 );

    my $last = $self->count( {where  => "$where"})-1;

    if ($q->param('nextrec')) {
	$rec++;
    }

    if ($q->param('prevrec')) {
	$rec--;
    }

    if ($q->param('firstrec')) {
	$rec = 0;
    }
    
    if ($q->param('lastrec')) {
	$rec = $last
    }

    $rec = ($rec <= $last ) ?  $rec : $last;
    $rec = ($rec <  0 )     ?  0    : $rec;

    $q->param(-name => 'record_number', -value => "$rec" );

    my $sth = $self->prepare({
	where  => $where,
	order  => $self->pkey_name.' ASC ',
	limit  => 1,
	offset => "$rec"
	})  or $self->die();

    $sth->execute()  or $self->die();
    my $row = $sth->fetchrow_hashref('NAME_lc')  or $self->die();

    #
    # column names
    #
    @columns = ( @{$self->{aliases}} );

    if ( $param->{field_names} &&
	 (scalar @{$param->{field_names}} == scalar @columns )) {
	@fnames = @{$param->{field_names}};
    } else {
	@fnames = @columns;
    }

    if ( $param->{field_order} && 
	 (scalar @{$param->{field_order}} == scalar @columns) ) {
	@forder = @{$param->{field_order}};
    }
    else {
	@forder = (0..(scalar(@columns)-1));
    }

    if ( $param->{field_length} && 
	 (scalar @{$param->{field_length}} == scalar @columns) ) {
	@flength = @{$param->{field_length}};
    }
    else {
	@flength = map 
	{
	    if ($_) {($_ < $self->{max_flength}) ? $_ : $self->{max_flength}}
	    else {0;}
	} 
	@{ $sth->{PRECISION} };
    }
    #
    # actions
    #
    my $redo_query = 1;
    if ( $q->param('add') ) {
	my $record = {};
	foreach my $f ( @columns ) {
	    $record->{$f} = $q->param($f);
	}
	$self->insert($record);
	$q->delete('add');

	my $nwhere;
	foreach my $w  ( keys %$record ) {
	   $nwhere .= 
	       $self->{table_aliases}->[0].'.'.$w.
		   " = ".
		       $self->{dbh}->quote($record->{$w})." AND ";
	}
	$nwhere =~ s/AND $//;

	$sth->finish()  or $self->die();
	$rec = 0;
	$sth = $self->prepare({
	    where  => $nwhere,
	    order  => $self->pkey_name.' DESC ',
	    limit  => 1,
	    offset => "$rec"
	    }) or $self->die();

    }
    elsif ( $q->param('update') ) {
	my $record = {};
	foreach my $f ( @columns ) {
	    $record->{$f} = $q->param($f);
	}
	$self->update($record, 
		      $self->{primary_key}." = ".
		      $row->{$self->pkey_name}
		      );
	$q->delete('update');
    }
    elsif ( $q->param('remove') ){
	$self->delete($row->{$self->pkey_name});
	$rec = ( $rec > 0 ) ? ($rec-1) : $rec;
	$q->param(-name => 'record_number', -value => "$rec" );
	$q->delete('remove');
    }
    else {
	$redo_query = 0;
    }
    if ( $redo_query ) {
	$sth->execute()  or $self->die();
	$row = $sth->fetchrow_hashref('NAME_lc')  or $self->die();
    }

    # debug info
    if ($self->debug) {
	my $parstr = 'Parameters: ';
	my @P = $q->param;
	foreach my $p ( @P ) {
	    $parstr .= "$p  =  ".$q->param($p).$q->br();
	}
	$self->debug($parstr);
    }



    print
	$self->open_form($rec),
	$q->hidden( -name  => 'where_clause' ),
	$q->start_table,"\n";

    my $style;
    foreach my $f ( @forder ) {
	$style = $self->style_class($f);
	my $tf = {
	    -name    => $columns[$f],
	    -default => $row->{$columns[$f]},
	};
	if ($flength[$f]) {$tf->{'-size'} = $flength[$f]};

	print
	    $q->start_Tr,"\n",
	    $q->th(ucfirst($fnames[$f])),"\n",
	    $q->start_td( {-class => "$style"} );
	if ($f < @{$self->{non_linked}} ) {
	    # Set the param
	    $q->param(-name  => $columns[$f],
		      -value => $row->{$columns[$f]});
	    print $q->textfield($tf);
	#    print
	#	$q->comment("Field: ".$fnames[$f].
	#		    ", Value: ".$row->{$columns[$f]});
	}
	else {
	    ### value list ###
	    my $fvalues = $self->field_values($f);
	    # Set the param
	    $q->param(-name  => $columns[$f],
		      -value => $row->{$columns[$f]});
	    # PopUp
	    print $q->popup_menu(
				-name     => $columns[$f],
				-values   => $fvalues,
				-default  => $row->{$columns[$f]},
				);
	    # debug comment
	    #print
	    #   $q->comment("Field: ".$fnames[$f].
	    #	    ", Value: ".$row->{$columns[$f]});
	}
	print
	    $q->end_td,"\n";
	print
	    $q->end_Tr,"\n";
    }
    # Editor
    print
	$q->start_Tr,
	$q->start_td( {
	    -colspan => 2,
	    -align   => 'center'		       }),"\n";
    $self->editor();
    print
	$q->end_td,
	$q->end_Tr;
    #Navigator
    print
	$q->start_Tr,
	$q->start_td( {
	    -colspan => 2,
	    -align   => 'center'
		       }),"\n";
    $self->navigator('Edit');
    print
	$q->end_td,
	$q->end_Tr;
    # End table
    print
	$q->end_table,"\n";

    $self->close_form;
}

#
# open_form
#
sub open_form {
    my $self = shift;
    my $rec  = shift;
    my $q    = $self->{cgi};
    my $text = '';
    $text  = $q->start_multipart_form( -name => 'Browser_'.$self->{table}, -method => 'POST' );
    $text .= "\n".$q->hidden(-name => 'record_number', -value => "$rec");
    if( my @fparams = keys %{$self->{form_params}} ) {
	$self->debug('Form Params: '.join(', ', @fparams));
	foreach my $p ( @fparams ) {
	    $text .= $q->hidden(
			      -name  => $p,
			      -value => $self->{form_params}->{$p}
			     );
	}
    }
    return $text;
}

#
# close_form
#
sub close_form   {
    my $self = shift;
    my $q    = $self->{cgi};
    return $q->end_form;
}

#
# navigator
#
sub navigator {
    my $self  = shift;
    my $page  = shift;
    my $q     = $self->{cgi};

    $q->param( -name => 'Page', -value => $page);

    print
	$q->start_table( -align => 'CENTER' ),"\n";
    print
	$q->hidden(-name => 'Page'),"\n",
	$q->Tr({ -class => 'Bar'}, "\n",
	       $q->td( { -class => 'Bar'},
		      $q->submit(
				 -name  => 'firstrec',
				 -value => 'First'
				 )
		      ),"\n",
	       $q->td(
		      $q->submit(
				 -name  => 'prevrec',
				 -value => 'Prev'
				 )
		      ),"\n",
	       $q->td(
		      $q->submit(
				 -name  => 'nextrec',
				 -value => 'Next'
				 )
		      ),"\n",
	       $q->td(
		      $q->submit(
				 -name  => 'lastrec',
				 -value => 'Last'
				 )
		      )
	       ),"\n";	
    print
	$q->end_table;
}

#
# editor
#
sub editor {
    my $self  = shift;
    my $q     = $self->{cgi};
    print
	$q->start_table( -align => 'CENTER' ),"\n";
    print
	$q->Tr({ -class => 'Bar'}, "\n",
	       $q->td({ -class => 'Bar'},
		      $q->submit(
				 -name  => 'update',
				 -value => 'Update',
				 -onClick => 
				 "return window.confirm('Update: Are you sure?');"
				 )
		      ),"\n",
	       $q->td({ -class => 'Bar'},
		      $q->submit(
				 -name  => 'remove',
				 -value => 'Remove',
				 -onClick => 
				 "return window.confirm('Remove: Are you sure?');"

				 )
		      ),"\n",
	       $q->td({ -class => 'Bar'},
		      $q->submit(
				 -name  => 'add',
				 -value => 'Add',
				 -onClick => 
				 "return window.confirm('Add: Are you sure?');"
				 )
		      ),"\n",
	       $q->td({ -class => 'Bar'},
		      $q->reset(
				 -name  => 'Clear',
				 -value => 'Clear'
				 )
		      ),"\n",
	       $q->td({ -class => 'Bar'},
		      $q->submit(
				 -name  => 'cancel',
				 -value => ' Back ',
				 -onClick => "this.form.Page.value = 'List';"
				 )
		      )
	       ),"\n";
    print
	$q->end_table;
}

#
# generic browse
#
sub browse {
    my $self   = shift;
    my $param  = shift || {};

    my $action =  ($self->{cgi}->param('Page') or 
	          $self->{default_action});

    $self->debug("Action: $action");

  ACTION:
    {
	foreach my $a ( keys %{$self->{actions}} ) {
	    if ( $action eq $a) {
		$self->{actions}->{$a}->($self, $param->{$action});
		last ACTION;
	    }
	}
	# We should'n arrive here
	carp "Not a valid action: $action\n";
  }
}

#
# style_class
#
sub style_class {
    my $self = shift;
    my $num  = shift;
    my $s    = $num % scalar( @{$self->{styles}} );
    return $self->{styles}->[$s];
}
#
# debug
#
sub debug {
    my $self = shift;
    return (0) unless $self->{debug};
    my $txt  = shift;
    print $self->{cgi}->p({-class => 'Debug'},
			   $txt
			  ) if ($txt);
    return 1;
}
#
# print
#
sub print_error {
    my $self  = shift;
    my $error = shift;
    my $q     = $self->{cgi};

    foreach my $er ( split(/\n/m, $error)) {
	print $q->p({-Class => 'Error'}, $er);
    }
    print $q->end_html();
}

#########################################################################
1;
#
#
#
__END__

=head1 NAME

DBIx::Browse::CGI - Perl extension to browse tables with a CGI interface.

=head1 SYNOPSIS

  use DBIx::Browse::CGI;
  my ($dbh, $dbb, $q);
  $dbh = DBI->connect("DBI:Pg:dbname=enterprise")
    or croak "Can't connect to database: $@";
 $q   = new CGI;
 $dbb = new  DBIx::Browse::CGI({
    dbh => $dbh, 
    table => 'employee', 
    proper_fields => [ qw ( name fname ) ],
    linked_fields => [ qw ( department category office ) ], 
    linked_tables => [ qw ( department category office ) ], 
    linked_values => [ qw ( name       name     phone  ) ], 
    linked_refs   => [ qw ( id         id       ide    ) ],
    aliases       => [ qw ( name fname department category phone )],
    primary_key   => 'id',
    cgi           => $q
});
 print
    $q->start_html(
                   -title => "Test DBIx::Browse::CGI"
                   );
 $dbb->list_form({
    field_order  => [  1,  0,  4,  3,  2 ],
    field_length => [ 14, 15, 15, 15, 10 ]
 });


...etc

=head1 DESCRIPTION

The purpose of DBIx::Browse::CGI is to handle the browsing of relational
tables with a human-like interface via Web.

DBIx::Browse::CGI transparently translates SELECTs, UPDATEs, DELETEs
and INSERTs from the desired "human view" to the values needed for the
table. This is the case when you have related tables (1 to n) where
the detail table has a reference (FOREIGN KEY) to a generic table
(i.e. Customers and Bills) with some index (tipically an integer).

=head1 METHODS

All the inherited methods inherited from its parent class
(DBIX::Browse(3)) plus the following:

=over 4

=item B<new>

Creates a new DBIx::Browse::CGI object. The parameters are passed
through a hash with the following added keys:

=over 4

=item I<cgi>

A CGI object that will be used for Web interaction. If it is not
defined a new CGI object will be created.

=item I<max_rows>

The maximum number of rows to be displayed per Web page (default: 10).

=item I<max_flength>

The maximum field length to be displayed (also the default for unknown
field lengths).

=item I<default_action>

The default action (web page) that will be displayed if not set by the
calling program (currently "List" or "Edit".

=item I<form_params>

A hash ref containing other form parameters that will appear as
"HIDDEN" input fields.

=item I<styles>

An anonymous arrays of css styles ("CLASS") that will be applied to
succesive rows of output.


=back

=item B<list_form>

This method produces a CGI form suitable to explore the main table. It
will list its rows in chunks of I<max_rows>. It will present also the
possibility to edit (see B<edit_register>) any row and to filter the rows
to display.

It takes one optional parameter with a hash reference with the following keys:

=over 4

=item I<field_names>

An array reference containing the field names to be displayed.

=item I<field_order>

An array reference with the desired order index in wich the fields
will appear.

=item I<field_length>

An array reference with the desired field length.

=back


=item B<edit_form>

This method produces a CGI form suitable to browse the main table
record by record. You can update, delete and insert new records.

It takes one optional parameter with a hash reference with the same
structure than B<list_form>.

=item B<browse>

This method will call B<list_form> or B<edit_form> as needed depending on the user input.

It takes one optional parameter with a hash reference with the same
structure than B<list_form>.

=back

=head1 AUTHOR

Evilio José del Río Silván, edelrio@icm.csic.es

=head1 SEE ALSO

perl(1), DBI(3), CGI(3), DBIx::Browse(3).

=cut
