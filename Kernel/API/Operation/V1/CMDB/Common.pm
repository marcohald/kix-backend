# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::API::Operation::V1::CMDB::Common;

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

Kernel::API::Operation::V1::CMDB::Common - Base class for all CMDB operations

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item CheckCreatePermission ()

Tests if the user has the permission to create a CI for a specific class

    my $Result = $CommonObject->CheckCreatePermission(
        ConfigItem => $ConfigItemHashReference,
        UserID     => 123,
        UserType   => 'Agent',
    );

returns:
    $Result = 1                                 # if everything is OK

=cut

sub CheckCreatePermission {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(ConfigItem UserID UserType)) {
        if ( !$Param{$Needed} ) {
            return;
        }
    }

    # check create permissions
    my $Permission = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->Permission(
        Scope   => 'Class',
        ClassID => $Param{ConfigItem}->{ClassID},
        UserID  => $Param{UserID},
        Type    => 'rw',
    );

    return 1;
}

=begin Internal:

=item _CheckConfigItem()

checks if the given config item parameters are valid.

    my $ConfigItemCheck = $OperationObject->_CheckConfigItem(
        ConfigItem => $ConfigItem,                  # all config item parameters
    );

    returns:

    $ConfigItemCheck = {
        Success => 1,                               # if everything is OK
    }

    $ConfigItemCheck = {
        Code    => 'Function.Error',           # if error
        Message => 'Error description',
    }

=cut

sub _CheckConfigItem {
    my ( $Self, %Param ) = @_;

    my $ConfigItem = $Param{ConfigItem};

    my $ConfigObject     = $Kernel::OM->Get('Kernel::Config');
    my $ConfigItemObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');

    # check, whether the feature to check for a unique name is enabled
    if (
        IsStringWithData( $ConfigItem->{Name} )
        && $ConfigObject->Get('UniqueCIName::EnableUniquenessCheck')
    ) {
        my $ConfigItemIDs = $ConfigItemObject->ConfigItemSearchExtended(
            Name           => $ConfigItem->{Name},
            ClassIDs       => [ $ConfigItem->{ClassID} ],
            UsingWildcards => 0,
        );

        my $NameDuplicates = $ConfigItemObject->UniqueNameCheck(
            ConfigItemID => $ConfigItemIDs->[0],
            ClassID      => $ConfigItem->{ClassID},
            Name         => $ConfigItem->{Name},
        );

        # stop processing if the name is not unique
        if ( IsArrayRefWithData($NameDuplicates) ) {
            return $Self->_Error(
                Code    => "BadRequest",
                Message => "The name $ConfigItem->{Name} is already in use by the ConfigItemID(s): $ConfigItemIDs->[0]"
            );
        }
    }

    if ( defined $ConfigItem->{Data} ) {

        if ( !IsHashRefWithData($ConfigItem->{Data}) ) {
            return $Self->_Error(
                Code    => 'BadRequest',
                Message => "Parameter Data is invalid!",
            );            
        }

        # get last config item definition
        my $DefinitionData = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->DefinitionGet(
            ClassID => $ConfigItem->{ClassID},
        );

        my $DataCheckResult = $Self->_CheckConfigItemVersion(
            Definition => $DefinitionData->{DefinitionRef},
            Version    => $ConfigItem->{Version},
        );

        if ( !$DataCheckResult->{Success} ) {
            return $DataCheckResult;
        }
    }

    # if everything is OK then return Success
    return $Self->_Success();
}

=item _CheckConfigItemVersion()

checks if the given version parameters are valid.

    my $VersionCheck = $OperationObject->_CheckConfigItemVersion(
        ConfigItem  => $ConfigItem                          # all ConfigItem parameters
        Version     => $ConfigItemVersion,                  # all Version parameters
    );

    returns:

    $VersionCheck = {
        Success => 1,                               # if everything is OK
    }

    $VersionCheck = {
        Code    => 'Function.Error',           # if error
        Message => 'Error description',
    }

=cut

sub _CheckConfigItemVersion {
    my ( $Self, %Param ) = @_;

    my $ConfigItem = $Param{ConfigItem};
    my $Version    = $Param{Version};

    # get last config item definition
    my $DefinitionData = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->DefinitionGet(
        ClassID => $ConfigItem->{ClassID},
    );

    my $DataCheckResult = $Self->_CheckData(
        Definition => $DefinitionData->{DefinitionRef},
        Data       => $Version->{Data},
    );

    if ( !$DataCheckResult->{Success} ) {
        return $DataCheckResult;
    }

    # if everything is OK then return Success
    return $Self->_Success();
}

=item _CheckData()

