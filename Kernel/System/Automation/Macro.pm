# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Automation::Macro;

use strict;
use warnings;

use Digest::MD5;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Config',
    'Cache',
    'DB',
    'Log',
    'User',
    'Valid',
);

=head1 NAME

Kernel::System::Automation::Macro - macro extension for automation lib

=head1 SYNOPSIS

All macro functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item MacroLookup()

get id for macro name

    my $MacroID = $AutomationObject->MacroLookup(
        Name => '...',
    );

get name for macro id

    my $MacroName = $AutomationObject->MacroLookup(
        ID => '...',
    );

=cut

sub MacroLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Name} && !$Param{ID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Got no Name or ID!',
        );
        return;
    }

    # get macro list
    my %MacroList = $Self->MacroList(
        Valid => 0,
    );

    return $MacroList{ $Param{ID} } if $Param{ID};

    # create reverse list
    my %MacroListReverse = reverse %MacroList;

    return $MacroListReverse{ $Param{Name} };
}

=item MacroGet()

returns a hash with the macro data

    my %MacroData = $AutomationObject->MacroGet(
        ID => 2,
    );

This returns something like:

    %MacroData = (
        'ID'         => 2,
        'Type'       => 'Ticket',
        'Name'       => 'Test'
        'ExecOrder'  => [],
        'Comment'    => '...',
        'ValidID'    => '1',
        'CreateTime' => '2010-04-07 15:41:15',
        'CreateBy'   => 1,
        'ChangeTime' => '2010-04-07 15:41:15',
        'ChangeBy'   => 1
    );

=cut

sub MacroGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need ID!'
        );
        return;
    }

    # check cache
    my $CacheKey = 'MacroGet::' . $Param{ID};
    my $Cache    = $Kernel::OM->Get('Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;

    return if !$Kernel::OM->Get('DB')->Prepare(
        SQL   => "SELECT id, name, type, exec_order, comments, valid_id, create_time, create_by, change_time, change_by FROM macro WHERE id = ?",
        Bind => [ \$Param{ID} ],
    );

    my %Result;

    # fetch the result
    while ( my @Row = $Kernel::OM->Get('DB')->FetchrowArray() ) {
        %Result = (
            ID         => $Row[0],
            Name       => $Row[1],
            Type       => $Row[2],
            ExecOrder  => $Row[3],
            Comment    => $Row[4],
            ValidID    => $Row[5],
            CreateTime => $Row[6],
            CreateBy   => $Row[7],
            ChangeTime => $Row[8],
            ChangeBy   => $Row[9],
        );

        # prepare ExecOrder
        my @ExecOrder = map {0 + $_} split(/,/, ($Result{ExecOrder} || ''));
        $Result{ExecOrder} = \@ExecOrder;
    }

    # no data found...
    if ( !%Result ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Macro with ID $Param{ID} not found!",
        );
        return;
    }

    # set cache
    $Kernel::OM->Get('Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \%Result,
    );

    return %Result;
}

=item MacroAdd()

adds a new macro

    my $ID = $AutomationObject->MacroAdd(
        Name       => 'test',
        Type       => 'Ticket',
        Comment    => '...',                                   # optional
        ValidID    => 1,                                       # optional
        UserID     => 123,
    );

=cut

sub MacroAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Name Type UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # set default value
    $Param{ValidID} //= 1;
    $Param{Comment} ||= '';

    # check if this is a duplicate after the change
    my $ID = $Self->MacroLookup(
        Name => $Param{Name},
    );
    if ( $ID ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "A macro with the same name already exists.",
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # insert
    return if !$DBObject->Do(
        SQL => 'INSERT INTO macro (name, type, comments, valid_id, create_time, create_by, change_time, change_by) '
             . 'VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$Param{Name}, \$Param{Type}, \$Param{Comment}, \$Param{ValidID}, \$Param{UserID}, \$Param{UserID}
        ],
    );

    # get new id
    return if !$DBObject->Prepare(
        SQL  => 'SELECT id FROM macro WHERE name = ?',
        Bind => [
            \$Param{Name},
        ],
    );

    # fetch the result
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $ID = $Row[0];
    }

    # delete cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $Self->{CacheType},
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'CREATE',
        Namespace => 'Macro',
        ObjectID  => $ID,
    );

    return $ID;
}

=item MacroUpdate()

updates a macro

    my $Success = $AutomationObject->MacroUpdate(
        ID         => 123,
        Name       => 'test'                                    # optional
        Type       => 'Ticket',                                 # optional
        ExecOrder  => [],                                       # optional
        Comment    => '...',                                    # optional
        ValidID    => 1,                                        # optional
        UserID     => 123,
    );

=cut

