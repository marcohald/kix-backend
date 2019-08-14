# --
# Kernel/API/Operation/SysConfig/SysConfigCreate.pm - API SysConfig Create operation backend
# Copyright (C) 2006-2016 c.a.p.e. IT GmbH, http://www.cape-it.de
#
# written/edited by:
# * Rene(dot)Boehm(at)cape(dash)it(dot)de
# 
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::API::Operation::V1::SysConfig::SysConfigOptionSearch;

use strict;
use warnings;

use Kernel::API::Operation::V1::SysConfig::SysConfigOptionGet;
use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::SysConfig::SysConfigOptionSearch - API SysConfig Search Operation backend

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

perform SysConfigOptionSearch Operation. This will return a SysConfig item list with data.

    my $Result = $OperationObject->Run(
        Data => {
        }
    );

    $Result = {
        Success => 1,                                # 0 or 1
        Code    => '',                          # In case of an error
        Message => '',                          # In case of an error
        Data    => {
            SysConfigOption => [
                {},
                {}
            ]
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # perform SysConfig search
    my %AllOptions = $Kernel::OM->Get('Kernel::System::SysConfig')->ValueGetAll();

	# get already prepared SysConfig data from SysConfigGet operation
    if ( IsHashRefWithData(\%AllOptions) ) {  	
        my $SysConfigGetResult = $Self->ExecOperation(
            OperationType => 'V1::SysConfig::SysConfigOptionGet',
            Data      => {
                Option  => join(',', sort keys %AllOptions),
                include => $Param{Data}->{include},
            }
        );    

        if ( !IsHashRefWithData($SysConfigGetResult) || !$SysConfigGetResult->{Success} ) {
            return $SysConfigGetResult;
        }

        my @SysConfigDataList = IsArrayRefWithData($SysConfigGetResult->{Data}->{SysConfigOption}) ? @{$SysConfigGetResult->{Data}->{SysConfigOption}} : ( $SysConfigGetResult->{Data}->{SysConfigOption} );

        if ( IsArrayRefWithData(\@SysConfigDataList) ) {
            return $Self->_Success(
                SysConfigOption => \@SysConfigDataList,
            )
        }
    }

    # return result
    return $Self->_Success(
        SysConfigOption => [],
    );
}

1;