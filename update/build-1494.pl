#!/usr/bin/perl
# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

use File::Basename;
use FindBin qw($Bin);
use lib dirname($Bin).'/';
use lib dirname($Bin).'/Kernel/cpan-lib';

use Getopt::Std;
use File::Path qw(mkpath);

use Kernel::System::ObjectManager;

use Kernel::System::VariableCheck qw(:all);

# create object manager
local $Kernel::OM = Kernel::System::ObjectManager->new(
    'Log' => {
        LogPrefix => 'framework_update-to-build-1494',
    },
);

use vars qw(%INC);

# add filter to notifaction for new ticket
_addFilterToNewCustomerTicket();

sub _addFilterToNewCustomerTicket {

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    my %Notification = $Kernel::OM->Get('NotificationEvent')->NotificationGet(
        Name => 'Customer - New Ticket Receipt'
    );

    if( %Notification ) {

        # add sender type filter if necessary
        $Notification{Filter} = {} if ( !IsHashRefWithData( $Notification{Filter} ) );
        $Notification{Filter}->{AND} = [] if ( !IsArrayRefWithData( $Notification{Filter}->{AND} ) );

        my $FoundFilter;
        for my $Filter ( @{ $Notification{Filter}->{AND} } ) {
            $FoundFilter = 1 if ( IsHashRefWithData($Filter) && $Filter->{Field} eq 'SenderTypeID');
        }

        if (!$FoundFilter) {
            my $SenderTypeID = $Kernel::OM->Get('Ticket')->ArticleSenderTypeLookup(
                SenderType => 'external'
            );
            if ($SenderTypeID) {
                push(@{ $Notification{Filter}->{AND} }, {
                    Field    => 'SenderTypeID',
                    Operator => 'IN',
                    Type     => 'NUMERIC',
                    Value    => [
                        $SenderTypeID
                    ]
                });

                $Kernel::OM->Get('NotificationEvent')->NotificationUpdate(
                    ID => $Notification{ID},
                    %Notification,
                    UserID => 1
                )
            }
        }
    }

    return 1;
}

exit 0;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
