# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::API::Operation::V1::TextModule::TextModuleSearch;

use strict;
use warnings;

use Kernel::API::Operation::V1::TextModule::TextModuleGet;
use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::TextModule::TextModuleSearch - API TextModule Search Operation backend

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
    for my $Needed (qw(DebuggerObject WebserviceID)) {
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

=item Run()

perform TextModuleSearch Operation. This will return a TextModule ID list.

    my $Result = $OperationObject->Run(
        Data => {
        }
    );

    $Result = {
        Success => 1,                                # 0 or 1
        Code    => '',                          # In case of an error
        Message => '',                          # In case of an error
        Data    => {
            TextModule => [
                {},
                {}
            ]
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # prepare search if given
    my %SearchParam;
    if ( IsArrayRefWithData($Self->{Search}->{TextModule}->{AND}) && !defined $Self->{Search}->{TextModule}->{OR} ) {
        foreach my $SearchItem ( @{$Self->{Search}->{TextModule}->{AND}} ) {
            # ignore everything that we don't support in the core DB search (the rest will be done in the generic API Searching)
            next if ($SearchItem->{Field} !~ /^(Name|Category|Language|ValidID)$/g);
            next if ($SearchItem->{Operator} ne 'EQ');

            $SearchParam{$SearchItem->{Field}} = $SearchItem->{Value};
        }
    }

    # perform TextModule search
    my $TextModuleList = $Kernel::OM->Get('TextModule')->TextModuleList(
        %SearchParam
    );

	# get already prepared TextModule data from TextModuleGet operation
    if ( IsArrayRefWithData($TextModuleList) ) {  	
        my $TextModuleGetResult = $Self->ExecOperation(
            OperationType            => 'V1::TextModule::TextModuleGet',
            SuppressPermissionErrors => 1,
            Data      => {
                TextModuleID => join(',', @{$TextModuleList}),
            }
        );    

        if ( !IsHashRefWithData($TextModuleGetResult) || !$TextModuleGetResult->{Success} ) {
            return $TextModuleGetResult;
        }

        my @TextModuleDataList = IsArrayRef($TextModuleGetResult->{Data}->{TextModule}) ? @{$TextModuleGetResult->{Data}->{TextModule}} : ( $TextModuleGetResult->{Data}->{TextModule} );

        if ( IsArrayRefWithData(\@TextModuleDataList) ) {
            return $Self->_Success(
                TextModule => \@TextModuleDataList,
            )
        }
    }

    # return result
    return $Self->_Success(
        TextModule => [],
    );
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
