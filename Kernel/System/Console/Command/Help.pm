# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console::Command::Help;

use strict;
use warnings;

use base qw(
    Kernel::System::Console::BaseCommand
    Kernel::System::Console::Command::Search
);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Main',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Displays help for an existing command or search for commands.');
    $Self->AddArgument(
        Name => 'command',
        Description =>
            "Print usage information for this command (if command is available) or search for commands with similar names.",
        ValueRegex => qr/[a-zA-Z0-9:_]+/,
        Required   => 1,
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $SearchCommand = $Self->GetArgument('command');
    my $CommandModule = "Kernel::System::Console::Command::$SearchCommand";

    # Is it an existing command? Then show help for it.
    if ( $Kernel::OM->Get('Kernel::System::Main')->Require( $CommandModule, Silent => 1 ) ) {
        my $Command = $Kernel::OM->Get($CommandModule);
        $Command->ANSI( $Self->ANSI() );
        print $Command->GetUsageHelp();
        return $Self->ExitCodeOk();
    }

    # Otherwise, search for commands with a similar name
    return $Self->HandleSearch( SearchCommand => $SearchCommand );    # From "Search" command
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