sub MacroUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(ID UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!",
            );
            return;
        }
    }

    # get current data
    my %Data = $Self->MacroGet(
        ID => $Param{ID},
    );

    return if (!IsHashRefWithData(\%Data));

    # check if this is a duplicate after the change
    if ($Param{Name}) {
        my $ID = $Self->MacroLookup(
            Name => $Param{Name},
        );
        if ( $ID && $ID != $Param{ID} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "A macro with the same name already exists.",
            );
            return;
        }
    } else {
        $Param{Name} = $Data{Name};
    }

    # set default value
    $Param{Comment} //= $Data{Comment};
    $Param{Type}    ||= $Data{Type};
    $Param{ValidID} //= $Data{ValidID};

    # check if update is required
    my $ChangeRequired;
    KEY:
    for my $Key ( qw(Type Name Comment ValidID) ) {

        next KEY if defined $Param{$Key} && $Data{$Key} eq $Param{$Key};

        $ChangeRequired = 1;

        last KEY;
    }

    my $ExecOrder;
    if ( ref $Param{ExecOrder} eq 'ARRAY') {
        $ExecOrder = join(',', @{$Param{ExecOrder}});
        if ( $ExecOrder ne join(',', @{ $Data{ExecOrder} || [] }) ) {
            $ChangeRequired = 1;
        }
    } else {
        $ExecOrder = join(',', @{ $Data{ExecOrder} || [] });
    }

    return 1 if !$ChangeRequired;

    # update Macro in database
    return if !$Kernel::OM->Get('DB')->Do(
        SQL => 'UPDATE macro SET type = ?, name = ?, exec_order = ?, comments = ?, valid_id = ?, change_time = current_timestamp, change_by = ? WHERE id = ?',
        Bind => [
            \$Param{Type}, \$Param{Name}, \$ExecOrder, \$Param{Comment}, \$Param{ValidID}, \$Param{UserID}, \$Param{ID}
        ],
    );

    # delete cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $Self->{CacheType},
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'UPDATE',
        Namespace => 'Macro',
        ObjectID  => $Param{ID},
    );

    return 1;
}

=item MacroList()

returns a hash of all macros

    my %Macros = $AutomationObject->MacroList(
        Valid => 1          # optional
        Type  => 'Ticket'   # optional
    );

the result looks like

    %Macros = (
        1 => 'test',
        2 => 'dummy',
        3 => 'domesthing'
    );

=cut

sub MacroList {
    my ( $Self, %Param ) = @_;

    # set default value
    my $Valid = $Param{Valid} ? 1 : 0;

    # create cache key
    my $CacheKey = 'MacroList::' . $Valid;

    # read cache
    my $Cache = $Kernel::OM->Get('Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;

    my $SQL = 'SELECT id, name FROM macro';

    my @Bind;
    if ( $Param{Valid} ) {
        $SQL .= ' WHERE valid_id = 1'
    }
    if ( $Param{Type} ) {
        $SQL .= $Param{Valid} ? ' AND type = ?' : ' WHERE type = ?';
        push(@Bind, \$Param{Type});
    }

    return if !$Kernel::OM->Get('DB')->Prepare(
        SQL  => $SQL,
        Bind => \@Bind
    );

    my %Result;
    while ( my @Row = $Kernel::OM->Get('DB')->FetchrowArray() ) {
        $Result{$Row[0]} = $Row[1];
    }

    # set cache
    $Kernel::OM->Get('Cache')->Set(
        Type  => $Self->{CacheType},
        Key   => $CacheKey,
        Value => \%Result,
        TTL   => $Self->{CacheTTL},
    );

    return %Result;
}

=item MacroDelete()

deletes a macro

    my $Success = $AutomationObject->MacroDelete(
        ID => 123,
    );

=cut

sub MacroDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(ID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # check if this macro exists
    my $ID = $Self->MacroLookup(
        ID => $Param{ID},
    );
    if ( !$ID ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "A macro with the ID $Param{ID} does not exist.",
        );
        return;
    }

    # delete macro actions
    return if !$Kernel::OM->Get('DB')->Prepare(
        SQL  => 'DELETE FROM macro_action WHERE macro_id = ?',
        Bind => [ \$Param{ID} ],
    );

    # delete relations with Jobs
    return if !$Kernel::OM->Get('DB')->Prepare(
        SQL  => 'DELETE FROM job_macro WHERE macro_id = ?',
        Bind => [ \$Param{ID} ],
    );

    # delete macro
    return if !$Kernel::OM->Get('DB')->Prepare(
        SQL  => 'DELETE FROM macro WHERE id = ?',
        Bind => [ \$Param{ID} ],
    );

    # delete cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $Self->{CacheType},
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'DELETE',
        Namespace => 'Macro',
        ObjectID  => $Param{ID},
    );

    return 1;

}

=item MacroIsExecutable()

checks if a macro is executable. Return 0 or 1.

    my $Result = $AutomationObject->MacroIsExecutable(
        ID       => 123,        # the ID of the macro
        UserID    => 1
    );

=cut

sub MacroIsExecutable {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(ID UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # get Macro data
    my %Macro = $Self->MacroGet(
        ID => $Param{ID}
    );

    if ( !%Macro ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "No such macro with ID $Param{ID}!"
        );
        return;
    }

    return IsArrayRefWithData($Macro{ExecOrder});
}

=item MacroExecute()

executes a macro

    my $Success = $AutomationObject->MacroExecute(
        ID            => 123,        # the ID of the macro
        ObjectID      => 123,        # the ID of the object to execute the macro onto
        UserID        => 1
    );

