# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::API::Operation::V1::CMDB::ClassDefinitionCreate;

use strict;
use warnings;

use MIME::Base64;

use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsStringWithData);

use base qw(
    Kernel::API::Operation::V1::CMDB::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::CMDB::ClassDefinitionCreate - API ClassDefinitionCreate Operation backend

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

    # get valid ClassIDs
    my $ItemList = $Kernel::OM->Get('Kernel::System::GeneralCatalog')->ItemList(
        Class => 'ITSM::ConfigItem::Class',
        Valid => 1,
    );

    my @ClassIDs = sort keys %{$ItemList};

    return {
        'ClassID' => {
            Required => 1,
            OneOf    => \@ClassIDs,            
        },       
        'ConfigItemClassDefinition' => {
            Type     => 'HASH',
            Required => 1,
        },
        'ConfigItemClassDefinition::DefinitionString' => {
            Required => 1,
        }, 
    }
}

=item Run()

perform ClassDefinitionCreate Operation.

    my $Result = $OperationObject->ClassDefinitionCreate(
        ClassID = 123,
        Data => {
            ...
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        Code            => '',                      # 
        Message         => '',                      # in case of error
        Data            => {                        # result data payload after Operation
            ConfigItemClassDefinitionID  => '',     # ConfigItemClassDefinitionID 
        },
    };


=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # isolate and trim ConfigItemClassDefinition parameter
    my $Definition = $Self->_Trim(
        Data => $Param{Data}->{ConfigItemClassDefinition}
    );

    my $DefinitionCheck = $Self->_CheckDefinition(
        ClassID    => $Param{Data}->{ClassID},
        Definition => $Definition->{DefinitionString},
    );

    if ( !$DefinitionCheck->{Success} ) {
        return $Self->_Error(
            %{$DefinitionCheck},
        );
    }

    my $ConfigItemClassDefinitionID = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->DefinitionAdd(
        ClassID    => $Param{Data}->{ClassID},
        Definition => $Definition->{DefinitionString},
        UserID     => $Self->{Authorization}->{UserID},
    );

    if ( !$ConfigItemClassDefinitionID ) {
        return $Self->_Error(
            Code    => 'Object.UnableToCreate',
            Message => "Definition could not be created, please contact the system administrator.",
        );
    }

    return $Self->_Success(
        Code                        => 'Object.Created',
        ConfigItemClassDefinitionID => $ConfigItemClassDefinitionID,
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