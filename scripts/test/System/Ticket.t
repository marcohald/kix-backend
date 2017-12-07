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
my $QueueObject   = $Kernel::OM->Get('Kernel::System::Queue');
my $ServiceObject = $Kernel::OM->Get('Kernel::System::Service');
my $SLAObject     = $Kernel::OM->Get('Kernel::System::SLA');
my $StateObject   = $Kernel::OM->Get('Kernel::System::State');
my $TicketObject  = $Kernel::OM->Get('Kernel::System::Ticket');
my $TimeObject    = $Kernel::OM->Get('Kernel::System::Time');
my $TypeObject    = $Kernel::OM->Get('Kernel::System::Type');
my $UserObject    = $Kernel::OM->Get('Kernel::System::User');

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

# set fixed time
$Helper->FixedTimeSet();

my $TicketID = $TicketObject->TicketCreate(
    Title        => 'Some Ticket_Title',
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'closed successful',
    CustomerNo   => '123465',
    CustomerUser => 'unittest@otrs.com',
    OwnerID      => 1,
    UserID       => 1,
);
$Self->True(
    $TicketID,
    'TicketCreate()',
);

my %Ticket = $TicketObject->TicketGet(
    TicketID => $TicketID,
    Extended => 1,
);
$Self->Is(
    $Ticket{Title},
    'Some Ticket_Title',
    'TicketGet() (Title)',
);
$Self->Is(
    $Ticket{Queue},
    'Raw',
    'TicketGet() (Queue)',
);
$Self->Is(
    $Ticket{Priority},
    '3 normal',
    'TicketGet() (Priority)',
);
$Self->Is(
    $Ticket{State},
    'closed successful',
    'TicketGet() (State)',
);
$Self->Is(
    $Ticket{Owner},
    'root@localhost',
    'TicketGet() (Owner)',
);
$Self->Is(
    $Ticket{CreateBy},
    1,
    'TicketGet() (CreateBy)',
);
$Self->Is(
    $Ticket{ChangeBy},
    1,
    'TicketGet() (ChangeBy)',
);
$Self->Is(
    $Ticket{Title},
    'Some Ticket_Title',
    'TicketGet() (Title)',
);
$Self->Is(
    $Ticket{Responsible},
    'root@localhost',
    'TicketGet() (Responsible)',
);
$Self->Is(
    $Ticket{Lock},
    'unlock',
    'TicketGet() (Lock)',
);
$Self->Is(
    $Ticket{ServiceID},
    '',
    'TicketGet() (ServiceID)',
);
$Self->Is(
    $Ticket{SLAID},
    '',
    'TicketGet() (SLAID)',
);

my $DefaultTicketType = $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Type::Default');
$Self->Is(
    $Ticket{TypeID},
    $TypeObject->TypeLookup( Type => $DefaultTicketType ),
    'TicketGet() (TypeID)',
);
$Self->Is(
    $Ticket{SolutionTime},
    $Ticket{Created},
    'Ticket created as closed as Solution Time = Creation Time',
);

my $TestUserLogin = $Helper->TestUserCreate(
    Groups => [ 'users', ],
);

my $TestUserID = $UserObject->UserLookup(
    UserLogin => $TestUserLogin,
);

my $TicketIDCreatedBy = $TicketObject->TicketCreate(
    Title        => 'Some Ticket_Title',
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'closed successful',
    CustomerNo   => '123465',
    CustomerUser => 'unittest@otrs.com',
    OwnerID      => 1,
    UserID       => $TestUserID,
);

my %CheckCreatedBy = $TicketObject->TicketGet(
    TicketID => $TicketIDCreatedBy,
    UserID   => $TestUserID,
);

$Self->Is(
    $CheckCreatedBy{ChangeBy},
    $TestUserID,
    'TicketGet() (ChangeBy - not system ID 1 user)',
);

$Self->Is(
    $CheckCreatedBy{CreateBy},
    $TestUserID,
    'TicketGet() (CreateBy - not system ID 1 user)',
);

$TicketObject->TicketOwnerSet(
    TicketID  => $TicketIDCreatedBy,
    NewUserID => $TestUserID,
    UserID    => 1,
);

%CheckCreatedBy = $TicketObject->TicketGet(
    TicketID => $TicketIDCreatedBy,
    UserID   => $TestUserID,
);

$Self->Is(
    $CheckCreatedBy{CreateBy},
    $TestUserID,
    'TicketGet() (CreateBy - still the same after OwnerSet)',
);

$Self->Is(
    $CheckCreatedBy{OwnerID},
    $TestUserID,
    'TicketOwnerSet()',
);

$Self->Is(
    $CheckCreatedBy{ChangeBy},
    1,
    'TicketOwnerSet() (ChangeBy - System ID 1 now)',
);

my $ArticleID = $TicketObject->ArticleCreate(
    TicketID    => $TicketID,
    ArticleType => 'note-internal',
    SenderType  => 'agent',
    From =>
        'Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent <email@example.com>',
    To =>
        'Some Customer A Some Customer A Some Customer A Some Customer A Some Customer A Some Customer A  Some Customer ASome Customer A Some Customer A <customer-a@example.com>',
    Cc =>
        'Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B <customer-b@example.com>',
    ReplyTo =>
        'Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B Some Customer B <customer-b@example.com>',
    Subject =>
        'some short description some short description some short description some short description some short description some short description some short description some short description ',
    Body => (
        'the message text
Perl modules provide a range of features to help you avoid reinventing the wheel, and can be downloaded from CPAN ( http://www.cpan.org/ ). A number of popular modules are included with the Perl distribution itself.

Categories of modules range from text manipulation to network protocols to database integration to graphics. A categorized list of modules is also available from CPAN.

To learn how to install modules you download from CPAN, read perlmodinstall

To learn how to use a particular module, use perldoc Module::Name . Typically you will want to use Module::Name , which will then give you access to exported functions or an OO interface to the module.

perlfaq contains questions and answers related to many common tasks, and often provides suggestions for good CPAN modules to use.

perlmod describes Perl modules in general. perlmodlib lists the modules which came with your Perl installation.

If you feel the urge to write Perl modules, perlnewmod will give you good advice.
' x 200
    ),    # create a really big string by concatenating 200 times

    ContentType    => 'text/plain; charset=ISO-8859-15',
    HistoryType    => 'OwnerUpdate',
    HistoryComment => 'Some free text!',
    UserID         => 1,
    NoAgentNotify  => 1,                                   # if you don't want to send agent notifications
);

$Self->True(
    $ArticleID,
    'ArticleCreate()',
);

$Self->Is(
    $TicketObject->ArticleCount( TicketID => $TicketID ),
    1,
    'ArticleCount',
);

my %Article = $TicketObject->ArticleGet( ArticleID => $ArticleID );
$Self->True(
    $Article{From} eq
        'Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent Some Agent <email@example.com>',
    'ArticleGet()',
);

for my $Key (qw( Body Subject From To ReplyTo )) {
    my $Success = $TicketObject->ArticleUpdate(
        ArticleID => $ArticleID,
        Key       => $Key,
        Value     => "New $Key",
        UserID    => 1,
        TicketID  => $TicketID,
    );
    $Self->True(
        $Success,
        'ArticleUpdate()',
    );
    my %Article2 = $TicketObject->ArticleGet( ArticleID => $ArticleID );
    $Self->Is(
        $Article2{$Key},
        "New $Key",
        'ArticleUpdate()',
    );

    # set old value
    $Success = $TicketObject->ArticleUpdate(
        ArticleID => $ArticleID,
        Key       => $Key,
        Value     => $Article{$Key},
        UserID    => 1,
        TicketID  => $TicketID,
    );
}

my $TicketSearchTicketNumber = substr $Ticket{TicketNumber}, 0, 10;
my %TicketIDs = $TicketObject->TicketSearch(
    Result       => 'HASH',
    Limit        => 100,
    Filter       => {
        OR => [ 
            {
                Field => 'TicketNumber',
                Value => $TicketSearchTicketNumber,
                Operator => 'STARTSWITH',
            },
            {
                Field => 'TicketNumber',
                Value => 'not exisiting',
                Operator => 'CONTAINS',
            }
        ]
    },
    UserID       => 1,
    Permission   => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber STARTSWITH or CONTAINS)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result       => 'HASH',
    Limit        => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'TicketNumber',
                Value => $Ticket{TicketNumber},
                Operator => 'EQ',
            },
        ]
    },    
    UserID       => 1,
    Permission   => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber EQUALS)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result     => 'HASH',
    Limit      => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'TicketID',
                Value => $TicketID,
                Operator => 'EQ',
            },
        ]
    },    
    UserID     => 1,
    Permission => 'rw',
);