=cut

sub MacroExecute {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(ID UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # init ObjectID with a numeric value if given
    $Param{ObjectID} = 0 if !$Param{ObjectID};

    # init call stack
    $Self->{ParentMacroID} //= [];

    # add IDs for log reference
    if ( $Self->{MacroID} ) {
        push @{$Self->{ParentMacroID}}, $Self->{MacroID};
    }
    else {
        $Self->{MacroResults} = {};
    }

    $Self->{MacroID}  = $Param{ID};
    $Self->{ObjectID} = $Param{ObjectID};

    # keep root object id
    $Self->{RootObjectID} = $Param{RootObjectID} || $Param{ObjectID};

    # get Macro data
    my %Macro = $Self->MacroGet(
        ID => $Param{ID}
    );

    if ( !%Macro ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "No such macro with ID $Param{ID}!"
        );
        return;
    }

    if ( !IsArrayRefWithData($Macro{ExecOrder}) ) {
        $Self->LogInfo(
            Message  => "Macro \"$Macro{Name}\" has no executable actions. Aborting macro execution.",
            UserID   => $Param{UserID},
        );
        return 1;
    }

    $Self->LogInfo(
        Message  => "executing macro \"$Macro{Name}\" with ".(scalar(@{$Macro{ExecOrder}}))." macro actions on ObjectID $Param{ObjectID}.",
        UserID   => $Param{UserID},
    );

    # load type backend module
    my $BackendObject = $Self->_LoadMacroTypeBackend(
        Name => $Macro{Type},
    );
    return if !$BackendObject;

    # add variable referrer data
    $BackendObject->{MacroID}      = $Param{ID};
    $BackendObject->{ObjectID}     = $Param{ObjectID};
    $BackendObject->{RootObjectID} = $Self->{RootObjectID};

    my $CacheType = Digest::MD5::md5_hex(
        ($Self->{JobID} ? $Self->{JobID} : '') . '::' .
        ($Self->{RunID} ? $Self->{RunID} : '') . '::' .
        $Self->{MacroID}
    );

    # clear result variable cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $CacheType
    );

    my $Success = $BackendObject->Run(
        ObjectID  => $Param{ObjectID},
        ExecOrder => $Macro{ExecOrder},
        UserID    => $Param{UserID},

        # FIXME: add instance if job was triggerd by event with new instance (ExecuteJobsForEvent)
        AutomationInstance => $Self
    );

    # remove result variable cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $CacheType
    );

    # remove IDs from log reference
    $Self->{MacroID} = pop @{$Self->{ParentMacroID}};
    delete $Self->{ObjectID};

    return $Success;
}

sub _LoadMacroTypeBackend {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Name)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # load type backend
    $Self->{MacroTypeModules} //= {};

    if ( !$Self->{MacroTypeModules}->{$Param{Name}} ) {

        # load backend modules
        my $Backends = $Kernel::OM->Get('Config')->Get('Automation::MacroType');

        if ( !IsHashRefWithData($Backends) ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "No macro backend modules found!",
            );
            return;
        }

        my $Backend = $Backends->{$Param{Name}}->{Module};

        if ( !$Kernel::OM->Get('Main')->Require($Backend) ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Unable to require $Backend!"
            );
            return;
        }

        my $BackendObject = $Backend->new( %{$Self} );
        if ( !$BackendObject ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Unable to create instance of $Backend!"
            );
            return;
        }

        # add referrer data
        $BackendObject->{JobID}   = $Self->{JobID};
        $BackendObject->{RunID}   = $Self->{RunID};

        $Self->{MacroTypeModules}->{$Param{Name}} = $BackendObject;
    }

    return $Self->{MacroTypeModules}->{$Param{Name}};
}

=item MacroLogList()

returns a list of all logs items for a given macro

    my @Logs = $AutomationObject->MacroLogList(
        MacroID => 123
    );

=cut

sub MacroLogList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(MacroID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # create cache key
    my $CacheKey = 'MacroLogList::' . $Param{MacroID};

    # read cache
    my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return @{$Cache} if $Cache;

    return if !$Kernel::OM->Get('Kernel::System::DB')->Prepare( 
        SQL  => 'SELECT id, job_id, run_id, macro_id, macro_action_id, object_id, priority, message, create_time, create_by FROM automation_log WHERE macro_id = ?',
        Bind => [ \$Param{MacroID} ]
    );

    my $Data = $Kernel::OM->Get('Kernel::System::DB')->FetchAllArrayRef(
        Columns => [ 'ID', 'JobID', 'RunID', 'MacroID', 'MacroActionID', 'ObjectID', 'Priority', 'Message', 'CreateTime', 'CreateBy' ],
    );

    # data found...
    my @Result;
    if ( IsArrayRefWithData($Data) ) {
        @Result = @{$Data};
    }

    # set cache
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        Key   => $CacheKey,
        Value => \@Result,
        TTL   => $Self->{CacheTTL},
    );

    return @Result;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-GPL3 for license information (GPL3). If you did not receive this file, see

<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut
