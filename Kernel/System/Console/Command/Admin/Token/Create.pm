# --
# Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console::Command::Admin::Token::Create;

use strict;
use warnings;

use base qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::Token',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Create AccessToken for remote APIs.');
    $Self->AddOption(
        Name        => 'user',
        Description => "The user identifier which will used by the token. Agent = UserLogin, Customer = CustomerKey.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    $Self->AddOption(
        Name        => 'user-type',
        Description => "The type of the user. Possible values are 'Agent' or 'Customer'",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/(Agent|Customer)/smx,
    );

    $Self->AddOption(
        Name        => 'valid-until',
        Description => "The token will be valid until the given daten+time. Format: YYYY-MM-DD HH24:MI:SS",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/^\d{4}-\d{2}-\d{2}[ ]\d{2}:\d{2}:\d{2}$/smx,
    );

    $Self->AddOption(
        Name        => 'remote-ip',
        Description => "The the remote IP for which the token should be valid.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    $Self->AddOption(
        Name        => 'description',
        Description => "It's recommended to add a description to identify the token.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->Print("<yellow>Creating token...</yellow>\n");

    my $UserID;
    my $UserType = $Self->GetOption('user-type');

    if ( $UserType eq 'Agent' ) {
        # lookup UserID
        $UserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
            UserLogin => $Self->GetOption('user'),
        );
    }
    elsif ( $UserType eq 'Customer' ) {
        # take user parameter as userid
        $UserID = $Self->GetOption('user');
    }

    if ( !$UserID ) {
        $Self->PrintError("No such user.");
        return $Self->ExitCodeError();
    }

    my $Token = $Kernel::OM->Get('Kernel::System::Token')->CreateToken(
        Payload => {
            UserID      => $UserID,
            UserType    => $UserType,
            ValidUntil  => $Self->GetOption('valid-until'),
            RemoteIP    => $Self->GetOption('remote-ip'),
            Description => $Self->GetOption('description'),
            TokenType   => 'AccessToken',
        },
    );

    $Self->Print("\n".$Token."\n");

    $Self->Print("<green>Done.</green>\n");

    return $Self->ExitCodeOk();
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