# --
# Copyright (C) 2006-2019 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::API::Operation::V1::SLA::SLADelete;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::SLA::SLADelete - API SLA SLADelete Operation backend

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

usually, you want to create an instance of this
by using Kernel::API::Operation->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw( DebuggerObject WebserviceID )) {
        if ( !$Param{$Needed} ) {
            return $Self->_Error(
                Code    => 'Operation.InternalError',
                Message => "Got no $Needed!"
            );
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    return $Self;
}

=item ParameterDefinition()

define parameter preparation and check for this operation

    my $Result = $OperationObject->ParameterDefinition(
        Data => {
            ...
        },
    );

    $Result = {
        ...
    };

=cut

sub ParameterDefinition {
    my ( $Self, %Param ) = @_;

    return {
        'SLAID' => {
            DataType => 'NUMERIC',
            Type     => 'ARRAY',
            Required => 1
        },
    }
}

=item Run()

perform SLADelete Operation. This will return the deleted SLAID.

    my $Result = $OperationObject->Run(
        Data => {
            SLAID  => '...',
        },		
    );

    $Result = {
        Message    => '',                      # in case of error
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;
      
    # start loop
    foreach my $SLAID ( @{$Param{Data}->{SLAID}} ) {

        my $ResultTicketSearch = $Kernel::OM->Get('Kernel::System::Ticket')->TicketSearch(        
            Result       => 'COUNT',
            Limit        => 1,
            Search       => {
                AND => [ 
                    {
                        Field => 'SLAID',
                        Value => $SLAID,
                        Operator => 'EQ',
                    },
                ]
            },
            UserID      => 1,
            Permission  => 'ro',         
        );
        
        if ( $ResultTicketSearch ) {
            return $Self->_Error(
                Code    => 'Object.DependingObjectExists',
                Message => 'Cannot delete SLA. A ticket with this SLA already exists.',
            );
        }
      
        # delete SLA	    
        my $Success = $Kernel::OM->Get('Kernel::System::SLA')->SLADelete(
            SLAID  => $SLAID,
            UserID  => $Self->{Authorization}->{UserID},
        );
 
        if ( !$Success ) {
            return $Self->_Error(
                Code    => 'Object.UnableToDelete',
                Message => 'Could not delete SLA, please contact the system administrator',
            );
        }
    }

    # return result
    return $Self->_Success();
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-GPL3 for license information (GPL3). If you did not receive this file, see

<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut
