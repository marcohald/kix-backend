# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::API::Operation::V1::Ticket::WatcherCreate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw( :all );

use base qw(
    Kernel::API::Operation::V1::Ticket::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::Ticket::WatcherCreate - API WatcherCreate Operation backend

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

usually, you want to create an instance of this
by using Kernel::API::Operation::V1->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw( DebuggerObject WebserviceID )) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('API::Operation::V1::TicketWatcherCreate');

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
        'TicketID' => {
            Required => 1
        },
        'Watcher::UserID' => {
            Required => 1
        },
    }
}

=item Run()

perform WatcherCreate Operation. This will return the created WatcherItemID

    my $Result = $OperationObject->Run(
        Data => {
            TicketID  => 123,                                  # required
            Watcher => {                                       # required
                UserID => 123,                                 # required
            },
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        Code            => '',                      #
        Message         => '',                      # in case of error
        Data            => {                        # result data payload after Operation
            WatcherID => 1
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # check write permission
    my $Permission = $Self->CheckWritePermission(
        TicketID => $Param{Data}->{TicketID},
        UserID   => $Self->{Authorization}->{UserID},
        UserType => $Self->{Authorization}->{UserType},
    );

    if ( !$Permission ) {
        return $Self->_Error(
            Code    => 'Object.NoPermission',
            Message => "No permission to add Watchers!",
        );
    }

    # isolate and trim WatcherItem parameter
    my $Watcher = $Self->_Trim(
        Data => $Param{Data}->{Watcher},
    );

    # check if Watcher exists
    my %Watchers = $Kernel::OM->Get('Kernel::System::Ticket')->TicketWatchGet(
        TicketID => $Param{Data}->{TicketID},
    );
    
    if ( $Watchers{$Watcher->{UserID}} ) {
        return $Self->_Error(
            Code    => 'Object.AlreadyExists',
            Message => "Can not create Watcher. Watcher already exists.",
        );
    }
    
    my $Success = $Kernel::OM->Get('Kernel::System::Ticket')->TicketWatchSubscribe(
        TicketID    => $Param{Data}->{TicketID},
        WatchUserID => $Watcher->{UserID},
        UserID      => $Self->{Authorization}->{UserID},
    );

    if ( !$Success ) {
        return $Self->_Error(
            Code    => 'Object.UnableToCreate',
            Message => 'Could not create Watcher, please contact the system administrator',
        );
    }

    return $Self->_Success(
        Code      => 'Object.Created',
        WatcherID => $Watcher->{UserID},
    );
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