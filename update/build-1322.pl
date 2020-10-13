#!/usr/bin/perl
# --
# Copyright (C) 2006-2020 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

use File::Basename;
use FindBin qw($Bin);
use lib dirname($Bin);
use lib dirname($Bin) . '/Kernel/cpan-lib';

use Getopt::Std;

use Kernel::System::ObjectManager;
use Kernel::System::VariableCheck qw(:all);

# create object manager
local $Kernel::OM = Kernel::System::ObjectManager->new(
    'Log' => {
        LogPrefix => 'framework_update-to-build-1322',
    },
);
my $LogObject = $Kernel::OM->Get('Log');

use vars qw(%INC);

# updates permissions for role Customer
_UpdatePermissionsForRoleSystemAdmin();

sub _UpdatePermissionsForRoleSystemAdmin {
    # get database object
    my $DBObject = $Kernel::OM->Get('DB');
    my $RoleObject = $Kernel::OM->Get('Role');

    my %RoleList           = reverse $RoleObject->RoleList();
    my %PermissionTypeList = reverse $RoleObject->PermissionTypeList();

    my @PermissionUpdates = (
        {
            Permission => {
                Role   => 'System Admin',
                Type   => 'Resource',
                Target => '/organisations'
            },
            Change => {
                Value => 6,
            }
        }
    );

    foreach my $Update ( @PermissionUpdates ) {
        my $RoleID = $RoleList{$Update->{Permission}->{Role}};
        if (!$RoleID) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => 'Unable to find role "'.$Update->{Permission}->{Role}.'"!'
            );
            next;
        }
        my $PermissionTypeID = $PermissionTypeList{$Update->{Permission}->{Type}};
        if (!$PermissionTypeID) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => 'Unable to find permission type "'.$Update->{Permission}->{Type}.'"!'
            );
            next;
        }

        my $PermissionID = $RoleObject->PermissionLookup(
            RoleID => $RoleID,
            TypeID => $PermissionTypeID,
            Target => $Update->{Permission}->{Target}
        );

        # Update existing permission
        if($PermissionID) {
            my $Success = $RoleObject->PermissionUpdate(
                ID     => $PermissionID,
                UserID => 1,
                %{$Update->{Change}}
            );

            if (!$Success) {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'error',
                    Message  => "Unable to update permission (role=$Update->{Permission}->{Role}, type=$Update->{Permission}->{Type}, target=$Update->{Permission}->{Target})!"
                );
            }
            else {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'info',
                    Message  => "Updated permission ID $PermissionID!"
                );
            }
        } else {
            # create permission
            my $Success = $RoleObject->PermissionAdd(
                RoleID     => $RoleID,
                TypeID     => $PermissionTypeID,
                Target     => $Update->{Permission}->{Target},
                Value      => $Update->{Change}->{Value},
                UserID => 1
            );

            if (!$Success) {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'error',
                    Message  => "Unable to create permission (role=$Update->{Permission}->{Role}, type=$Update->{Permission}->{Type}, target=$Update->{Permission}->{Target})!"
                );
            }
        }
    }

    # delete whole cache
    $Kernel::OM->Get('Cache')->CleanUp();

    return 1;
}

exit 0;

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