checks if the given Data value are valid.

    my $DataCheck = $CommonObject->_CheckData(
        Definition => $DefinitionArrayRef,          # Config Item Definition ot just part of it
        Data       => $DataHashRef,
        Parent     => 'some parent',
    );

    returns:

    $DataCheck = {
        Success => 1,                               # if everything is OK
    }

    $DataCheck = {
        Code    => 'Function.Error',           # if error
        Message => 'Error description',
    }

=cut

sub _CheckData {
    my ( $Self, %Param ) = @_;

    my $Definition = $Param{Definition};
    my $Data       = $Param{Data};
    my $Parent     = $Param{Parent} || '';

    my $CheckValueResult;
    for my $DefItem ( @{$Definition} ) {
        my $ItemKey = $DefItem->{Key};

        # check if at least one element should exist
        if (
            (
                defined $DefItem->{CountMin}
                && $DefItem->{CountMin} >= 1
                && defined $DefItem->{Input}->{Required}
                && $DefItem->{Input}->{Required}
            )
            && ( !defined $Data->{$ItemKey} || !$Data->{$ItemKey} )
            )
        {
            return $Self->_Error(
                Code    => "BadRequest",
                Message => "Parameter Version::Data::$Parent$ItemKey is missing!",
            );
        }

        if ( ref $Data->{$ItemKey} eq 'ARRAY' ) {
            for my $ArrayItem ( @{ $Data->{$ItemKey} } ) {
                if ( ref $ArrayItem eq 'HASH' ) {
                    $CheckValueResult = $Self->_CheckValue(
                        Value   => $ArrayItem->{$ItemKey},
                        Input   => $DefItem->{Input},
                        ItemKey => $ItemKey,
                        Parent  => $Parent,
                    );
                    if ( !$CheckValueResult->{Success} ) {
                        return $CheckValueResult;
                    }
                }
                elsif ( ref $ArrayItem eq '' ) {
                    $CheckValueResult = $Self->_CheckValue(
                        Value   => $ArrayItem,
                        Input   => $DefItem->{Input},
                        ItemKey => $ItemKey,
                        Parent  => $Parent,
                    );
                    if ( !$CheckValueResult->{Success} ) {
                        return $CheckValueResult;
                    }
                }
                else {
                    return $Self->_Error(
                        Code    => "BadRequest",
                        Message => "Parameter Version::Data::$Parent$ItemKey is invalid!",
                    );
                }
            }
        }
        elsif ( ref $Data->{$ItemKey} eq 'HASH' ) {
            $CheckValueResult = $Self->_CheckValue(
                Value   => $Data->{$ItemKey}->{$ItemKey},
                Input   => $DefItem->{Input},
                ItemKey => $ItemKey,
                Parent  => $Parent,
            );
            if ( !$CheckValueResult->{Success} ) {
                return $CheckValueResult;
            }
        }
        else {

            # only perform checks if item really exits in the Data
            # CountNin checks was verified and passed before!, so it is safe to skip if needed
            if ( $Data->{$ItemKey} ) {
                $CheckValueResult = $Self->_CheckValue(
                    Value   => $Data->{$ItemKey},
                    Input   => $DefItem->{Input},
                    ItemKey => $ItemKey,
                    Parent  => $Parent,
                );
                if ( !$CheckValueResult->{Success} ) {
                    return $CheckValueResult;
                }
            }
        }

        # check if exists more elements than the ones they should
        if ( defined $DefItem->{CountMax} )
        {
            if (
                ref $Data->{$ItemKey} eq 'ARRAY'
                && scalar @{ $Data->{$ItemKey} } > $DefItem->{CountMax}
                )
            {
                return $Self->_Error(
                    Code    => "BadRequest",
                    Message => "Parameter Version::Data::$Parent$ItemKey count exceeds allowed maximum!",
                );
            }
        }

        # check if there is a sub and start recursion
        if ( defined $DefItem->{Sub} ) {

            if ( ref $Data->{$ItemKey} eq 'ARRAY' ) {
                my $Counter = 0;
                for my $ArrayItem ( @{ $Data->{$ItemKey} } ) {

                    # start recursion for each array item
                    my $DataCheck = $Self->_CheckData(
                        Definition => $DefItem->{Sub},
                        Data       => $ArrayItem,
                        Parent     => $Parent . $ItemKey . "[$Counter]::",
                    );
                    if ( !$DataCheck->{Success} ) {
                        return $DataCheck;
                    }
                    $Counter++;
                }
            }
            elsif ( ref $Data->{$ItemKey} eq 'HASH' ) {

                # start recursion
                my $DataCheck = $Self->_CheckData(
                    Definition => $DefItem->{Sub},
                    Data       => $Data->{$ItemKey},
                    Parent     => $Parent . $ItemKey . '::',
                );
                if ( !$DataCheck->{Success} ) {
                    return $DataCheck;
                }
            }
            else {
                # start recursion
                my $DataCheck = $Self->_CheckData(
                    Definition => $DefItem->{Sub},
                    Data       => {},
                    Parent     => $Parent . $ItemKey . '::',
                );
                if ( !$DataCheck->{Success} ) {
                    return $DataCheck;
                }
            }
        }
    }

    return $Self->_Success();
}