$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketID EQUALS)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result     => 'HASH',
    Limit      => 100,
    Filter       => {
        OR => [ 
            {
                Field => 'TicketID',
                Value => $TicketID,
                Operator => 'EQ',
            },
            {
                Field => 'TicketID',
                Value => 42,
                Operator => 'EQ',
            },
        ]
    },  
    UserID     => 1,
    Permission => 'rw',
);

$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketID EQUALS A or B)',
);

my $Count = $TicketObject->TicketSearch(
    Result       => 'COUNT',
    Filter       => {
        OR => [ 
            {
                Field => 'TicketNumber',
                Value => $Ticket{TicketNumber},
                Operator => 'EQ',
            },
        ]
    },      
    UserID       => 1,
    Permission   => 'rw',
);
$Self->Is(
    $Count,
    1,
    'TicketSearch() (COUNT:TicketNumber EQUALS)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result       => 'HASH',
    Limit        => 100,
    Filter       => {
        OR => [ 
            {
                Field => 'TicketNumber',
                Value => [ $Ticket{TicketNumber}, '1234' ],
                Operator => 'IN',
            },
        ]  
    },  
    UserID       => 1,
    Permission   => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber IN)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result     => 'HASH',
    Limit      => 100,
    Filter     => {
        OR => [ 
            {
                Field => 'Title',
                Value => $Ticket{Title},
                Operator => 'EQ',
            },
        ]  
    }, 
    Title      => $Ticket{Title},
    UserID     => 1,
    Permission => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Title EQUALS)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result     => 'HASH',
    Limit      => 100,
    Filter     => {
        OR => [ 
            {
                Field => 'Title',
                Value => $Ticket{Title},
                Operator => 'EQ',
            },
            {
                Field => 'Title',
                Value => 'SomeTitleABC',
                Operator => 'EQ',
            },
        ]  
    }, 
    UserID     => 1,
    Permission => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Title EQUALS A or B)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result     => 'HASH',
    Limit      => 100,
    Filter     => {
        OR => [ 
            {
                Field => 'CustomerID',
                Value => $Ticket{CustomerID},
                Operator => 'EQ',
            },
        ]  
    },     
    UserID     => 1,
    Permission => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:CustomerID EQUALS)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result     => 'HASH',
    Limit      => 100,
    Filter     => {
        OR => [ 
            {
                Field => 'CustomerID',
                Value => [ $Ticket{CustomerID}, 'LULU' ],
                Operator => 'IN',
            },
        ]  
    },       
    UserID     => 1,
    Permission => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:CustomerID IN)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result     => 'HASH',
    Limit      => 100,
    Filter     => {
        AND => [ 
            {
                Field => 'CustomerID',
                Value => $Ticket{CustomerID},
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => 'LULU',
                Operator => 'EQ',
            },            
        ]  
    },  
    UserID     => 1,
    Permission => 'rw',
);
$Self->False(
    scalar $TicketIDs{$TicketID},
    'TicketSearch() (HASH:CustomerID EQUALS A and B)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result            => 'HASH',
    Limit             => 100,
    Filter     => {
        OR => [ 
            {
                Field => 'CustomerUserID',
                Value => $Ticket{CustomerUserID},
                Operator => 'EQ',
            },          
        ]  
    },      
    UserID            => 1,
    Permission        => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:CustomerUserID EQUALS)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result            => 'HASH',
    Limit             => 100,
    Filter     => {
        OR => [ 
            {
                Field => 'CustomerUserID',
                Value => [ $Ticket{CustomerUserID}, '1234' ],
                Operator => 'IN',
            },          
        ]  
    },      
    UserID            => 1,
    Permission        => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:CustomerUserID IN)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result            => 'HASH',
    Limit             => 100,
    Filter     => {
        AND => [ 
            {
                Field => 'TicketNumber',
                Value => $Ticket{TicketNumber},
                Operator => 'EQ',
            }, 
            {
                Field => 'Title',
                Value => $Ticket{Title},
                Operator => 'EQ',
            },                     
            {
                Field => 'CustomerUserID',
                Value => $Ticket{CustomerUserID},
                Operator => 'EQ',
            }, 
            {
                Field => 'CustomerID',
                Value => $Ticket{CustomerID},
                Operator => 'EQ',
            },     
        ]  
    },    
    UserID            => 1,
    Permission        => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber and Title and CustomerID and CustomerUserID EQUALS)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result            => 'HASH',
    Limit             => 100,
    Filter     => {
        AND => [ 
            {
                Field => 'TicketNumber',
                Value => [ $Ticket{TicketNumber}, 'ABC' ],
                Operator => 'IN',
            }, 
            {
                Field => 'Title',
                Value => [ $Ticket{Title}, '123' ],
                Operator => 'IN',
            },                     
            {
                Field => 'CustomerUserID',
                Value => [ $Ticket{CustomerUserID}, 'iadasd' ],
                Operator => 'IN',
            }, 
            {
                Field => 'CustomerID',
                Value => [ $Ticket{CustomerID}, '1213421' ],
                Operator => 'IN',
            },     
        ]  
    },     
    UserID            => 1,
    Permission        => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber and Title and CustomerID and CustomerUserID IN)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result            => 'HASH',
    Limit             => 100,
    Filter     => {
        OR => [ 
            {
                Field => 'TicketNumber',
                Value => [ $Ticket{TicketNumber}, 'ABC' ],
                Operator => 'IN',
            }, 
            {
                Field => 'Title',
                Value => [ $Ticket{Title}, '123' ],
                Operator => 'IN',
            },                     
            {
                Field => 'CustomerUserID',
                Value => [ $Ticket{CustomerUserID}, 'iadasd' ],
                Operator => 'IN',
            }, 
            {
                Field => 'CustomerID',
                Value => [ $Ticket{CustomerID}, '1213421' ],
                Operator => 'IN',
            },     
        ]  
    },     
    UserID            => 1,
    Permission        => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber or Title or CustomerID or CustomerUserID IN)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result       => 'HASH',
    Limit        => 100,
    Filter     => {
        AND => [ 
            {
                Field => 'TicketNumber',
                Value => [ $Ticket{TicketNumber}, 'ABC' ],
                Operator => 'IN',
            }, 
            {
                Field => 'StateType',
                Value => 'Closed',
                Operator => 'EQ',
            },                        
        ]  
    },      
    UserID       => 1,
    Permission   => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber,StateType:Closed)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result       => 'HASH',
    Limit        => 100,
    Filter     => {
        AND => [ 
            {
                Field => 'TicketNumber',
                Value => [ $Ticket{TicketNumber}, 'ABC' ],
                Operator => 'IN',
            }, 
            {
                Field => 'StateType',
                Value => 'Open',
                Operator => 'EQ',
            },                        
        ]  
    },     
    UserID       => 1,
    Permission   => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber,StateType:Open)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result              => 'HASH',
    Limit               => 100,
    Filter     => {
        AND => [ 
            {
                Field => 'Body',
                Value => 'write perl modules',
                Operator => 'CONTAINS',
            }, 
            {
                Field => 'StateType',
                Value => 'Closed',
                Operator => 'EQ',
            },                        
        ]  
    },        
    UserID              => 1,
    Permission          => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Body,StateType:Closed)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result              => 'HASH',
    Limit               => 100,
    Filter     => {
        AND => [ 
            {
                Field => 'Body',
                Value => 'write perl modules',
                Operator => 'CONTAINS',
            }, 
            {
                Field => 'StateType',
                Value => 'Open',
                Operator => 'EQ',
            },                        
        ]  
    },    
    UserID              => 1,
    Permission          => 'rw',
);
$Self->True(
    !$TicketIDs{$TicketID},
    'TicketSearch() (HASH:Body,StateType:Open)',
);

$TicketObject->MoveTicket(
    Queue              => 'Junk',
    TicketID           => $TicketID,
    SendNoNotification => 1,
    UserID             => 1,
);

$TicketObject->MoveTicket(
    Queue              => 'Raw',
    TicketID           => $TicketID,
    SendNoNotification => 1,
    UserID             => 1,
);

my %HD = $TicketObject->HistoryTicketGet(
    StopYear  => 4000,
    StopMonth => 1,
    StopDay   => 1,
    TicketID  => $TicketID,
    Force     => 1,
);
my $QueueLookupID = $QueueObject->QueueLookup( Queue => $HD{Queue} );
$Self->Is(
    $QueueLookupID,
    $HD{QueueID},
    'HistoryTicketGet() Check history queue',
);

my $TicketMove = $TicketObject->MoveTicket(
    Queue              => 'Junk',
    TicketID           => $TicketID,
    SendNoNotification => 1,
    UserID             => 1,
);
$Self->True(
    $TicketMove,
    'MoveTicket()',
);

my $TicketState = $TicketObject->StateSet(
    State    => 'open',
    TicketID => $TicketID,
    UserID   => 1,
);
$Self->True(
    $TicketState,
    'StateSet()',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result       => 'HASH',
    Limit        => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'TicketNumber',
                Value => [$Ticket{TicketNumber}, 'ABC'],
                Operator => 'IN',
            },
            {
                Field => 'StateType',
                Value => 'Open',
                Operator => 'EQ',
            }
        ]
    },    
    UserID       => 1,
    Permission   => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber,StateType:Open)',
);

%TicketIDs = $TicketObject->TicketSearch(
    Result       => 'HASH',
    Limit        => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'TicketNumber',
                Value => [$Ticket{TicketNumber}, 'ABC'],
                Operator => 'IN',
            },
            {
                Field => 'StateType',
                Value => 'Closed',
                Operator => 'EQ',
            }
        ]
    },      
    UserID       => 1,
    Permission   => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:TicketNumber,StateType:Closed)',
);

my $TicketPriority = $TicketObject->PrioritySet(
    Priority => '2 low',
    TicketID => $TicketID,
    UserID   => 1,
);
$Self->True(
    $TicketPriority,
    'PrioritySet()',
);

# get ticket data
my %TicketData = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

# save current change_time
my $ChangeTime = $TicketData{Changed};

# wait 5 seconds
$Helper->FixedTimeAddSeconds(5);

my $TicketTitle = $TicketObject->TicketTitleUpdate(
    Title => 'Very long title 01234567890123456789012345678901234567890123456789'
        . '0123456789012345678901234567890123456789012345678901234567890123456789'
        . '0123456789012345678901234567890123456789012345678901234567890123456789'
        . '0123456789012345678901234567890123456789',
    TicketID => $TicketID,
    UserID   => 1,
);
$Self->True(
    $TicketTitle,
    'TicketTitleUpdate()',
);

# get updated ticket data
%TicketData = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

# compare current change_time with old one
$Self->IsNot(
    $ChangeTime,
    $TicketData{Changed},
    'Change_time updated in TicketTitleUpdate()',
);

# check if we have a Ticket Title Update history record
my @HistoryLines = $TicketObject->HistoryGet(
    TicketID => $TicketID,
    UserID   => 1,
);
my $HistoryItem = pop @HistoryLines;
$Self->Is(
    $HistoryItem->{HistoryType},
    'TitleUpdate',
    "TicketTitleUpdate - found HistoryItem",
);

$Self->Is(
    $HistoryItem->{Name},
    '%%Some Ticket_Title%%Very long title 0123456789012345678901234567890123...',
    "TicketTitleUpdate - Found new title",
);

# get updated ticket data
%TicketData = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

# save current change_time
$ChangeTime = $TicketData{Changed};

# wait 5 seconds
$Helper->FixedTimeAddSeconds(5);

# set unlock timeout
my $UnlockTimeout = $TicketObject->TicketUnlockTimeoutUpdate(
    UnlockTimeout => $TimeObject->SystemTime() + 10000,
    TicketID      => $TicketID,
    UserID        => 1,
);

$Self->True(
    $UnlockTimeout,
    'TicketUnlockTimeoutUpdate()',
);

# get updated ticket data
%TicketData = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

# compare current change_time with old one
$Self->IsNot(
    $ChangeTime,
    $TicketData{Changed},
    'Change_time updated in TicketUnlockTimeoutUpdate()',
);

# save current change_time
$ChangeTime = $TicketData{Changed};

# save current queue
my $CurrentQueueID = $TicketData{QueueID};

# wait 5 seconds
$Helper->FixedTimeAddSeconds(5);

my $NewQueue = $CurrentQueueID != 1 ? 1 : 2;

