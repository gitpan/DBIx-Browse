#
# $Id: Browse.pm,v 1.24 2002/02/27 17:32:13 evilio Exp $
#
package DBIx::Browse;

use strict;
use diagnostics;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

use CGI;
use CGI::Carp;
use DBI;

require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(
);
#
# Keep Revision from CVS and Perl version in paralel.
#
$VERSION = do { my @r=(q$Revision: 1.24 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

#
# new
#
sub new {
    my $this   = shift;
    my $class  = ref($this) || $this;
    my $self   = {};
    bless $self, $class;
    $self->init( @_ );
    return $self;
}

#
# init
#
sub init {
    my $self  = shift;
    my $param = shift;
    my ($dbh, $table, $pkey, $pfields, 
	$lfields , $ltables, $lvalues, $lrefs, $lalias, $styles,
	$cgi, $maxrows, $maxflength, $debug, $default_action, $form_params);

    $dbh        = $param->{dbh}   or croak 'No database handler.';
    $table      = $param->{table} or croak 'No table to browse.';
    $pkey       = $param->{primary_key} || 'id';
    $pfields    = $param->{proper_fields};
    $lfields    = $param->{linked_fields};
    $ltables    = $param->{linked_tables};
    $lvalues    = $param->{linked_values};
    $lrefs      = $param->{linked_refs};
    $lalias     = $param->{aliases};
    $cgi        = $param->{cgi} || new CGI;
    $maxrows    = $param->{max_rows} || 10;
    $maxflength =  $param->{max_flength} || 40;
    $debug      = $param->{debug};

    $default_action = $param->{default_action} || 'List';
    $form_params    = $param->{form_params} || {};
    $styles         = $param->{styles} || [ 'Even','Odd'];

    $self->{cgi}         = $cgi;
    $self->{dbh}   = $dbh;    
    eval { $self->{dbh}->{AutoCommit} = 0; };
    $self->die() if ($dbh->{AutoCommit}); 
    $self->{dbh}->{PrintError} = 0;
    $self->set_syntax();

    $self->{table} = lc("$table");
    $self->{primary_key} = $pkey;

    $self->{single} = 0;


    $self->{max_rows}    = $maxrows;
    $self->{max_flength} = $maxflength;
    $self->{debug}       = $debug;
    $self->{actions}     = {
	'List' => \&DBIx::Browse::list_form,
	'Edit' => \&DBIx::Browse::edit_form
	};
    $self->{default_action} = $default_action;
    $self->{form_params}    = $form_params;
    $self->{styles}         = $styles;


    if ( ! $lfields ) {
	$self->{single} = 1;
    }

    $self->{linked_fields} = [map {lc($_)} @$lfields];

    my @fields = $self->fields;

    if ( $pfields ) {
	$self->{non_linked} = [map {lc($_)} @$pfields];
    }
    else {
	$self->{non_linked} = [];
	foreach my $f ( @fields ) {
	    my $lnk = grep (/$f/i,  @{$self->{linked_fields}});
	    if ( ! $lnk ) {
		push @{$self->{non_linked}}, lc($f);
	    }
	}
    }

    if ( ! $ltables ) {
	$ltables = $self->{linked_fields};
    }
    $self->{linked_tables} = [map {lc($_)} @$ltables];

    my $n_ltables = 0;
    if ( $ltables ) {
	$n_ltables = scalar(@$ltables);
    }

    if ( ! $lvalues && $n_ltables ) {
	my $names = 'name,' x $n_ltables;
	my @lvalues =  split(/,/, $names, $n_ltables);
	$lvalues[$n_ltables-1] =~ s/,$//;
	$lvalues = \@lvalues;
    }
    $self->{linked_values} = [map {lc($_)} @$lvalues];

    if ( ! $lrefs && $n_ltables ) {
	my $ids =  'id,' x $n_ltables;
	my @lrefs = split( /,/, $ids, $n_ltables);
	$lrefs[$n_ltables-1] =~ s/,$//;
	$lrefs = \@lrefs;
    }

    if ( ! $lalias ) {
	$lalias = $ltables;
    }
    $self->{aliases} = [map {lc($_)} @$lalias];

    $self->{linked_refs} = [map {lc($_)} @$lrefs];

    my $table_alias = 'AAA';
    $self->{table_aliases} = [ "$table_alias" ];
    foreach my $t ( @{$self->{linked_tables}} ) {
	$table_alias++; # How nice is perl
	push(@{$self->{table_aliases}}, $table_alias);
    }

}
#
# query_fields
#
sub query_fields {
    my $self = shift;

    my $query = "";
    $query .= join(',',
		   map( $self->{table_aliases}->[0].".".$_ , @{$self->{non_linked}} )
			);
    unless ( $self->{single}) {
	for(my $lf = 0; $lf <  scalar(@{$self->{linked_fields}}); $lf++) {
	    $query .= ", ".$self->{table_aliases}->[$lf+1].".".
		$self->{linked_values}->[$lf].
		    ' AS '.$self->{aliases}->[$lf];
	}
    }

    # Include pkey always
    $query .= 
	', '.$self->{table_aliases}->[0].'.'.$self->{primary_key}.' AS '.
	    $self->pkey_name;

    return $query;
}
#
# query_tables
#
sub query_tables {
    my $self = shift;

    my $query = '';

    # tables list
    $query .= "\n FROM ".$self->{table}." ".$self->{table_aliases}->[0]." ";
    unless ( $self->{single} ) {
	my $i = 1;
	foreach my $lt ( @{$self->{linked_tables}} ) {
	    $query .= ", ".$lt." ".$self->{table_aliases}->[$i];
	    $i++;
	}

    # join condition
    $query .= "\n WHERE ";
    for(my $lf = 0; $lf <  scalar(@{$self->{linked_fields}}); $lf++)  {
	unless ($self->{linked_fields}->[$lf] =~ m/.+\..+/ ) {
	    $query .= 
		$self->{table_aliases}->[0].".";
	}
	$query .=
	    $self->{linked_fields}->[$lf] . " = ".
	    $self->{table_aliases}->[$lf+1].".".
	    $self->{linked_refs}->[$lf]. " AND ";
    }

    # Erase trailing AND 
    $query =~ s/AND $//;
    }

    return $query;
}

#
# query
#
sub query {
    my $self = shift;

    my $query = "SELECT ";

    $query .= $self->query_fields;

    $query .= $self->query_tables;

    return $query;
}


#
# count 
#
sub count {
    my $self   = shift;
    my $params = shift;

    $params->{fields} = ' count(*) ';

    my $counth = $self->prepare($params);

    $counth->execute;

    my ($count) = $counth->fetchrow_array;

    return $count;
}

#
# prepare
#
sub prepare {
    my $self  = shift;
    my $param = shift;
    my %syntax = %{$self->{syntax}};
    my %order  = %{$self->{syntax_order}};

    if ( $self->{single} ) {
	$syntax{where} = ' WHERE ';
    }

    # always use offset
    unless ($param->{offset}) {
	$param->{offset} = '0 ';
    }
    
    my $query = '';

    foreach my $num ( sort keys %order ) {
	my $p = $order{$num};
	if ( $param->{$p} ) {
	    $query .= "\n".$syntax{$p}.$param->{$p};
	    if ( ref($param->{$p}) eq 'HASH') {
		print 
		    "Par: ",$p,
		    ", Keys: ",join(':', keys   %{ $param->{$p} } ),
		    ", Vals: ",join(':', values %{ $param->{$p} } );
	    }
	}
    }

    if ( $param->{fields} ) {
	$query  = 'SELECT '.$param->{fields}.' '.$self->query_tables();
    }
    else  {
	$query = $self->query().' '.$query;
    }

    $self->debug("Prepare: ".$query."\n");

    return $self->{dbh}->prepare($query)
	or $self->die();
}

#
# demap
#
sub demap {
    my $self = shift;
    my $rec  = shift;

    unless ( $self->{single} ) {
	for my $test ( keys %{$rec} ) {
	    $self->debug("\t".$test.' => '.$rec->{$test})
	}
	for(my $f = 0; $f <  scalar( @{$self->{linked_fields}} ); $f++) {
	    my $fname = $self->{aliases}->[$f];
	    my $lnk = grep( /$fname/i, keys %$rec );
	    next unless $lnk;
	    my $qfield = 
		"SELECT ".$self->{linked_refs}->[$f].
		"  FROM ".$self->{linked_tables}->[$f].
		" WHERE ".$self->{linked_values}->[$f].
		"    = ?";
	    $self->debug('Demap: '.$qfield);
	    my $stf = $self->{dbh}->prepare($qfield)
		or $self->die();
	    $stf->execute($rec->{$fname})
		or $self->die();
	    my ($ref_value) = $stf->fetchrow_array;
	    delete $rec->{$fname};
	    $rec->{$self->{linked_fields}->[$f]} = $ref_value;
	}
    }
}

#
# insert
#
sub insert {
    my $self = shift;
    my $rec  = shift;

    my $query = 'INSERT INTO '.$self->{table}.'(';
    my $qval  = ' VALUES(';

    my @fields = $self->fields;

    $self->demap($rec);

    foreach my $f ( keys %$rec ) {
	my $fok = grep (/$f/i,  @fields );
	$query .= $f.',';
	$qval  .= $self->{dbh}->quote($rec->{$f}).",";
	next if $fok;
	$self->debug("Field not found: $f => ".$rec->{$f});
    }
    chop($query);
    chop($qval);
    $query .= ') '.$qval.')';
    $self->debug("Insert: ".$query);
    my $ok = $self->{dbh}->do($query) or $self->die();
    $self->{dbh}->commit() or $self->die();
    return $ok;
}

#
# update
#
sub update {
    my $self  = shift;
    my $rec   = shift;
    my $where = shift;
    my @fields = $self->fields;

    my $query = 'UPDATE  '.$self->{table}.' SET ';

    $self->demap($rec);

    foreach my $f ( keys %$rec ) {
	my $fok = grep (/$f/i,  @fields );
	$query .= $f.' = ';
	$query .= $self->{dbh}->quote($rec->{$f}).",";
	next if $fok;
	croak "Field not found: $f => ".$rec->{$f};
    }
    chop($query);

    
    $query .= ' WHERE '.$where if ($where);

    $self->debug(" Update: ".$query);
    my $ok = $self->{dbh}->do($query) or $self->die();
    $self->{dbh}->commit() or $self->die();
    return $ok;
}

#
# delete
#
sub delete {
    my $self  = shift;
    my $pkey  = shift;
    my $qdel  = 
	"DELETE FROM ".$self->{table}.
	" WHERE ".$self->{primary_key}." = ?";

    $self->debug("Delete: ".$qdel. ' [ ? = '.$pkey.']');
    my $sdel  = $self->{dbh}->prepare($qdel) or $self->die();
    my $rdel  = $sdel->execute($pkey) or $self->die();
    $self->{dbh}->commit() or $self->die();
    return $rdel;
}

#
# fields
#
sub fields {
    my $self   = shift;
    my $single = "SELECT * FROM ".$self->{table}." LIMIT 1";
    my $sth    = $self->{dbh}->prepare($single)  or $self->die();
    my $rh     = $sth->execute  or $self->die();
#    my $hrow   = $sth->fetchrow_hashref;
    my @fields = @{ $sth->{NAME_lc} };
#   sort keys %$hrow;
    return @fields;
}

#
# field_values
#
sub field_values {
    my $self  = shift;
    my $field = shift;
    my ($fname, $table, $id);
    if ( $field < scalar @{$self->{non_linked}}  ) {
	$fname = $self->{non_linked}->[$field];
	$id    = $self->{primary_key};
	$table = $self->{table};
    }
    else {
	$field -= scalar @{$self->{non_linked}};
	$fname = $self->{linked_values}->[$field];
	$id    = $self->{linked_refs}->[$field];
	$table = $self->{linked_tables}->[$field];
    }

    my $q = 'SELECT  DISTINCT '.$fname.' FROM '.$table.' ORDER BY '.$fname.';';

    #$self->debug('Field Values:'.$q);

    my $sth = $self->{dbh}->prepare($q) or $self->die();
    $sth->execute() or $self->die();

    my $rv = [];
    while (my @line = $sth->fetchrow_array()){
	push @{ $rv }, $line[0]; 
    }
    return $rv;
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
 
    if ( $self->{single} ) {
	@columns = @{$self->{non_linked}};
    }
    else {
	@columns = ( @{$self->{non_linked}}, @{$self->{aliases}} );
    }

    if ( $param->{field_names} &&
	 (scalar @{$param->{field_names}} == scalar @columns )) {
	@fnames = @{$param->{field_names}};
    } else {
	@fnames = @columns;
    }

    for (my $f = 0; $f < scalar( @columns ); $f++) {
	my $c = $columns[$f];
	if ( grep( /^$c$/, @{$self->{aliases}} )) {
	    my $i = $f - scalar(@{$self->{non_linked}});
	    $c = $self->{table_aliases}->[$i+1].'.'.$self->{linked_values}->[$i]; 
	}
	else {
	    $c = $self->{table_aliases}->[0].'.'.$c;
	}
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
    if ( $self->{single} ) {
	@columns = @{$self->{non_linked}};
    }
    else {
	@columns = ( @{$self->{non_linked}}, @{$self->{aliases}} );
    }

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
# pkey_name: primary key field name
#
sub pkey_name {
    my $self = shift;
    return $self->{table}.'_primary_key';
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
# set_syntax
#
sub set_syntax {

    my $self = shift;

    $self->{syntax_order} = {
	1 => 'where',
	2 => 'group',
	3 => 'having',
	4 => 'order',
	5 => 'limit',
	6 => 'offset'
	};


    $self->{syntax} = {
	'where'  => ' AND ',
	'group'  => ' GROUP BY ',
	'having' => ' HAVING ',
	'order'  => ' ORDER BY ',
	'limit'  => ' LIMIT ',
	'offset' => ' OFFSET ',
	'ilike'  => ' ~*  ',
	'glob'   => ''
	};

    #
    # Standards? Ha!
    #
    if ( $self->{dbh}->{Driver}->{Name} =~ m/mysql/i ) {
	$self->{syntax}->{limit}  = ',';
	$self->{syntax}->{offset} = ' LIMIT ';
	$self->{syntax}->{ilike}  = ' LIKE ';
	$self->{syntax}->{glob}   = '%';
	$self->{syntax_order}->{5} = 'offset';
	$self->{syntax_order}->{6} = 'limit';
    }
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
# sprint
#
sub sprint {
    my $self = shift;
    my $s    = ref($self)."\n";
    foreach my $tag ( sort keys %$self ) {
	$s .= "\t".$tag."\n";
	my $type = ref($self->{$tag});
	if ( $type eq 'HASH') {
	    foreach my $k ( sort keys %{$self->{$tag}} ) {
		$s .= "\t\t".$k."\t=> ".$self->{$tag}->{$k}."\n";
	    }
	}
	elsif ($type eq 'ARRAY') {
	    $s .= "\t\t(".join(",", @{$self->{$tag}}).")\n";
	}
	else {
	    $s .= "\t\t".$self->{$tag}."\n";
	}
    }
    return("$s");
}
#
#
#
sub die {
    my $self = shift;
    my $dbh  = $self->{dbh};
    my $err  = $dbh->errstr;
    my $q    = $self->{cgi};
    my @caller = caller;

    print
	$q->p(
	      {-Class => 'Error'},
	      "Error from database: ".$err
	      ),
	$q->p(
	      {-Class => 'Error'},
	      'At '.$caller[0].', '.$caller[1].' line '.$caller[2].'.'
	      ),
        $q->end_html();

    $dbh->rollback();
    exit();
}
#
# cvsid
#
sub cvsid {
    my $cvs     = q[ $Id: Browse.pm,v 1.24 2002/02/27 17:32:13 evilio Exp $ ];
    my $version = ( $cvs =~ m/\$Id:\s+\S+\s+(\d+\.\d+)+\s+.*/);
    return $version;
}
#########################################################################
1;
#
#
#
__END__

=head1 NAME

DBIx::Browse - Perl extension to browse tables with a CGI/Web interface.

=head1 SYNOPSIS

  use DBIx::Browse;
  my ($dbh, $dbb, $q);
  $dbh = DBI->connect("DBI:Pg:dbname=enterprise")
    or croak "Can't connect to database: $@";
 $q   = new CGI;
 $dbb = new  DBIx::Browse({
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
                   -title => "Test DBIx::Browse"
                   );
 $dbb->list_form({
    field_order  => [  1,  0,  4,  3,  2 ],
    field_length => [ 14, 15, 15, 15, 10 ]
 });


...etc

=head1 DESCRIPTION

 The purpose of DBIx::Browse is to handle the browsing of relational
 tables with a human-like interface via Web.

 DBIx::Browse transparently translates SELECTs, UPDATEs, DELETEs and INSERTs
 from the desired "human view" to the values needed for the table. This is the
 case when you have related tables (1 to n) where the detail table
 has a reference (FOREIGN KEY) to a generic table (i.e. Customers and
 Bills) with some index (tipically an integer).

=head1 METHODS

=over 4

=item B<new>

Creates a new DBIx::Browse object. The parameters are passed
throug a hash with the following keys:

=over 4

=item I<dbh>

A DBI database handle already opened that will be used for all
database interaction.

=item I<table>

The main (detail) table to browse.

=item I<primary_key>

The primary key of the main I<table> (default: I<'id'>).

=item I<proper_fields>

An array ref of field names of the main table that are not related
to any other table.

=item I<linked_fields>

An array reference of field names of the main table that are related
to other tables.

=item I<linked_tables>

An array reference of related table names corresponding to each
element of the I<linked_fields> parameter.

=item I<linked_values>

The "human" values of each I<linked_fields> (a field name of the
corresponding I<linked_tables> element, default: 'name').

=item I<linked_refs>

The foreign key field name that relates the values of the
I<linked_fields> with the I<linked_tables> (default: 'id').

If present, I<linked_tables>, and I<linked_refs> must have the same
number of elements than I<linked_fields>.

=item I<aliases>

An array ref containing the field aliases (names that will be
displayed) of the table. This must include all, proper and linked fields.

=item I<cgi>

A CGI object that will be used for Web interaction. If it is not
defined a new CGI object will be created.

=item I<max_rows>

The maximum number of rows to be displayed per Web page (default: 10).

=item I<max_flength>

The maximum field length to be displayed (also the default for unknown
field lengths).


=item I<debug>

If set, it will output a lot of debug information.

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

=item B<prepare>

It will create a statement handle (see DBI manpage) suited so that the
caller does not need to explicitly set the "WHERE" clause to reflect
the main table structure and relations, just add the interesting
part. For example, using an already initialized DBIx::Browse object,
you can "prepare" like this:

    my $dbixbr = new DBIx::Browse({
	table         => 'employee',
        proper_fields => 'name',
        linked_fields => ['departament','category']
    })

 (...)

    $my $sth = $dbixbr->prepare({
	where => "departament = 'Adminitstration' AND age < 35",
        order => "name ASC, departament ASC"
	}

instead of:

     $my $sth = $dbh->prepare(
 "SELECT employee.name AS name, 
        departament.name AS departament, 
        category.name AS category
  FROM employee, departament, category
  WHERE departament.id   = employee.departament AND
        category.id      = employee.category    AND
        departament.name = 'Administration'     AND
        employee.age     < 35
  ORDER BY employee.name ASC, departament.name ASC"
			      );

All parameters are passed in a hash reference containig the following
fields (all optional):

=over 4

=item I<where>

The WHERE clause to be I<added> to the query (after the join conditions).

=item I<group>

The "GROUP BY" clause.

=item I<having>

The "HAVING" clause.

=item I<order>

The "ORDER BY" clause.

=item I<limit>

The "LIMIT" clause.

=item I<offset>

The "OFFSET" clause.

=back

The last column will always be the declared primary key for the main
table. The column name will be generated with the B<pkey_name> method.

=item B<pkey_name>

It returns the primary key field name that will be the last field in a
prepared statement.

=item B<count>

It will return the number of rows in a query. The hash reference
parameter is the same than the B<prepare> method.

=item B<insert>

This method inserts a new row into the main table. The input parameter
is a hash reference containing the field names (keys) and values of
the record to be inserted. The field names must correspond to those
declared when calling the B<new> method in the aliases parameter. Not
all the field names and values must be passed as far as the table has
no restriction on the missing fields (like "NOT NULL" or "UNIQUE").

=item B<update>

This method updates rows of the main table. It takes two parmeters:

=over 4

=item I<record>

A hash reference containing the field names as keys with the
corresponding values.

=item I<where>

The "WHERE" clause of the "UPDATE".

=back

=item B<delete>

This method deletes a row in the main table. It takes one parameter
I<pkey>, the value of the primary key of the row to delete. Multiple
deletes are not allowed and should be addressed directly to the DBI
driver.

=item B<field_values>

This method returns an array reference with the list of possible field
values for a given field in the main table. It takes one parameter:

I<field_number>: An index indicating the field number (as declared in
the B<new> method). If the field is a linked field (related to other
table) it will return the values of the related table (as described by
I<linked_table>, and I<linked_values> in the B<new> method).

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

The last three methods will probably be moved to a subclass in the future.

=head1 RESTRICTIONS

The DBI driver to use MUST allow to set I<AutoCommit> to zero.

The syntax construction of queries have only been tested against
PostgreSQL and MySQL.

Not all the clauses are supported by all DBI drivers. In particular,
the "LIMIT" and "OFFSET" ones are non SQL-standard and have been only
tested in PostgresSQL and MySQL (in this later case, no especific
OFFSET clause exists but the DBIx::Browse simulates it by setting
accordingly the "LIMIT" clause).

=head1 AUTHOR

Evilio José del Río Silván, edelrio@icm.csic.es

=head1 SEE ALSO

perl(1), DBI(3), CGI(3).

=cut
