# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::API::Operation::V1::CMDB::ClassDefinitionGet;

use strict;
use warnings;

use MIME::Base64;

use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsStringWithData);

use base qw(
    Kernel::API::Operation::V1::CMDB::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::CMDB::ClassDefinitionGet - API ClassDefinitionGet Operation backend

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
    for my $Needed (qw(DebuggerObject WebserviceID)) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!",
            };
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
        'ClassID' => {
            DataType => 'NUMERIC',
            Required => 1
        },
        'DefinitionID' => {
            Type     => 'ARRAY',
            DataType => 'NUMERIC',
            Required => 1
        },
    }
}

=item Run()

perform ClassDefinitionGet Operation.

    my $Result = $OperationObject->Run(
        ClassID      => 1,                                # required 
        DefinitionID => 1                                 # required
    );

    $Result = {
        Success      => 1,                                # 0 or 1
        Code         => '',                               # In case of an error
        Message      => '',                               # In case of an error
        Data         => {
            ConfigItemClassDefinition => [
                {
                    ...
                },
            ]
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my @DefinitionList;        
    foreach my $DefinitionID ( @{$Param{Data}->{DefinitionID}} ) {                 

        my $Definition = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->DefinitionGet(
            DefinitionID => $DefinitionID,
        );

        if (!IsHashRefWithData($Definition) || $Definition->{ClassID} != $Param{Data}->{ClassID}) {
            return $Self->_Error(
                Code    => 'Object.NotFound',
                Message => "Could not get data for DefinitionID $DefinitionID in ClassID $Param{Data}->{ClassID}",
            );
        }     

        # rename DefinitionRef to Definition and remove DefinitionRef attribute
        $Definition->{Definition} = $Definition->{DefinitionRef};
        delete $Definition->{DefinitionRef};

        push(@DefinitionList, $Definition);
    }

    if ( scalar(@DefinitionList) == 0 ) {
        return $Self->_Error(
            Code    => 'Object.NotFound',
            Message => "Could not get data for DefinitionID ".join(',', $Param{Data}->{DefinitionID}),
        );
    }
    elsif ( scalar(@DefinitionList) == 1 ) {
        return $Self->_Success(
            ConfigItemClassDefinition => $DefinitionList[0],
        );    
    }

    return $Self->_Success(
        ConfigItemClassDefinition => \@DefinitionList,
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