# set queue
my $TicketQueueSet = $TicketObject->TicketQueueSet(
    QueueID  => $NewQueue,
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->True(
    $TicketQueueSet,
    'TicketQueueSet()',
);

# get updated ticket data
%TicketData = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

# compare current change_time with old one
$Self->IsNot(
    $ChangeTime,
    $TicketData{Changed},
    'Change_time updated in TicketQueueSet()',
);

# restore queue
$TicketQueueSet = $TicketObject->TicketQueueSet(
    QueueID  => $CurrentQueueID,
    TicketID => $TicketID,
    UserID   => 1,
);

# save current change_time
$ChangeTime = $TicketData{Changed};

# save current type
my $CurrentTicketType = $TicketData{TypeID};

# wait 5 seconds
$Helper->FixedTimeAddSeconds(5);

# create a test type
my $TypeID = $TypeObject->TypeAdd(
    Name    => 'Type' . $Helper->GetRandomID(),
    ValidID => 1,
    UserID  => 1,
);

# set type
my $TicketTypeSet = $TicketObject->TicketTypeSet(
    TypeID   => $TypeID,
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->True(
    $TicketTypeSet,
    'TicketTypeSet()',
);

# get updated ticket data
%TicketData = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

# compare current change_time with old one
$Self->IsNot(
    $ChangeTime,
    $TicketData{Changed},
    'Change_time updated in TicketTypeSet()',
);

# restore type
$TicketTypeSet = $TicketObject->TicketTypeSet(
    TypeID   => $CurrentTicketType,
    TicketID => $TicketID,
    UserID   => 1,
);

# set as invalid the test type
$TypeObject->TypeUpdate(
    ID      => $TypeID,
    Name    => 'Type' . $Helper->GetRandomID(),
    ValidID => 2,
    UserID  => 1,
);

# create a test service
my $ServiceID = $ServiceObject->ServiceAdd(
    Name    => 'Service' . $Helper->GetRandomID(),
    ValidID => 1,
    Comment => 'Unit Test Comment',
# ---
# ITSMCore
# ---
    TypeID      => 1,
    Criticality => '3 normal',
# ---
    UserID  => 1,
);

# wait 1 seconds
$Helper->FixedTimeAddSeconds(1);

# set type
my $TicketServiceSet = $TicketObject->TicketServiceSet(
    ServiceID => $ServiceID,
    TicketID  => $TicketID,
    UserID    => 1,
);

$Self->True(
    $TicketServiceSet,
    'TicketServiceSet()',
);

# get updated ticket data
%TicketData = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

# compare current change_time with old one
$Self->IsNot(
    $ChangeTime,
    $TicketData{Changed},
    'Change_time updated in TicketServiceSet()',
);

# set as invalid the test service
my %Service = $ServiceObject->ServiceGet(
    ServiceID => $ServiceID,
    UserID    => 1, 
);
$ServiceObject->ServiceUpdate(
    ServiceID   => $ServiceID,
    Name        => 'Service' . $Helper->GetRandomID(),
    TypeID      => $Service{TypeID},
    Criticality => $Service{Criticality},    
    ValidID     => 2,
    UserID      => 1,
);

# save current change_time
$ChangeTime = $TicketData{Changed};

# wait 5 seconds
$Helper->FixedTimeAddSeconds(5);

my $TicketEscalationIndexBuild = $TicketObject->TicketEscalationIndexBuild(
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->True(
    $TicketEscalationIndexBuild,
    'TicketEscalationIndexBuild()',
);

# get updated ticket data
%TicketData = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

# compare current change_time with old one
$Self->IsNot(
    $ChangeTime,
    $TicketData{Changed},
    'Change_time updated in TicketEscalationIndexBuild()',
);

# save current change_time
$ChangeTime = $TicketData{Changed};

# create a test SLA
my $SLAID = $SLAObject->SLAAdd(
    Name    => 'SLA' . $Helper->GetRandomID(),
    ValidID => 1,
    Comment => 'Unit Test Comment',
# ---
# ITSMCore
# ---
    TypeID => 1,
# ---
    UserID  => 1,
);

# wait 5 seconds
$Helper->FixedTimeAddSeconds(5);

# set SLA
my $TicketSLASet = $TicketObject->TicketSLASet(
    SLAID    => $SLAID,
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->True(
    $TicketSLASet,
    'TicketSLASet()',
);

# get updated ticket data
%TicketData = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

# compare current change_time with old one
$Self->IsNot(
    $ChangeTime,
    $TicketData{Changed},
    'Change_time updated in TicketSLASet()',
);

# set as invalid the test SLA
my %SLA = $SLAObject->SLAGet(
    SLAID  => $SLAID,
    UserID => 1, 
);
$SLAObject->SLAUpdate(
    SLAID   => $SLAID,
    Name    => 'SLA' . $Helper->GetRandomID(),
    TypeID  => $SLA{TypeID},
    ValidID => 1,
    Comment => 'Unit Test Comment',
    UserID  => 1,
);

my $TicketLock = $TicketObject->LockSet(
    Lock               => 'lock',
    TicketID           => $TicketID,
    SendNoNotification => 1,
    UserID             => 1,
);
$Self->True(
    $TicketLock,
    'LockSet()',
);

# Test CreatedUserIDs
%TicketIDs = $TicketObject->TicketSearch(
    Result         => 'HASH',
    Limit          => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CreatedUserID',
                Value => [ 1, 455, 32 ],
                Operator => 'IN',
            },
        ]
    },      
    UserID         => 1,
    Permission     => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:CreatedUserID IN)',
);

# Test CreatedPriorityIDs
%TicketIDs = $TicketObject->TicketSearch(
    Result             => 'HASH',
    Limit              => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CreatedPriorityID',
                Value => [ 2, 3 ],
                Operator => 'IN',
            },
        ]
    },     
    UserID             => 1,
    Permission         => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:CreatedPriorityID IN)',
);

# Test CreatedStateIDs
%TicketIDs = $TicketObject->TicketSearch(
    Result          => 'HASH',
    Limit           => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CreatedStateID',
                Value => [ 2 ],
                Operator => 'IN',
            },
        ]
    },     
    UserID          => 1,
    Permission      => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:CreatedStateID IN)',
);

# Test CreatedQueueIDs
%TicketIDs = $TicketObject->TicketSearch(
    Result          => 'HASH',
    Limit           => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CreatedQueueID',
                Value => [ 2, 3 ],
                Operator => 'IN',
            },
        ]
    },  
    UserID          => 1,
    Permission      => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:CreatedQueueID IN)',
);

# Test CreateTime
my $CreateTime = $TimeObject->SystemTime2TimeStamp(
    SystemTime => $TimeObject->SystemTime() - 3600,
);
%TicketIDs = $TicketObject->TicketSearch(
    Result                       => 'HASH',
    Limit                        => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CreateTime',
                Value => $CreateTime,
                Operator => 'GTE',
            },
        ]
    },
    UserID                       => 1,
    Permission                   => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Ticket CreateTime >= now()-60 min)',
);

# Test LastChangeTime
my $CreateTime = $TimeObject->SystemTime2TimeStamp(
    SystemTime => $TimeObject->SystemTime() - 3600,
);
%TicketIDs = $TicketObject->TicketSearch(
    Result                           => 'HASH',
    Limit                            => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'LastChangeTime',
                Value => $ChangeTime,
                Operator => 'GTE',
            },
        ]
    },    
    UserID                           => 1,
    Permission                       => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Ticket LastChangeTime >= now()-60 min)',
);

