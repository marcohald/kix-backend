# --
# Kernel/API/Operation/TextModule/TextModuleUpdate.pm - API TextModule Update operation backend
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

package Kernel::API::Operation::V1::TextModule::TextModuleUpdate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsStringWithData);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::TextModule::TextModuleUpdate - API TextModule Create Operation backend

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

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('API::Operation::V1::TextModuleUpdate');

    return $Self;
}

=item Run()

perform TextModuleUpdate Operation. This will return the updated TypeID.

    my $Result = $OperationObject->Run(
        Data => {
            TextModuleID => 123,
            TextModule  => {
                Name                => '...',       # optional
                Text                => '...',       # optional
                Language            => '...',       # optional
                Category            => '...',       # optional
                Comment             => '...',       # optional
                Keywords            => '...',       # optional
                Subject             => '...',       # optional
                AgentFrontend       => 0|1,         # optional
                CustomerFrontend    => 0|1,         # optional
                PublicFrontend      => 0|1,         # optional
                ValidID             => 1            # optional
            },
        },
    );

    $Result = {
        Success     => 1,                       # 0 or 1
        Code        => '',                      # in case of error
        Message     => '',                      # in case of error
        Data        => {                        # result data payload after Operation
            TextModuleID  => 123,              # ID of the updated TextModule 
        },
    };
   
=cut


sub Run {
    my ( $Self, %Param ) = @_;

    # init webTextModule
    my $Result = $Self->Init(
        WebserviceID => $Self->{WebserviceID},
    );

    if ( !$Result->{Success} ) {
        $Self->_Error(
            Code    => 'WebService.InvalidConfiguration',
            Message => $Result->{Message},
        );
    }

    # get system LanguageIDs
    my $Languages = $Kernel::OM->Get('Kernel::Config')->Get('DefaultUsedLanguages');
    my @LanguageIDs = sort keys %{$Languages};

    # prepare data
    $Result = $Self->PrepareData(
        Data         => $Param{Data},
        Parameters   => {
            'TextModuleID' => {
                Required => 1
            },
            'TextModule' => {
                Type     => 'HASH',
                Required => 1
            },
            'TextModule::Language' => {
                RequiresValueIfUsed => 1,
                OneOf => \@LanguageIDs
            },
            'TextModule::AgentFrontend' => {
                RequiresValueIfUsed => 1,
                OneOf    => [
                    0,
                    1
                ]
            },
            'TextModule::CustomerFrontend' => {
                RequiresValueIfUsed => 1,
                OneOf    => [
                    0,
                    1
                ]
            },
            'TextModule::PublicFrontend' => {
                RequiresValueIfUsed => 1,
                OneOf    => [
                    0,
                    1
                ]
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

    # isolate and trim TextModule parameter
    my $TextModule = $Self->_Trim(
        Data => $Param{Data}->{TextModule}
    );
    
    # check if TextModule exists 
    my %TextModuleData = $Kernel::OM->Get('Kernel::System::TextModule')->TextModuleGet(
        ID     => $Param{Data}->{TextModuleID},
        UserID => $Self->{Authorization}->{UserID},
    );
 
    if ( !%TextModuleData ) {
        return $Self->_Error(
            Code    => 'Object.NotFound',
            Message => "Cannot update TextModule. No TextModule with ID '$Param{Data}->{TextModuleID}' found.",
        );
    }

    if ( $TextModule->{Name} ) {
        # check if TextModule exists
        my $ExistingProfileIDs = $Kernel::OM->Get('Kernel::System::TextModule')->TextModuleList(
            Name        => $TextModule->{Name},
        );
        
        if ( IsArrayRefWithData($ExistingProfileIDs) && $ExistingProfileIDs->[0] != $TextModuleData{ID}) {
            return $Self->_Error(
                Code    => 'Object.AlreadyExists',
                Message => "Cannot update TextModule. Another TextModule with the same name already exists.",
            );
        }
    }

    # update TextModule
    my $Success = $Kernel::OM->Get('Kernel::System::TextModule')->TextModuleUpdate(
        ID                 => $Param{Data}->{TextModuleID},
        Name               => $TextModule->{Name} || $TextModuleData{Name},
        Text               => $TextModule->{Text} || $TextModuleData{Text},
        Category           => $TextModule->{Category} || $TextModuleData{Category},
        Language           => $TextModule->{Language} || $TextModuleData{Language},
        Subject            => $TextModule->{Subject} || $TextModuleData{Subject},
        Keywords           => $TextModule->{Keywords} || $TextModuleData{Keywords},
        Comment            => $TextModule->{Comment} || $TextModuleData{Comment},
        AgentFrontend      => $TextModule->{AgentFrontend} || $TextModuleData{AgentFrontend},
        CustomerFrontend   => $TextModule->{CustomerFrontend} || $TextModuleData{CustomerFrontend},
        PublicFrontend     => $TextModule->{PublicFrontend} || $TextModuleData{PublicFrontend},        
        ValidID            => $TextModule->{ValidID} || $TextModuleData{ValidID},        
        UserID             => $Self->{Authorization}->{UserID},
    );

    if ( !$Success ) {
        return $Self->_Error(
            Code    => 'Object.UnableToUpdate',
            Message => 'Could not update TextModule, please contact the system administrator',
        );
    }

    # return result    
    return $Self->_Success(
        TextModuleID => $Param{Data}->{TextModuleID},
    );    
}

1;