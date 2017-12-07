# --
# Kernel/API/Operation/SystemAddress/SystemAddressCreate.pm - API SystemAddress Create operation backend
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

package Kernel::API::Operation::V1::SystemAddress::SystemAddressCreate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsString IsStringWithData);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::SystemAddress::SystemAddressCreate - API SystemAddress SystemAddressCreate Operation backend

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

=item Run()

perform SystemAddressCreate Operation. This will return the created SystemAddressID.

    my $Result = $OperationObject->Run(
        Data => {
            SystemAddress  => {
                Name     => 'info@example.com',
                Realname => 'Hotline',
                ValidID  => 1,
                Comment  => 'some comment',
            },
	    },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        Code            => '',                      # 
        Message         => '',                      # in case of error
        Data            => {                        # result data payload after Operation
            SystemAddressID  => '',                         # ID of the created SystemAddress
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # init webSystemAddress
    my $Result = $Self->Init(
        WebserviceID => $Self->{WebserviceID},
    );

    if ( !$Result->{Success} ) {
        $Self->_Error(
            Code    => 'WebService.InvalidConfiguration',
            Message => $Result->{Message},
        );
    }

    # prepare data
    $Result = $Self->PrepareData(
        Data       => $Param{Data},
        Parameters => {
            'SystemAddress' => {
                Type     => 'HASH',
                Required => 1
            },
            'SystemAddress::Name' => {
                Required => 1
            },
            'SystemAddress::Realname' => {
                Required => 1
            },                           
        }
    );

    # check result
    if ( !$Result->{Success} ) {
        return $Self->_Error(
            Code    => 'Operation.PrepareDataError',
            Message => $Result->{Message},
        );
    }

    # isolate SystemAddress parameter
    my $SystemAddress = $Param{Data}->{SystemAddress};

    # remove leading and trailing spaces
    for my $Attribute ( sort keys %{$SystemAddress} ) {
        if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

            #remove leading spaces
            $SystemAddress->{$Attribute} =~ s{\A\s+}{};

            #remove trailing spaces
            $SystemAddress->{$Attribute} =~ s{\s+\z}{};
        }
    }   
    	
    # check if SystemAddress exists
    my $Exists = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressLookup(
        Name => $SystemAddress->{Name},
    );

    if ( $Exists ) {
        return $Self->_Error(
            Code    => 'Object.AlreadyExists',
            Message => "Can not create SystemAddress. SystemAddress with same name '$SystemAddress->{Name}' already exists.",
        );
    }

    # create SystemAddress
    my $SystemAddressID = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressAdd(
        Name     => $SystemAddress->{Name},
        Comment  => $SystemAddress->{Comment} || '',
        ValidID  => $SystemAddress->{ValidID} || 1,
        Realname => $SystemAddress->{Realname},
        UserID   => $Self->{Authorization}->{UserID},              
    );

    if ( !$SystemAddressID ) {
        return $Self->_Error(
            Code    => 'Object.UnableToCreate',
            Message => 'Could not create SystemAddress, please contact the system administrator',
        );
    }
    
    # return result    
    return $Self->_Success(
        Code   => 'Object.Created',
        SystemAddressID => $SystemAddressID,
    );    
}


1;