# Test ArticleCreateTime
%TicketIDs = $TicketObject->TicketSearch(
    Result                        => 'HASH',
    Limit                         => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'ArticleCreateTime',
                Value => $CreateTime,
                Operator => 'GTE',
            },
        ]
    },
    UserID                        => 1,
    Permission                    => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Article CreateTime >= now()-60 min)',
);

# Test CreateTime
%TicketIDs = $TicketObject->TicketSearch(
    Result                       => 'HASH',
    Limit                        => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CreateTime',
                Value => $CreateTime,
                Operator => 'LT',
            },
        ]
    },
    UserID                       => 1,
    Permission                   => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Ticket CreateTime < now()-60 min)',
);

# Test TicketLastChangeOlderMinutes
%TicketIDs = $TicketObject->TicketSearch(
    Result                           => 'HASH',
    Limit                            => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'LastChangeTime',
                Value => $ChangeTime,
                Operator => 'LT',
            },
        ]
    },
    UserID                           => 1,
    Permission                       => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Ticket LastChangeTime < now()-60 min)',
);

# Test ArticleCreateTime
%TicketIDs = $TicketObject->TicketSearch(
    Result                        => 'HASH',
    Limit                         => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'ArticleCreateTime',
                Value => $CreateTime,
                Operator => 'LT',
            },
        ]
    },
    UserID                        => 1,
    Permission                    => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Article CreateTime < now()-60 min)',
);

# Test CloseTime
%TicketIDs = $TicketObject->TicketSearch(
    Result                   => 'HASH',
    Limit                    => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CloseTime',
                Value => $CreateTime,
                Operator => 'GTE',
            },
        ]
    },
    UserID     => 1,
    Permission => 'rw',
);
$Self->True(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Ticket CloseTime >= now()-60 min)',
);

# Test TicketCloseOlderDate
%TicketIDs = $TicketObject->TicketSearch(
    Result                   => 'HASH',
    Limit                    => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CloseTime',
                Value => $CreateTime,
                Operator => 'LT',
            },
        ]
    },
    UserID     => 1,
    Permission => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Ticket CreateTime < now()-60 min)',
);

my %Ticket2 = $TicketObject->TicketGet( TicketID => $TicketID );
$Self->Is(
    $Ticket2{Title},
    'Very long title 01234567890123456789012345678901234567890123456789'
        . '0123456789012345678901234567890123456789012345678901234567890123456789'
        . '0123456789012345678901234567890123456789012345678901234567890123456789'
        . '0123456789012345678901234567890123456789',
    'TicketGet() (Title)',
);
$Self->Is(
    $Ticket2{Queue},
    'Junk',
    'TicketGet() (Queue)',
);
$Self->Is(
    $Ticket2{Priority},
    '2 low',
    'TicketGet() (Priority)',
);
$Self->Is(
    $Ticket2{State},
    'open',
    'TicketGet() (State)',
);
$Self->Is(
    $Ticket2{Lock},
    'lock',
    'TicketGet() (Lock)',
);

my @MoveQueueList = $TicketObject->MoveQueueList(
    TicketID => $TicketID,
    Type     => 'Name',
);

$Self->Is(
    $MoveQueueList[0],
    'Raw',
    'MoveQueueList() (Raw)',
);
$Self->Is(
    $MoveQueueList[$#MoveQueueList],
    'Junk',
    'MoveQueueList() (Junk)',
);

my $TicketAccountTime = $TicketObject->TicketAccountTime(
    TicketID  => $TicketID,
    ArticleID => $ArticleID,
    TimeUnit  => '4.5',
    UserID    => 1,
);

$Self->True(
    $TicketAccountTime,
    'TicketAccountTime() 1',
);

my $TicketAccountTime2 = $TicketObject->TicketAccountTime(
    TicketID  => $TicketID,
    ArticleID => $ArticleID,
    TimeUnit  => '4123.53',
    UserID    => 1,
);

$Self->True(
    $TicketAccountTime2,
    'TicketAccountTime() 2',
);

my $TicketAccountTime3 = $TicketObject->TicketAccountTime(
    TicketID  => $TicketID,
    ArticleID => $ArticleID,
    TimeUnit  => '4,53',
    UserID    => 1,
);

$Self->True(
    $TicketAccountTime3,
    'TicketAccountTime() 3',
);

my $AccountedTime = $TicketObject->TicketAccountedTimeGet( TicketID => $TicketID );

$Self->Is(
    $AccountedTime,
    4132.56,
    'TicketAccountedTimeGet()',
);

my $AccountedTime2 = $TicketObject->ArticleAccountedTimeGet(
    ArticleID => $ArticleID,
);

$Self->Is(
    $AccountedTime2,
    4132.56,
    'ArticleAccountedTimeGet()',
);

my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $TimeObject->SystemTime2Date(
    SystemTime => $TimeObject->SystemTime(),
);

my ( $StopSec, $StopMin, $StopHour, $StopDay, $StopMonth, $StopYear ) = $TimeObject->SystemTime2Date(
    SystemTime => $TimeObject->SystemTime() - 60 * 60 * 24,
);

my %TicketStatus = $TicketObject->HistoryTicketStatusGet(
    StopYear   => $Year,
    StopMonth  => $Month,
    StopDay    => $Day,
    StartYear  => $StopYear,
    StartMonth => $StopMonth,
    StartDay   => $StopDay,
);

if ( $TicketStatus{$TicketID} ) {
    my %TicketHistory = %{ $TicketStatus{$TicketID} };
    $Self->Is(
        $TicketHistory{TicketNumber},
        $Ticket{TicketNumber},
        "HistoryTicketStatusGet() (TicketNumber)",
    );
    $Self->Is(
        $TicketHistory{TicketID},
        $TicketID,
        "HistoryTicketStatusGet() (TicketID)",
    );
    $Self->Is(
        $TicketHistory{CreateUserID},
        1,
        "HistoryTicketStatusGet() (CreateUserID)",
    );
    $Self->Is(
        $TicketHistory{Queue},
        'Junk',
        "HistoryTicketStatusGet() (Queue)",
    );
    $Self->Is(
        $TicketHistory{CreateQueue},
        'Raw',
        "HistoryTicketStatusGet() (CreateQueue)",
    );
    $Self->Is(
        $TicketHistory{State},
        'open',
        "HistoryTicketStatusGet() (State)",
    );
    $Self->Is(
        $TicketHistory{CreateState},
        'closed successful',
        "HistoryTicketStatusGet() (CreateState)",
    );
    $Self->Is(
        $TicketHistory{Priority},
        '2 low',
        "HistoryTicketStatusGet() (Priority)",
    );
    $Self->Is(
        $TicketHistory{CreatePriority},
        '3 normal',
        "HistoryTicketStatusGet() (CreatePriority)",
    );

}
else {
    $Self->True(
        0,
        'HistoryTicketStatusGet()',
    );
}

my $Delete = $TicketObject->TicketDelete(
    TicketID => $TicketID,
    UserID   => 1,
);
$Self->True(
    $Delete,
    'TicketDelete()',
);

my $DeleteCheck = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->False(
    $DeleteCheck,
    'TicketDelete() worked',
);

my $CustomerNo = 'CustomerNo' . $Helper->GetRandomID();

# ticket search sort/order test
my $TicketIDSortOrder1 = $TicketObject->TicketCreate(
    Title        => 'Some Ticket_Title - ticket sort/order by tests',
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'new',
    CustomerNo   => $CustomerNo,
    CustomerUser => 'unittest@otrs.com',
    OwnerID      => 1,
    UserID       => 1,
);

my %TicketCreated = $TicketObject->TicketGet(
    TicketID => $TicketIDSortOrder1,
    UserID   => 1,
);

# wait 5 seconds
$Helper->FixedTimeAddSeconds(2);

my $TicketIDSortOrder2 = $TicketObject->TicketCreate(
    Title        => 'Some Ticket_Title - ticket sort/order by tests2',
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'new',
    CustomerNo   => $CustomerNo,
    CustomerUser => 'unittest@otrs.com',
    OwnerID      => 1,
    UserID       => 1,
);

# wait 5 seconds
$Helper->FixedTimeAddSeconds(2);

my $Success = $TicketObject->TicketStateSet(
    State    => 'open',
    TicketID => $TicketIDSortOrder1,
    UserID   => 1,
);

my %TicketUpdated = $TicketObject->TicketGet(
    TicketID => $TicketIDSortOrder1,
    UserID   => 1,
);

$Self->IsNot(
    $TicketCreated{Changed},
    $TicketUpdated{Changed},
    'TicketUpdated for sort - change time was updated'
        . " $TicketCreated{Changed} ne $TicketUpdated{Changed}",
);

# find newest ticket by priority, age
my $QueueID = $QueueObject->QueueLookup( Queue => 'Raw' );
my @TicketIDsSortOrder = $TicketObject->TicketSearch(
    Result       => 'ARRAY',
    Filter       => {
        AND => [ 
            {
                Field => 'Title',
                Value => 'sort/order by test',
                Operator => 'CONTAINS',
            },
            {
                Field => 'QueueID',
                Value => $QueueID,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => $CustomerNo,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            }            
        ]
    },
    Sort => [
        {
            Field => "PriorityID",
            Direction => 'descending',
        },  
        {
            Field => "Age",
            Direction => 'ascending',
        }        
    ],      
    UserID       => 1,
    Limit        => 1,
);

$Self->Is(
    $TicketIDsSortOrder[0],
    $TicketIDSortOrder1,
    'TicketTicketSearch() - ticket sort/order by (PriorityID (Down), Age (Up))',
);

# find oldest ticket by priority, age
@TicketIDsSortOrder = $TicketObject->TicketSearch(
    Result       => 'ARRAY',
    Filter       => {
        AND => [ 
            {
                Field => 'Title',
                Value => 'sort/order by test',
                Operator => 'CONTAINS',
            },
            {
                Field => 'QueueID',
                Value => $QueueID,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => $CustomerNo,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            }            
        ]
    },
    Sort => [
        {
            Field => "PriorityID",
            Direction => 'descending',
        },  
        {
            Field => "Age",
            Direction => 'descending',
        }
    ], 
    UserID       => 1,
    Limit        => 1,
);
$Self->Is(
    $TicketIDsSortOrder[0],
    $TicketIDSortOrder2,
    'TicketTicketSearch() - ticket sort/order by (PriorityID (Down), Age (Down))',
);

# find last modified ticket by changed time
@TicketIDsSortOrder = $TicketObject->TicketSearch(
    Result       => 'ARRAY',
    Filter       => {
        AND => [ 
            {
                Field => 'Title',
                Value => 'sort/order by test',
                Operator => 'CONTAINS',
            },
            {
                Field => 'QueueID',
                Value => $QueueID,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => $CustomerNo,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            }            
        ]
    },
    Sort => [
        {
            Field => "ChangeTime",
            Direction => 'descending',
        },  
    ], 
    UserID       => 1,
    Limit        => 1,
);
$Self->Is(
    $TicketIDsSortOrder[0],
    $TicketIDSortOrder1,
    'TicketTicketSearch() - ticket sort/order by (ChangeTime (Down))'
        . "$TicketIDsSortOrder[0] instead of $TicketIDSortOrder1",
);

# find oldest modified by changed time
@TicketIDsSortOrder = $TicketObject->TicketSearch(
    Result       => 'ARRAY',
    Filter       => {
        AND => [ 
            {
                Field => 'Title',
                Value => 'sort/order by test',
                Operator => 'CONTAINS',
            },
            {
                Field => 'QueueID',
                Value => $QueueID,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => $CustomerNo,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            }            
        ]
    },
    Sort => [
        {
            Field => "ChangeTime",
            Direction => 'ascending',
        },  
    ], 
    UserID       => 1,
    Limit        => 1,
);
$Self->Is(
    $TicketIDsSortOrder[0],
    $TicketIDSortOrder2,
    'TicketTicketSearch() - ticket sort/order by (ChangeTime (Up)))'
        . "$TicketIDsSortOrder[0]  instead of $TicketIDSortOrder2",
);

my $TicketIDSortOrder3 = $TicketObject->TicketCreate(
    Title        => 'Some Ticket_Title - ticket sort/order by tests2',
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '4 high',
    State        => 'new',
    CustomerNo   => $CustomerNo,
    CustomerUser => 'unittest@otrs.com',
    OwnerID      => 1,
    UserID       => 1,
);

# wait 2 seconds
$Helper->FixedTimeAddSeconds(2);

my $TicketIDSortOrder4 = $TicketObject->TicketCreate(
    Title        => 'Some Ticket_Title - ticket sort/order by tests2',
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '4 high',
    State        => 'new',
    CustomerNo   => $CustomerNo,
    CustomerUser => 'unittest@otrs.com',
    OwnerID      => 1,
    UserID       => 1,
);

# find oldest ticket by priority, age
@TicketIDsSortOrder = $TicketObject->TicketSearch(
    Result       => 'ARRAY',
    Filter       => {
        AND => [ 
            {
                Field => 'Title',
                Value => 'sort/order by test',
                Operator => 'CONTAINS',
            },
            {
                Field => 'QueueID',
                Value => $QueueID,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => $CustomerNo,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            }            
        ]
    },
    Sort => [
        {
            Field => "PriorityID",
            Direction => 'descending',
        },  
        {
            Field => "Age",
            Direction => 'descending',
        }
    ],     
    UserID       => 1,
    Limit        => 1,
);
$Self->Is(
    $TicketIDsSortOrder[0],
    $TicketIDSortOrder4,
    'TicketTicketSearch() - ticket sort/order by (Priority (Down), Age (Down))',
);

# find oldest ticket by priority, age
@TicketIDsSortOrder = $TicketObject->TicketSearch(
    Result       => 'ARRAY',
    Filter       => {
        AND => [ 
            {
                Field => 'Title',
                Value => 'sort/order by test',
                Operator => 'CONTAINS',
            },
            {
                Field => 'QueueID',
                Value => $QueueID,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => $CustomerNo,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            }            
        ]
    },
    Sort => [
        {
            Field => "PriorityID",
            Direction => 'ascending',
        },  
        {
            Field => "Age",
            Direction => 'descending',
        }
    ],       
    UserID       => 1,
    Limit        => 1,
);
$Self->Is(
    $TicketIDsSortOrder[0],
    $TicketIDSortOrder2,
    'TicketTicketSearch() - ticket sort/order by (Priority (Up), Age (Down))',
);

# find newest ticket
@TicketIDsSortOrder = $TicketObject->TicketSearch(
    Result       => 'ARRAY',
    Filter       => {
        AND => [ 
            {
                Field => 'Title',
                Value => 'sort/order by test',
                Operator => 'CONTAINS',
            },
            {
                Field => 'QueueID',
                Value => $QueueID,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => $CustomerNo,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            }            
        ]
    },
    Sort => [
        {
            Field => "Age",
            Direction => 'descending',
        }
    ],       
    UserID       => 1,
    Limit        => 1,
);
$Self->Is(
    $TicketIDsSortOrder[0],
    $TicketIDSortOrder4,
    'TicketTicketSearch() - ticket sort/order by (Age (Down))',
);

# find oldest ticket
@TicketIDsSortOrder = $TicketObject->TicketSearch(
    Result       => 'ARRAY',
    Filter       => {
        AND => [ 
            {
                Field => 'Title',
                Value => 'sort/order by test',
                Operator => 'CONTAINS',
            },
            {
                Field => 'QueueID',
                Value => $QueueID,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => $CustomerNo,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            }            
        ]
    },
    Sort => [
        {
            Field => "Age",
            Direction => 'ascending',
        }
    ],       
    UserID       => 1,
    Limit        => 1,
);
$Self->Is(
    $TicketIDsSortOrder[0],
    $TicketIDSortOrder1,
    'TicketTicketSearch() - ticket sort/order by (Age (Up))',
);

$Count = $TicketObject->TicketSearch(
    Result       => 'COUNT',
    Filter       => {
        AND => [ 
            {
                Field => 'Title',
                Value => 'sort/order by test',
                Operator => 'CONTAINS',
            },
            {
                Field => 'QueueID',
                Value => $QueueID,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerID',
                Value => $CustomerNo,
                Operator => 'EQ',
            },
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            }            
        ]
    },
    UserID       => 1,
    Limit        => 1,
);
$Self->Is(
    $Count,
    4,
    'TicketTicketSearch() - ticket count for created tickets',
);