=item _CheckValue()

checks if the given value is valid.

    my $ValueCheck = $CommonObject->_CheckValue(
        Value   => $Value                        # $Value could be a string, a time stamp,
                                                 #   general catalog class name, or a integer
        Input   => $InputDefinitionHashRef,      # The definition of the element input extracted
                                                 #   from the Configuration Item definition for
                                                 #   for each value
        ItemKey => 'some key',                   # The name of the value as sent in the request
        Parent  => 'soem parent key->',          # The name of the parent followed by -> or empty
                                                 #   for root key items
    );

    returns:

    $ValueCheck = {
        Success => 1,                            # if everything is OK
    }

    $ValueCheck = {
        Code    => 'Function.Error',             # if error
        Message => 'Error description',
    }

=cut

sub _CheckValue {
    my ( $Self, %Param ) = @_;

    my $Parent  = $Param{Parent};
    my $ItemKey = $Param{ItemKey};

    if (
        defined $Param{Input}->{Required} && $Param{Input}->{Required} && !$Param{Value}
        )
    {
        return $Self->_Error(
            Code    => "BadRequest",
            Message => "Parameter Version::Data::$Parent$ItemKey value is required and missing!",
        );
    }

    # check if we have already created an instance of this type
    if ( !$Self->{AttributeTypeModules}->{$Param{Input}->{Type}} ) {
        # create module instance
        my $Module = 'Kernel::System::ITSMConfigItem::XML::Type::'.$Param{Input}->{Type};
        my $Object = $Kernel::OM->Get($Module);

        if (ref $Object ne $Module) {
            return $Self->_Error(
                Code    => "Operation.InternalError",
                Message => "Unable to create instance of attribute type module for parameter Version::Data::$Parent$ItemKey!",
            );
        }
        $Self->{AttributeTypeModules}->{$Param{Input}->{Type}} = $Object;
    }

    # validate value if possible
    if ( $Self->{AttributeTypeModules}->{$Param{Input}->{Type}}->can('ValidateValue') ) {
        my $ValidateResult = $Self->{AttributeTypeModules}->{$Param{Input}->{Type}}->ValidateValue(%Param);

        if ( $ValidateResult != 1 ) {
            return $Self->_Error(
                Code    => "BadRequest",
                Message => "Parameter Version::Data::$Parent$ItemKey has an invalid value ($ValidateResult)!",
            );
        }
    }

    return $Self->_Success();
}

=item ConvertDataToInternal()

Create a Data suitable for VersionAdd.

    my $NewData = $CommonObject->ConvertDataToInternal(
        Data    => $DataHashRef,
        Child      => 1,                    # or 0, optional
    );

    returns:

    $NewData = $DataHashRef,                  # suitable for version add

=cut

sub ConvertDataToInternal {
    my ( $Self, %Param ) = @_;

    my $Data = $Param{Data};
    my $Child   = $Param{Child};

    my $NewData;

    for my $RootKey ( sort keys %{$Data} ) {
        if ( ref $Data->{$RootKey} eq 'ARRAY' ) {
            my @NewXMLParts;
            $NewXMLParts[0] = undef;

            for my $ArrayItem ( @{ $Data->{$RootKey} } ) {
                if ( ref $ArrayItem eq 'HASH' ) {

                    # extract the root key from the hash and assign it to content key
                    my $Content = delete $ArrayItem->{$RootKey};

                    # start recursion
                    my $NewDataPart = $Self->ConvertDataToInternal(
                        Data => $ArrayItem,
                        Child   => 1,
                    );
                    push @NewXMLParts, {
                        Content => $Content,
                        %{$NewDataPart},
                    };
                }
                elsif ( ref $ArrayItem eq '' ) {
                    push @NewXMLParts, {
                        Content => $ArrayItem,
                    };
                }
            }

            # assamble the final value from the parts array
            $NewData->{$RootKey} = \@NewXMLParts;
        }

        if ( ref $Data->{$RootKey} eq 'HASH' ) {

            my @NewXMLParts;
            $NewXMLParts[0] = undef;

            # extract the root key from the hash and assign it to content key
            my $Content = delete $Data->{$RootKey}->{$RootKey};

            # start recursion
            my $NewDataPart = $Self->ConvertDataToInternal(
                Data => $Data->{$RootKey},
                Child   => 1,
            );
            push @NewXMLParts, {
                Content => $Content,
                %{$NewDataPart},
            };

            # assamble the final value from the parts array
            $NewData->{$RootKey} = \@NewXMLParts;
        }

        elsif ( ref $Data->{$RootKey} eq '' ) {
            $NewData->{$RootKey} = [
                undef,
                {
                    Content => $Data->{$RootKey},
                }
                ],
        }
    }

    # return only the part on recursion
    if ($Child) {
        return $NewData;
    }

    # return the complete Data as needed for version add
    return [
        undef,
        {
            Version => [
                undef,
                $NewData
            ],
        },
    ];
}

