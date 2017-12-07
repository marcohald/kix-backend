# --
# Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::TicketSearch::Database::Priority;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::System::Ticket::TicketSearch::Database::Common
);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
);

=head1 NAME

Kernel::System::Ticket::TicketSearch::Database::Priority - attribute module for database ticket search

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item GetSupportedAttributes()

defines the list of attributes this module is supporting

    my $AttributeList = $Object->GetSupportedAttributes();

    $Result = {
        Filter => [ ],
        Sort   => [ ],
    };

=cut

sub GetSupportedAttributes {
    my ( $Self, %Param ) = @_;

    return {
        Filter => [
            'Priority',
            'PriorityID' 
        ],
        Sort   => [ 
            'PriorityID' 
        ],
    };
}


=item Filter()

run this module and return the SQL extensions

    my $Result = $Object->Filter(
        Filter => {}
    );

    $Result = {
        SQLWhere   => [ ],
    };

=cut

sub Filter {
    my ( $Self, %Param ) = @_;
    my @SQLWhere;

    # check params
    if ( !$Param{Filter} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need Filter!",
        );
        return;
    }

    my @PriorityIDs;
    if ( $Param{Filter}->{Field} eq 'Priority' ) {
        my @PriorityList = ( $Param{Filter}->{Value} );
        if ( IsArrayRefWithData($Param{Filter}->{Value}) ) {
            @PriorityList = @{$Param{Filter}->{Value}}
        }
        foreach my $Priority ( @PriorityList ) {
            my $PriorityID = $Kernel::OM->Get('Kernel::System::Priority')->PriorityLookup(
                Priority => $Priority,
            );
            if ( !$PriorityID ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "Unknown priority $Priority!",
                );
                return;
            }                

            push( @PriorityIDs, $PriorityID );
        }
    }
    else {
        @PriorityIDs = ( $Param{Filter}->{Value} );
        if ( IsArrayRefWithData($Param{Filter}->{Value}) ) {
            @PriorityIDs = @{$Param{Filter}->{Value}}
        }
    }

    if ( $Param{Filter}->{Operator} eq 'EQ' ) {
        push( @SQLWhere, 'st.ticket_priority_id = '.$PriorityIDs[0] );
    }
    elsif ( $Param{Filter}->{Operator} eq 'IN' ) {
        push( @SQLWhere, 'st.ticket_priority_id IN ('.(join(',', @PriorityIDs)).')' );
    }
    else {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Unsupported Operator $Param{Filter}->{Operator}!",
        );
        return;
    }

    return {
        SQLWhere => \@SQLWhere,
    };        
}

=item Sort()

run this module and return the SQL extensions

    my $Result = $Object->Sort(
        Attribute => '...'      # required
    );

    $Result = {
        SQLAttrs   => [ ],          # optional
        SQLOrderBy => [ ]           # optional
    };

=cut

sub Sort {
    my ( $Self, %Param ) = @_;

    return {
        SQLAttrs => [
            'st.ticket_priority_id'
        ],
        SQLOrderBy => [
            'st.ticket_priority_id'
        ],
    };       
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<http://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
COPYING for license information (AGPL). If you did not receive this file, see

<http://www.gnu.org/licenses/agpl.txt>.

=cut