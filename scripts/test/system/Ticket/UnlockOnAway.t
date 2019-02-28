# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# get needed objects
my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

$Kernel::OM->Get('Kernel::Config')->Set(
    Key   => 'Ticket::UnlockOnAway',
    Value => 1,
);

my $TestUserLogin = $Helper->TestUserCreate(
    Groups => [ 'users', ],
);

my $TestUserID = $UserObject->UserLookup(
    UserLogin => $TestUserLogin,
);

my $TicketID = $TicketObject->TicketCreate(
    Title        => 'Some Ticket_Title',
    Queue        => 'Raw',
    Lock         => 'lock',
    Priority     => '3 normal',
    State        => 'closed successful',
    CustomerNo   => '123465',
    CustomerUser => 'customer@example.com',
    OwnerID      => $TestUserID,
    UserID       => 1,
);

$Self->True( $TicketID, 'Could create ticket' );

$TicketObject->ArticleCreate(
    TicketID       => $TicketID,
    Channel        => 'note',
    SenderType     => 'agent',
    Subject        => 'Should not unlock',
    Body           => '.',
    ContentType    => 'text/plain; charset=UTF-8',
    HistoryComment => 'Just a test',
    HistoryType    => 'OwnerUpdate',
    UserID         => 1,
    NoAgentNotify  => 1,
    UnlockOnAway   => 1,
);
my %Ticket = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1
);

$Self->Is(
    $Ticket{Lock},
    'lock',
    'Ticket still locked (UnlockOnAway)',
);
$UserObject->SetPreferences(
    UserID => $Ticket{OwnerID},
    Key    => 'OutOfOffice',
    Value  => 1,
);

my ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WeekDay ) = $TimeObject->SystemTime2Date(
    SystemTime => $TimeObject->SystemTime(),
);

# Special case for leap years. There is no Feb 29 in the next and previous years in this case.
if ( $Month == 2 && $Day == 29 ) {
    $Day--;
}

$UserObject->SetPreferences(
    UserID => $Ticket{OwnerID},
    Key    => 'OutOfOfficeStartYear',
    Value  => $Year - 1,
);
$UserObject->SetPreferences(
    UserID => $Ticket{OwnerID},
    Key    => 'OutOfOfficeEndYear',
    Value  => $Year + 1,
);
$UserObject->SetPreferences(
    UserID => $Ticket{OwnerID},
    Key    => 'OutOfOfficeStartMonth',
    Value  => $Month,
);
$UserObject->SetPreferences(
    UserID => $Ticket{OwnerID},
    Key    => 'OutOfOfficeEndMonth',
    Value  => $Month,
);
$UserObject->SetPreferences(
    UserID => $Ticket{OwnerID},
    Key    => 'OutOfOfficeStartDay',
    Value  => $Day,
);
$UserObject->SetPreferences(
    UserID => $Ticket{OwnerID},
    Key    => 'OutOfOfficeEndDay',
    Value  => $Day,
);

$TicketObject->ArticleCreate(
    TicketID       => $TicketID,
    Channel        => 'note',
    SenderType     => 'agent',
    Subject        => 'Should now unlock',
    Body           => '.',
    ContentType    => 'text/plain; charset=UTF-8',
    HistoryComment => 'Just a test',
    HistoryType    => 'OwnerUpdate',
    UserID         => 1,
    NoAgentNotify  => 1,
    UnlockOnAway   => 1,
);
%Ticket = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1
);

$Self->Is(
    $Ticket{Lock},
    'unlock',
    'Ticket now unlocked (UnlockOnAway)',
);

# cleanup is done by RestoreDatabase.

1;


=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<http://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
COPYING for license information (AGPL). If you did not receive this file, see

<http://www.gnu.org/licenses/agpl.txt>.

=cut