=item ConvertDataToExternal()

Creates a readible Data.

    my $NewData = $CommonObject->ConvertDataToExternal(
        Definition => $DefinitionHashRef,
        Data       => $DataHashRef,
    );

    returns:

    $NewData = $DataHashRef,                  # suitable for display

=cut

sub ConvertDataToExternal {
    my ( $Self, %Param ) = @_;

    my $Data = $Param{Data};

    my $NewData;
    my $Content;
    ROOTHASH:
    for my $RootHash ( @{$Data} ) {
        next ROOTHASH if !defined $RootHash;
        delete $RootHash->{TagKey};

        for my $RootHashKey ( sort keys %{$RootHash} ) {

            # get attribute definition 
            my $AttrDef = $Self->_GetAttributeDefByKey(
                Key        => $RootHashKey,
                Definition => $Param{Definition},
            );

            if ( $AttrDef->{CountMax} > 1 ) {

                # we have multiple items
                my $Counter = 0;
                ARRAYITEM:
                for my $ArrayItem ( @{ $RootHash->{$RootHashKey} } ) {
                    next ARRAYITEM if !defined $ArrayItem;
    
                    delete $ArrayItem->{TagKey};

                    $Content = delete $ArrayItem->{Content} || '';

                    # look if we have a sub structure
                    if ( $AttrDef->{Sub} ) {
                        $NewData->{$RootHashKey}->[$Counter]->{$RootHashKey} = $Content;

                        # start recursion
                        for my $ArrayItemKey ( sort keys %{$ArrayItem} ) {

                            my $NewDataPart = $Self->ConvertDataToExternal(
                                Definition => $Param{Definition},
                                Data       => [ undef, { $ArrayItemKey => $ArrayItem->{$ArrayItemKey} } ],
                                RootKey    => $RootHashKey,
                            );
                            for my $Key ( sort keys %{$NewDataPart} ) {
                                $NewData->{$RootHashKey}->[$Counter]->{$Key} = $NewDataPart->{$Key};
                            }
                        }
                    }
                    else {
                        $NewData->{$RootHashKey}->[$Counter] = $Content;
                    }

                    $Counter++;
                }
            }
            else {
                # we've got a single item

                ARRAYITEM:
                for my $ArrayItem ( @{ $RootHash->{$RootHashKey} } ) {
                    next ARRAYITEM if !defined $ArrayItem;

                    delete $ArrayItem->{TagKey};

                    $Content = delete $ArrayItem->{Content} || '';

                    $NewData->{$RootHashKey} = $Content;

                    # look if we have a sub structure
                    if ( $AttrDef->{Sub} ) {
                        # start recursion
                        for my $ArrayItemKey ( sort keys %{$ArrayItem} ) {

                            my $NewDataPart = $Self->ConvertDataToExternal(
                                Definition => $Param{Definition},
                                Data       => [ undef, { $ArrayItemKey => $ArrayItem->{$ArrayItemKey} } ],
                                RootKey    => $RootHashKey,
                            );
                            $NewData->{$RootHashKey}->{$ArrayItemKey} = $NewDataPart;
                        }
                    }
                }
            }
            # # if we are on a final node
            # elsif ( !$Param{RootKey} && ref $RootHash->{$RootHashKey} eq '' && $RootHashKey eq 'Content' ) {
            #     $NewData = $RootHash->{$RootHashKey};
            # }
        }
    }

    return $NewData;
}

sub _GetAttributeDefByKey {
    my ( $Self, %Param ) = @_;

    # check required params...
    return
        if (
        !$Param{Definition} || ref( $Param{Definition} ) ne 'ARRAY' ||
        !$Param{Key}
        );

    ITEM:
    for my $Item ( @{ $Param{Definition} } ) {

        if ( $Item->{Key} eq $Param{Key} ) {
            return $Item;
        }

        next ITEM if ( !$Item->{Sub} );

        # recurse if subsection available...
        my $SubResult = $Self->_GetAttributeDefByKey(
            Key        => $Param{Key},
            Definition => $Item->{Sub},
        );

        if ( $SubResult && ref($SubResult) eq 'HASH' ) {
            return $SubResult;
        }
    }

    return;
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