# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::API::Operation::V1::Notification::Common;

use strict;
use warnings;

use MIME::Base64();
use Mail::Address;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::Notification::Common - Base class for all Notification Operations

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=begin Internal:

=item _CheckNotification()

checks if the given Notification parameter is valid.

    my $Result = $OperationObject->_CheckNotification(
        Notification => $Notification,
    );

    returns:

    $Result = {
        Success => 1,                               # if everything is OK
    }

    $Result = {
        Code    => 'Function.Error',           # if error
        Message => 'Error description',
    }

=cut

sub _CheckNotification {
    my ( $Self, %Param ) = @_;

    my $Notification = $Param{Notification};

    if ( exists $Notification->{Data} && IsHashRefWithData($Notification->{Data}) ) {
        # validate Data attribute
        foreach my $Key ( sort keys %{ $Notification->{Data} } ) {

            # error if message data is incomplete
            if ( !IsArrayRefWithData($Notification->{Data}->{$Key}) ) {
                return $Self->_Error( 
                    Code    => 'BadRequest',
                    Message => "Parameter $Key is invalid!"
                );
            }
        }
    }

    if ( exists $Notification->{Message} && IsHashRefWithData($Notification->{Message}) ) {
        # validate Message attribute
        foreach my $Language ( sort keys %{ $Notification->{Message} } ) {

            # error if Language is not a valid hash
            if ( !IsHashRefWithData($Notification->{Message}->{$Language}) ) {
                return $Self->_Error( 
                    Code    => 'BadRequest',
                    Message => "Parameter Message::$Language is invalid!"
                );
            }

            foreach my $Parameter (qw(Subject Body ContentType)) {
                # error if message data is incomplete
                if ( !$Notification->{Message}->{$Language}->{$Parameter} ) {
                    return $Self->_Error( 
                        Code    => 'BadRequest',
                        Message => "Required parameter Message::$Language::$Parameter is missing or undefined!"
                    );
                }
            }
        }
    }

    # if everything is OK then return Success
    return $Self->_Success();
}

1;

=end Internal:




=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<http://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
COPYING for license information (AGPL). If you did not receive this file, see

<http://www.gnu.org/licenses/agpl.txt>.

=cut