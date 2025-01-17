# --
# Modified version of the work: Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-AGPL for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Automation::MacroAction::Common::Loop;

use strict;
use warnings;
use utf8;

use Kernel::System::VariableCheck qw(:all);

use base qw(Kernel::System::Automation::MacroAction::Common);

our @ObjectDependencies = (
    'Log',
);

=head1 NAME

Kernel::System::Automation::MacroAction::Common::Loop - A module to loop over given values

=head1 SYNOPSIS

All Loop functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item Describe()

Describe this macro action module.

=cut

sub Describe {
    my ( $Self, %Param ) = @_;

    $Self->Description(Kernel::Language::Translatable('Execute a loop over each of the given values. Each value will be the new ObjectID for the depending macro.'));
    $Self->AddOption(
        Name        => 'Values',
        Label       => Kernel::Language::Translatable('Values'),
        Description => Kernel::Language::Translatable('A list of values to go through. Either a comma separated list or an array generated by a placeholder.'),
        Required    => 1,
    );
    $Self->AddOption(
        Name        => 'LoopVariable',
        Label       => Kernel::Language::Translatable('Loop Variable'),
        Description => Kernel::Language::Translatable('The value (ObjectID) of the current loop iteration in case it is needed. It can be used like any result variable in a macro.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'MacroID',
        Label       => Kernel::Language::Translatable('MacroID'),
        Description => Kernel::Language::Translatable('The ID of the macro to execute for each value.'),
        Required    => 1,
    );

    return;
}

=item Run()

Run this module. Returns 1 if everything is ok.

Example:
    my $Success = $Object->Run(
        ObjectID => 123,
        Config   => {
            Values  => '1,2,3,4,5',
            MacroID => 123,
        },
        UserID   => 123,
    );

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # check incoming parameters
    return if !$Self->_CheckParams(%Param);

    my $Values = $Kernel::OM->Get('TemplateGenerator')->ReplacePlaceHolder(
        RichText  => 0,
        Text      => $Param{Config}->{Values},
        Data      => {},
        UserID    => $Param{UserID},
        Translate => 0,

        # FIXME: as common action, object id could be not a ticket!
        TicketID  => $Self->{RootObjectID} || $Param{ObjectID}
    );

    my @ValueList;
    if ( IsArrayRefWithData($Values) ) {
        @ValueList = @{$Values};
    }
    else {
        @ValueList = split('\s*,\s*', $Values);
    }

    # FIXME: use given instance
    my $AutomationObject = $Param{AutomationInstance} || $Kernel::OM->Get('Automation');

    foreach my $Value ( @ValueList ) {
        if ( $Param{Config}->{LoopVariable} ) {
            $Self->SetResult(Name => $Param{Config}->{LoopVariable}, Value => $Value);
        }

        my $Result = $AutomationObject->MacroExecute(
            ID       => $Param{Config}->{MacroID},
            ObjectID => $Value,
            UserID   => $Param{UserID},

            # keep (or overwrite) root object id
            RootObjectID => $Self->{RootObjectID} || $Param{ObjectID}
        );
    }

    return 1;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-AGPL for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