for my $TicketIDDelete (
    $TicketIDSortOrder1, $TicketIDSortOrder2, $TicketIDSortOrder3,
    $TicketIDSortOrder4
    )
{
    $Self->True(
        $TicketObject->TicketDelete(
            TicketID => $TicketIDDelete,
            UserID   => 1,
        ),
        "TicketDelete()",
    );
}

# avoid StateType and StateTypeID problems in TicketSearch()

my %StateTypeList = $StateObject->StateTypeList(
    UserID => 1,
);

# you need a hash with the state as key and the related StateType and StateTypeID as
# reference
my %StateAsKeyAndStateTypeAsValue;
for my $StateTypeID ( sort keys %StateTypeList ) {
    my @List = $StateObject->StateGetStatesByType(
        StateType => [ $StateTypeList{$StateTypeID} ],
        Result    => 'Name',                             # HASH|ID|Name
    );
    for my $Index (@List) {
        $StateAsKeyAndStateTypeAsValue{$Index}->{Name} = $StateTypeList{$StateTypeID};
        $StateAsKeyAndStateTypeAsValue{$Index}->{ID}   = $StateTypeID;
    }
}

# to be sure that you have a result ticket create one
$TicketID = $TicketObject->TicketCreate(
    Title        => 'StateTypeTest',
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'new',
    CustomerID   => '123465',
    CustomerUser => 'unittest@otrs.com',
    OwnerID      => 1,
    UserID       => 1,
);

my %StateList = $StateObject->StateList( UserID => 1 );

# now check every possible state
for my $State ( values %StateList ) {
    $TicketObject->StateSet(
        State              => $State,
        TicketID           => $TicketID,
        SendNoNotification => 1,
        UserID             => 1,
    );

    my @TicketIDs = $TicketObject->TicketSearch(
        Result       => 'ARRAY',
        Filter       => {
            AND => [ 
                {
                    Field => 'Title',
                    Value => 'StateTypeTest',
                    Operator => 'CONTAINS',
                },
                {
                    Field => 'QueueID',
                    Value => $QueueID,
                    Operator => 'EQ',
                },
                {
                    Field => 'StateTypeID',
                    Value => [ $StateAsKeyAndStateTypeAsValue{$State}->{ID} ],
                    Operator => 'IN',
                }            
            ]
        },
        UserID       => 1,
    );

    my @TicketIDsType = $TicketObject->TicketSearch(
        Result    => 'ARRAY',
        Filter       => {
            AND => [ 
                {
                    Field => 'Title',
                    Value => 'StateTypeTest',
                    Operator => 'CONTAINS',
                },
                {
                    Field => 'QueueID',
                    Value => $QueueID,
                    Operator => 'EQ',
                },
                {
                    Field => 'StateType',
                    Value => [ $StateAsKeyAndStateTypeAsValue{$State}->{Name} ],
                    Operator => 'IN',
                }            
            ]
        },
        UserID    => 1,
    );

    if ( $TicketIDs[0] ) {
        my %Ticket = $TicketObject->TicketGet(
            TicketID => $TicketIDs[0],
            UserID   => 1,
        );
    }

    # if there is no result the StateTypeID hasn't worked
    # Test if there is a result, if I use StateTypeID $StateAsKeyAndStateTypeAsValue{$State}->{ID}
    $Self->True(
        $TicketIDs[0],
        "TicketSearch() - StateTypeID - found ticket",
    );

# if it is not equal then there is in the using of StateType or StateTypeID an error
# check if you get the same result if you use the StateType attribute or the StateTypeIDs attribute.
# State($State) StateType($StateAsKeyAndStateTypeAsValue{$State}->{Name}) and StateTypeIDs($StateAsKeyAndStateTypeAsValue{$State}->{ID})
    $Self->Is(
        scalar @TicketIDs,
        scalar @TicketIDsType,
        "TicketSearch() - StateType",
    );
}

my %TicketPending = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->Is(
    $TicketPending{UntilTime},
    '0',
    "TicketPendingTimeSet() - Pending Time - not set",
);

my $Diff               = 60;
my $CurrentSystemTime  = $TimeObject->SystemTime();
my $PendingTimeSetDiff = $TicketObject->TicketPendingTimeSet(
    Diff     => $Diff,
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->True(
    $PendingTimeSetDiff,
    "TicketPendingTimeSet() - Pending Time - set diff",
);

%TicketPending = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->Is(
    $TicketPending{RealTillTimeNotUsed},
    $CurrentSystemTime + $Diff * 60,
    "TicketPendingTimeSet() - diff time check",
);

my $PendingTimeSet = $TicketObject->TicketPendingTimeSet(
    TicketID => $TicketID,
    UserID   => 1,
    Year     => '2003',
    Month    => '08',
    Day      => '14',
    Hour     => '22',
    Minute   => '05',
);

$Self->True(
    $PendingTimeSet,
    "TicketPendingTimeSet() - Pending Time - set",
);

%TicketPending = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

my $PendingUntilTime = $TimeObject->Date2SystemTime(
    Year   => '2003',
    Month  => '08',
    Day    => '14',
    Hour   => '22',
    Minute => '05',
    Second => '00',
);

$PendingUntilTime = $TimeObject->SystemTime() - $PendingUntilTime;

$Self->Is(
    $TicketPending{UntilTime},
    '-' . $PendingUntilTime,
    "TicketPendingTimeSet() - Pending Time - read back",
);

$PendingTimeSet = $TicketObject->TicketPendingTimeSet(
    TicketID => $TicketID,
    UserID   => 1,
    Year     => '0',
    Month    => '0',
    Day      => '0',
    Hour     => '0',
    Minute   => '0',
);

$Self->True(
    $PendingTimeSet,
    "TicketPendingTimeSet() - Pending Time - reset",
);

%TicketPending = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->Is(
    $TicketPending{UntilTime},
    '0',
    "TicketPendingTimeSet() - Pending Time - not set",
);

$PendingTimeSet = $TicketObject->TicketPendingTimeSet(
    TicketID => $TicketID,
    UserID   => 1,
    String   => '2003-09-14 22:05:00',
);

$Self->True(
    $PendingTimeSet,
    "TicketPendingTimeSet() - Pending Time - set string",
);

%TicketPending = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

$PendingUntilTime = $TimeObject->TimeStamp2SystemTime(
    String => '2003-09-14 22:05:00',
);

$PendingUntilTime = $TimeObject->SystemTime() - $PendingUntilTime;

$Self->Is(
    $TicketPending{UntilTime},
    '-' . $PendingUntilTime,
    "TicketPendingTimeSet() - Pending Time - read back",
);

$PendingTimeSet = $TicketObject->TicketPendingTimeSet(
    TicketID => $TicketID,
    UserID   => 1,
    String   => '0000-00-00 00:00:00',
);

$Self->True(
    $PendingTimeSet,
    "TicketPendingTimeSet() - Pending Time - reset string",
);

%TicketPending = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->Is(
    $TicketPending{UntilTime},
    '0',
    "TicketPendingTimeSet() - Pending Time - not set",
);

$PendingTimeSet = $TicketObject->TicketPendingTimeSet(
    TicketID => $TicketID,
    UserID   => 1,
    String   => '2003-09-14 22:05:00',
);

$Self->True(
    $PendingTimeSet,
    "TicketPendingTimeSet() - Pending Time - set string",
);

my $TicketStateUpdate = $TicketObject->TicketStateSet(
    TicketID => $TicketID,
    UserID   => 1,
    State    => 'pending reminder',
);

%TicketPending = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->True(
    $TicketPending{UntilTime},
    "TicketPendingTimeSet() - Set to pending - time should still be there",
);

$TicketStateUpdate = $TicketObject->TicketStateSet(
    TicketID => $TicketID,
    UserID   => 1,
    State    => 'new',
);

%TicketPending = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

$Self->Is(
    $TicketPending{UntilTime},
    '0',
    "TicketPendingTimeSet() - Set to new - Pending Time not set",
);

# check that searches with NewerDate in the future are not executed
$Helper->FixedTimeAddSeconds( -60 * 60 );

# Test CreateTime (future date)
my $FutureTime = $TimeObject->SystemTime2TimeStamp(
    SystemTime => $TimeObject->SystemTime() + ( 60 * 60 ),
);
%TicketIDs  = $TicketObject->TicketSearch(
    Result                    => 'HASH',
    Limit                     => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CreateTime',
                Value => $FutureTime,
                Operator => 'GTE',
            },       
        ]
    },    
    UserID     => 1,
    Permission => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Ticket CreateTime >= now()+60 min)',
);

# Test ArticleCreateTime (future date)
%TicketIDs  = $TicketObject->TicketSearch(
    Result                     => 'HASH',
    Limit                      => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'ArticleCreateTime',
                Value => $FutureTime,
                Operator => 'GTE',
            },       
        ]
    },      
    UserID     => 1,
    Permission => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Article CreateTime >= now()+60 min)',
);

# Test CloseTime (future date)
%TicketIDs = $TicketObject->TicketSearch(
    Result                   => 'HASH',
    Limit                    => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'CloseTime',
                Value => $FutureTime,
                Operator => 'GTE',
            },       
        ]
    },       
    UserID     => 1,
    Permission => 'rw',
);
$Self->False(
    $TicketIDs{$TicketID},
    'TicketSearch() (HASH:Ticket CloseTime >= now()+60 min)',
);

# the ticket is no longer needed
$TicketObject->TicketDelete(
    TicketID => $TicketID,
    UserID   => 1,
);

# tests for searching StateTypes that might not have states
# this should return an empty list rather then a big SQL error
# the problem is, we can't really test if there is an SQL error or not
# ticket search returns an empty list anyway

my @NewStates = $StateObject->StateGetStatesByType(
    StateType => ['new'],
    Result    => 'ID',
);

# make sure we don't have valid states for state type new
for my $NewStateID (@NewStates) {
    my %State = $StateObject->StateGet(
        ID => $NewStateID,
    );
    $StateObject->StateUpdate(
        %State,
        ValidID => 2,
        UserID  => 1,
    );
}

my @TicketIDs = $TicketObject->TicketSearch(
    Result       => 'LIST',
    Limit        => 100,
    Filter       => {
        AND => [ 
            {
                Field => 'TicketNumber',
                Value => [ $Ticket{TicketNumber}, 'ABC' ],
                Operator => 'IN',
            },
            {
                Field => 'StateType',
                Value => 'New',
                Operator => 'EQ',
            },                    
        ]
    },        
    UserID       => 1,
    Permission   => 'rw',
);
$Self->False(
    $TicketIDs[0],
    'TicketSearch() (LIST:TicketNumber,StateType:new (no valid states of state type new)',
);

# activate states again
for my $NewStateID (@NewStates) {
    my %State = $StateObject->StateGet(
        ID => $NewStateID,
    );
    $StateObject->StateUpdate(
        %State,
        ValidID => 1,
        UserID  => 1,
    );
}

# check response of ticket search for invalid timestamps
for my $SearchParam (qw(ArticleCreateTime CreateTime PendingTime)) {
    for my $ParamOption (qw(LT GTE)) {
        $TicketObject->TicketSearch(
            Filter       => {
                AND => [ 
                    {
                        Field => $SearchParam,
                        Value => '2000-02-31 00:00:00',
                        Operator => $ParamOption,
                    },                
                ]
            },                   
            UserID                      => 1,
        );
        my $ErrorMessage = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
            Type => 'error',
            What => 'Message',
        );
        $Self->Is(
            $ErrorMessage,
            "Attribute module for $SearchParam returned an error!",
            "TicketSearch() (Handling invalid timestamp in '$SearchParam $ParamOption')",
        );
    }
}

# cleanup is done by RestoreDatabase but we need to delete the tickets to cleanup the filesystem too
my @DeleteTicketList = $TicketObject->TicketSearch(
    Result            => 'ARRAY',
    Filter       => {
        AND => [ 
            {
                Field => 'CustomerUserID',
                Value => 'unittest@otrs.com',
                Operator => 'EQ',
            },                
        ]
    },      
    UserID            => 1,
);
for my $TicketID (@DeleteTicketList) {
    $TicketObject->TicketDelete(
        TicketID => $TicketID,
        UserID   => 1,
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