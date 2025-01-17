# --
# Modified version of the work: Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-AGPL for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::User;

use strict;
use warnings;

use Crypt::PasswdMD5 qw(unix_md5_crypt apache_md5_crypt);
use Digest::SHA;
use Data::Dumper;
use Time::HiRes;

use Kernel::System::Role;
use Kernel::System::Role::Permission;
use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Config',
    'Cache',
    'CheckItem',
    'DB',
    'Encode',
    'Log',
    'Main',
    'Time',
    'Valid',
);

=head1 NAME

Kernel::System::User - user lib

=head1 SYNOPSIS

All user functions. E. g. to add and updated user and other functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $UserObject = $Kernel::OM->Get('User');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    # get user table
    $Self->{UserTable}       = $ConfigObject->Get('DatabaseUserTable')       || 'users';
    $Self->{UserTableUserID} = $ConfigObject->Get('DatabaseUserTableUserID') || 'id';
    $Self->{UserTableUserPW} = $ConfigObject->Get('DatabaseUserTableUserPW') || 'pw';
    $Self->{UserTableUser}   = $ConfigObject->Get('DatabaseUserTableUser')   || 'login';

    $Self->{CacheType} = 'User';
    $Self->{CacheTTL}  = 60 * 60 * 24 * 20;

    # set lower if database is case sensitive
    $Self->{Lower} = '';
    if ( $Kernel::OM->Get('DB')->GetDatabaseFunction('CaseSensitive') ) {
        $Self->{Lower} = 'LOWER';
    }

    $Self->{PermissionDebug} = $Kernel::OM->Get('Config')->Get('Permission::Debug');

    return $Self;
}

=item GetUserData()

get user data

    my %User = $UserObject->GetUserData(
        UserID => 123,
    );

    or

    my %User = $UserObject->GetUserData(
        User          => 'franz',
        Valid         => 1,       # not required -> 0|1 (default 0)
                                  # returns only data if user is valid
        NoOutOfOffice => 1,       # not required -> 0|1 (default 0)
                                  # returns data without out of office infos
        NoPreferences => 1,       # not required -> 0|1 (default 0)
                                  # returns data without preferences
    );

=cut

sub GetUserData {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{User} && !$Param{UserID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need User or UserID!',
        );
        return;
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    # check if result is cached
    if ( $Param{Valid} ) {
        $Param{Valid} = 1;
    }
    else {
        $Param{Valid} = 0;
    }
    if ( $Param{NoOutOfOffice} ) {
        $Param{NoOutOfOffice} = 1;
    }
    else {
        $Param{NoOutOfOffice} = 0;
    }
    if ( $Param{NoPreferences} ) {
        $Param{NoPreferences} = 1;
    }
    else {
        $Param{NoPreferences} = 0;
    }

    my $CacheKey;
    if ( $Param{User} ) {
        $CacheKey = join '::', 'GetUserData', 'User',
            $Param{User},
            $Param{Valid},
            $Param{NoOutOfOffice},
            $Param{NoPreferences};
    }
    else {
        $CacheKey = join '::', 'GetUserData', 'UserID',
            $Param{UserID},
            $Param{Valid},
            $Param{NoOutOfOffice},
            $Param{NoPreferences};
    }

    # check cache
    my $Cache = $Kernel::OM->Get('Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;

    # get initial data
    my @Bind;
    my $SQL = "SELECT $Self->{UserTableUserID}, $Self->{UserTableUser}, $Self->{UserTableUserPW},"
        . " comments, valid_id, create_time, change_time, create_by, change_by, is_agent, is_customer FROM $Self->{UserTable} WHERE ";

    if ( $Param{User} ) {
        my $User = lc $Param{User};
        $SQL .= " $Self->{Lower}($Self->{UserTableUser}) = ?";
        push @Bind, \$User;
    }
    else {
        $SQL .= " $Self->{UserTableUserID} = ?";
        push @Bind, \$Param{UserID};
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    return if !$DBObject->Prepare(
        SQL   => $SQL,
        Bind  => \@Bind,
        Limit => 1,
    );

    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Data{UserID}      = $Row[0];
        $Data{UserLogin}   = $Row[1];
        $Data{UserPw}      = $Row[2];
        $Data{UserComment} = $Row[3];
        $Data{ValidID}     = $Row[4];
        $Data{CreateTime}  = $Row[5];
        $Data{ChangeTime}  = $Row[6];
        $Data{CreateBy}    = $Row[7];
        $Data{ChangeBy}    = $Row[8];
        $Data{IsAgent}     = $Row[9];
        $Data{IsCustomer}  = $Row[10];
    }

    # set usage context
    $Data{UsageContext} = 0;
    if ( $Data{IsAgent} && $Data{IsCustomer} ) {
        $Data{UsageContext} = 3;
    }
    elsif ( $Data{IsCustomer} ) {
        $Data{UsageContext} = 2;
    }
    elsif ( $Data{IsAgent} ) {
        $Data{UsageContext} = 1;
    }

    # check data
    if ( !$Data{UserID} ) {
        if ( $Param{User} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'notice',
                Message  => "Panic! No UserData for user: '$Param{User}'!!!",
            );
            return;
        }
        else {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'notice',
                Message  => "Panic! No UserData for user id: '$Param{UserID}'!!!",
            );
            return;
        }
    }

    # Store CacheTTL locally so that we can reduce it for users that are out of office.
    my $CacheTTL = $Self->{CacheTTL};

    # check valid, return if there is locked for valid users
    if ( $Param{Valid} ) {

        my $Hit = 0;

        for ( $Kernel::OM->Get('Valid')->ValidIDsGet() ) {
            if ( $_ eq $Data{ValidID} ) {
                $Hit = 1;
            }
        }

        if ( !$Hit ) {

            # set cache
            $Kernel::OM->Get('Cache')->Set(
                Type  => $Self->{CacheType},
                TTL   => $CacheTTL,
                Key   => $CacheKey,
                Value => {},
            );
            return;
        }
    }

    # get preferences
    my %Preferences = $Self->GetPreferences( UserID => $Data{UserID} );

    my $TimeObject = $Kernel::OM->Get('Time');

    # out of office check
    if ( !$Param{NoOutOfOffice} ) {
        if ( $Preferences{OutOfOffice} ) {
            my $Time = $TimeObject->SystemTime();
            my $Start
                = "$Preferences{OutOfOfficeStartYear}-$Preferences{OutOfOfficeStartMonth}-$Preferences{OutOfOfficeStartDay} 00:00:00";
            my $TimeStart = $TimeObject->TimeStamp2SystemTime(
                String => $Start,
            );
            my $End
                = "$Preferences{OutOfOfficeEndYear}-$Preferences{OutOfOfficeEndMonth}-$Preferences{OutOfOfficeEndDay} 23:59:59";
            my $TimeEnd = $TimeObject->TimeStamp2SystemTime(
                String => $End,
            );
            if ( $TimeStart < $Time && $TimeEnd > $Time ) {
                my $OutOfOfficeMessageTemplate =
                    $ConfigObject->Get('OutOfOfficeMessageTemplate')
                    || '*** out of office until %s (%s d left) ***';
                my $TillDate = sprintf(
                    '%04d-%02d-%02d',
                    $Preferences{OutOfOfficeEndYear},
                    $Preferences{OutOfOfficeEndMonth},
                    $Preferences{OutOfOfficeEndDay}
                );
                my $Till = int( ( $TimeEnd - $Time ) / 60 / 60 / 24 );
                $Preferences{OutOfOfficeMessage}
                    = sprintf( $OutOfOfficeMessageTemplate, $TillDate, $Till );
            }

# Reduce CacheTTL to one hour for users that are out of office to make sure the cache expires timely
#   even if there is no update action.
            $CacheTTL = 60 * 60 * 1;
        }
    }

    if ( !$Param{NoPreferences} ) {

        # add last login timestamp
        if ( $Preferences{UserLastLogin} ) {
            $Preferences{UserLastLoginTimestamp} = $TimeObject->SystemTime2TimeStamp(
                SystemTime => $Preferences{UserLastLogin},
            );
        }

        # add preferences defaults
        my $Config = $ConfigObject->Get('PreferencesGroups');
        if ( $Config && ref $Config eq 'HASH' ) {

            KEY:
            for my $Key ( sort keys %{$Config} ) {

                next KEY if !defined $Config->{$Key}->{DataSelected};

                # check if data is defined
                next KEY if defined $Preferences{ $Config->{$Key}->{PrefKey} };

                # set default data
                $Preferences{ $Config->{$Key}->{PrefKey} } = $Config->{$Key}->{DataSelected};
            }
        }

        # add preferences to data hash
        $Data{Preferences} = \%Preferences;
    }

    # set cache
    $Kernel::OM->Get('Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $CacheTTL,
        Key   => $CacheKey,
        Value => \%Data,
    );

    return %Data;
}

=item UserAdd()

to add new users

    my $UserID = $UserObject->UserAdd(
        UserLogin     => 'mhuber',
        UserPw        => 'some-pass',           # optional
        UserComment   => 'some comment',        # optional
        ValidID       => 1,
        ChangeUserID  => 123,
        IsAgent       => 0 | 1                  # optional
        IsCustomer    => 0 | 1                  # optional
    );

=cut

sub UserAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(UserLogin ValidID ChangeUserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!",
            );
            return;
        }
    }

    # check if a user with this login (username) already exits
    if ( $Self->UserLoginExistsCheck( UserLogin => $Param{UserLogin} ) ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "A user with username '$Param{UserLogin}' already exists!"
        );
        return;
    }

    # check password
    if ( !$Param{UserPw} ) {
        $Param{UserPw} = $Self->GenerateRandomPassword();
    }

    $Param{IsAgent}
        = ( defined $Param{IsAgent} && IsInteger( $Param{IsAgent} ) ) ? $Param{IsAgent} : 0;
    $Param{IsCustomer}
        = ( defined $Param{IsCustomer} && IsInteger( $Param{IsCustomer} ) )
        ? $Param{IsCustomer}
        : 0;

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # Don't store the user's password in plaintext initially. It will be stored in a
    #   hashed version later with SetPassword().
    my $RandomPassword = $Self->GenerateRandomPassword();

    # sql
    return if !$DBObject->Do(
        SQL => "INSERT INTO $Self->{UserTable} "
            . " ( $Self->{UserTableUser}, $Self->{UserTableUserPW}, "
            . " comments, valid_id, create_time, create_by, change_time, change_by, is_agent, is_customer )"
            . " VALUES "
            . " (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?, ?, ?)",
        Bind => [
            \$Param{UserLogin}, \$RandomPassword, \$Param{UserComment}, \$Param{ValidID},
            \$Param{ChangeUserID}, \$Param{ChangeUserID}, \$Param{IsAgent}, \$Param{IsCustomer},
        ],
    );

    # get new user id
    my $UserLogin = lc $Param{UserLogin};
    return if !$DBObject->Prepare(
        SQL => "SELECT $Self->{UserTableUserID} FROM $Self->{UserTable} "
            . " WHERE $Self->{Lower}($Self->{UserTableUser}) = ?",
        Bind  => [ \$UserLogin ],
        Limit => 1,
    );

    # fetch the result
    my $UserID;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $UserID = $Row[0];
    }

    # check if user exists
    if ( !$UserID ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'notice',
            Message  => "Unable to create User: '$Param{UserLogin}' ($Param{ChangeUserID})!",
        );
        return;
    }

    # log notice
    $Kernel::OM->Get('Log')->Log(
        Priority => 'notice',
        Message =>
            "User: '$Param{UserLogin}' ID: '$UserID' created successfully ($Param{ChangeUserID})!",
    );

    # set password
    $Self->SetPassword(
        UserLogin => $Param{UserLogin},
        PW        => $Param{UserPw}
    );

    # generate personal access token
    $Self->TokenGenerate(
        UserID => $UserID,
    );

    # delete cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $Self->{CacheType},
    );

    # assign basic roles depending on context
    $Self->_AssignRolesByContext(
        UserID => $UserID
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'CREATE',
        Namespace => 'User',
        ObjectID  => $UserID,
    );

    return $UserID;
}

=item UserUpdate()

to update users

    $UserObject->UserUpdate(
        UserID        => 4321,
        UserLogin     => 'mhuber',
        UserPw        => 'some-pass',           # optional
        UserComment   => 'some comment',        # optional
        IsAgent       => 0 | 1,                 # optional
        IsCustomer    => 0 | 1,                 # optional
        ValidID       => 1,
        ChangeUserID  => 123,
    );

=cut

sub UserUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(UserID UserLogin ValidID ChangeUserID)) {

        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')
                ->Log( Priority => 'error', Message => "Need $_!" );
            return;
        }
    }

    # store old user login for later use
    my $OldUserLogin = $Self->UserLookup(
        UserID => $Param{UserID},
    );

    # check if a user with this login (username) already exists
    if (
        $Self->UserLoginExistsCheck(
            UserLogin => $Param{UserLogin},
            UserID    => $Param{UserID}
        )
        )
    {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "A user with username '$Param{UserLogin}' already exists!"
        );
        return;
    }
    $Param{IsAgent}
        = ( defined $Param{IsAgent} && IsInteger( $Param{IsAgent} ) ) ? $Param{IsAgent} : 0;
    $Param{IsCustomer}
        = ( defined $Param{IsCustomer} && IsInteger( $Param{IsCustomer} ) )
        ? $Param{IsCustomer}
        : 0;

    # update db
    return if !$Kernel::OM->Get('DB')->Do(
        SQL => "UPDATE $Self->{UserTable} SET "
            . " $Self->{UserTableUser} = ?, comments = ?, valid_id = ?, "
            . " change_time = current_timestamp, change_by = ? , is_customer = ?, is_agent = ?"
            . " WHERE $Self->{UserTableUserID} = ?",
        Bind => [
            \$Param{UserLogin},    \$Param{UserComment}, \$Param{ValidID},
            \$Param{ChangeUserID}, \$Param{IsCustomer},  \$Param{IsAgent},
            \$Param{UserID},
        ],
    );

    # check pw
    if ( $Param{UserPw} ) {
        $Self->SetPassword(
            UserLogin => $Param{UserLogin},
            PW        => $Param{UserPw}
        );
    }

    # generate token, if it doen't exist
    my %Preferences = $Self->GetPreferences(
        UserID => $Param{UserID},
    );
    if (!IsHashRefWithData(\%Preferences) || !$Preferences{UserToken} ) {
        $Self->TokenGenerate(
            UserID => $Param{UserID},
        );
    };

    # delete cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $Self->{CacheType},
    );

    # assign basic roles depending on context
    $Self->_AssignRolesByContext(
        UserID => $Param{UserID}
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'UPDATE',
        Namespace => 'User',
        ObjectID  => $Param{UserID},
    );

    return 1;
}

=item UserSearch()

to search users

    my %List = $UserObject->UserSearch(
        Search => '*some*', # also 'hans+huber' possible
        Valid  => 1, # not required
    );

    my %List = $UserObject->UserSearch(
        UserLogin => '*some*',
        Limit     => 50,
        Valid     => 1, # not required
    );

    my %List = $UserObject->UserSearch(
        UserLoginEquals => 'some',              # exact match
        Limit           => 50,
        Valid           => 1, # not required
    );

Returns hash of UserID, Login pairs:

    my %List = (
        1 => 'root@locahost',
        4 => 'admin',
        9 => 'joe',
    );

=cut

sub UserSearch {
    my ( $Self, %Param ) = @_;

    my %Users;
    my $Valid = $Param{Valid} // 1;

    # check needed stuff
    if ( !$Param{Search} && !$Param{UserLogin} && !$Param{UserLoginEquals}) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need Search or UserLogin or UserLoginEquals!',
        );
        return;
    }

    my $CacheKey
        = 'UserSearch::'
        . ( $Param{Search}    || '' ) . '::'
        . ( $Param{UserLogin} || '' ) . '::'
        . ( $Param{UserLoginEquals} || '' ) . '::'
        . ( $Param{Valid}     || '' ) . '::'
        . ( $Param{Limit}     || '' );

    # check cache
    my $Cache = $Kernel::OM->Get('Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # get like escape string needed for some databases (e.g. oracle)
    my $LikeEscapeString = $DBObject->GetDatabaseFunction('LikeEscapeString');

    # build SQL string
    my $SQL = "SELECT $Self->{UserTableUserID}, login FROM $Self->{UserTable} WHERE ";
    my @Bind;

    if ( $Param{Search} ) {

        my %QueryCondition = $DBObject->QueryCondition(
            Key      => [qw(login)],
            Value    => $Param{Search},
            BindMode => 1,
        );
        $SQL .= $QueryCondition{SQL} . ' ';
        push @Bind, @{ $QueryCondition{Values} };
    }
    elsif ( $Param{UserLogin} ) {

        $SQL .= " $Self->{Lower}($Self->{UserTableUser}) LIKE ? $LikeEscapeString";
        $Param{UserLogin} =~ s/\*/%/g;
        $Param{UserLogin} = $DBObject->Quote( $Param{UserLogin}, 'Like' );
        push @Bind, \$Param{UserLogin};
    }
    elsif ( $Param{UserLoginEquals} ) {

        $SQL .= " $Self->{UserTableUser} = ?";
        push @Bind, \$Param{UserLoginEquals};
    }

    # add valid option
    if ($Valid) {
        $SQL .= "AND valid_id IN ("
            . join( ', ', $Kernel::OM->Get('Valid')->ValidIDsGet() ) . ")";
    }

    # get data
    return if !$DBObject->Prepare(
        SQL   => $SQL,
        Bind  => \@Bind,
        Limit => $Param{Limit} || $Self->{UserSearchListLimit},
    );

    # fetch the result
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Users{ $Row[0] } = $Row[1];
    }

    # set cache
    $Kernel::OM->Get('Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \%Users,
    );

    return %Users;
}

=item SetPassword()

to set users passwords

    $UserObject->SetPassword(
        UserLogin => 'some-login',
        PW        => 'some-new-password'
    );

=cut

sub SetPassword {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{UserLogin} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need UserLogin!'
        );
        return;
    }

    # get old user data
    my %User = $Self->GetUserData( User => $Param{UserLogin} );
    if ( !$User{UserLogin} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'No such User!',
        );
        return;
    }

    my $Pw = $Param{PW} || '';
    my $CryptedPw = '';

    # get crypt type
    my $CryptType = $Kernel::OM->Get('Config')->Get('AuthModule::DB::CryptType') || 'sha2';

    # crypt plain (no crypt at all)
    if ( $CryptType eq 'plain' ) {
        $CryptedPw = $Pw;
    }

    # crypt with UNIX crypt
    elsif ( $CryptType eq 'crypt' ) {

        # encode output, needed by crypt() only non utf8 signs
        $Kernel::OM->Get('Encode')->EncodeOutput( \$Pw );
        $Kernel::OM->Get('Encode')->EncodeOutput( \$Param{UserLogin} );

        $CryptedPw = crypt( $Pw, $Param{UserLogin} );
    }

    # crypt with md5
    elsif ( $CryptType eq 'md5' || !$CryptType ) {

        # encode output, needed by unix_md5_crypt() only non utf8 signs
        $Kernel::OM->Get('Encode')->EncodeOutput( \$Pw );
        $Kernel::OM->Get('Encode')->EncodeOutput( \$Param{UserLogin} );

        $CryptedPw = unix_md5_crypt( $Pw, $Param{UserLogin} );
    }

    # crypt with md5 (compatible with Apache's .htpasswd files)
    elsif ( $CryptType eq 'apr1' ) {

        # encode output, needed by unix_md5_crypt() only non utf8 signs
        $Kernel::OM->Get('Encode')->EncodeOutput( \$Pw );
        $Kernel::OM->Get('Encode')->EncodeOutput( \$Param{UserLogin} );

        $CryptedPw = apache_md5_crypt( $Pw, $Param{UserLogin} );
    }

    # crypt with sha1
    elsif ( $CryptType eq 'sha1' ) {

        my $SHAObject = Digest::SHA->new('sha1');

        # encode output, needed by sha1_hex() only non utf8 signs
        $Kernel::OM->Get('Encode')->EncodeOutput( \$Pw );

        $SHAObject->add($Pw);
        $CryptedPw = $SHAObject->hexdigest();
    }

    # bcrypt
    elsif ( $CryptType eq 'bcrypt' ) {

        if ( !$Kernel::OM->Get('Main')->Require('Crypt::Eksblowfish::Bcrypt') ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message =>
                    "User: '$User{UserLogin}' tried to store password with bcrypt but 'Crypt::Eksblowfish::Bcrypt' is not installed!",
            );
            return;
        }

        my $Cost = 9;
        my $Salt = $Kernel::OM->Get('Main')->GenerateRandomString( Length => 16 );

        # remove UTF8 flag, required by Crypt::Eksblowfish::Bcrypt
        $Kernel::OM->Get('Encode')->EncodeOutput( \$Pw );

        # calculate password hash
        my $Octets = Crypt::Eksblowfish::Bcrypt::bcrypt_hash(
            {
                key_nul => 1,
                cost    => 9,
                salt    => $Salt,
            },
            $Pw
        );

        # We will store cost and salt in the password string so that it can be decoded
        #   in future even if we use a higher cost by default.
        $CryptedPw = "BCRYPT:$Cost:$Salt:" . Crypt::Eksblowfish::Bcrypt::en_base64($Octets);
    }

    # crypt with sha256 as fallback
    else {

        my $SHAObject = Digest::SHA->new('sha256');

        # encode output, needed by sha256_hex() only non utf8 signs
        $Kernel::OM->Get('Encode')->EncodeOutput( \$Pw );

        $SHAObject->add($Pw);
        $CryptedPw = $SHAObject->hexdigest();
    }

    # update db
    my $UserLogin = lc $Param{UserLogin};
    return if !$Kernel::OM->Get('DB')->Do(
        SQL => "UPDATE $Self->{UserTable} SET $Self->{UserTableUserPW} = ? "
            . " WHERE $Self->{Lower}($Self->{UserTableUser}) = ?",
        Bind => [ \$CryptedPw, \$UserLogin ],
    );

    # log notice
    $Kernel::OM->Get('Log')->Log(
        Priority => 'notice',
        Message  => "User: '$Param{UserLogin}' changed password successfully!",
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'UPDATE',
        Namespace => 'User',
        ObjectID  => $User{UserID},
    );

    return 1;
}

=item UserLookup()

user login or id lookup

    my $UserLogin = $UserObject->UserLookup(
        UserID => 1,
        Silent => 1, # optional, don't generate log entry if user was not found
    );

    my $UserID = $UserObject->UserLookup(
        UserLogin => 'some_user_login',
        Silent    => 1, # optional, don't generate log entry if user was not found
    );

=cut

sub UserLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{UserLogin} && !$Param{UserID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need UserLogin or UserID!'
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    if ( $Param{UserLogin} ) {

        # check cache
        my $CacheKey = 'UserLookup::ID::' . $Param{UserLogin};
        my $Cache    = $Kernel::OM->Get('Cache')->Get(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );
        return $Cache if $Cache;

        # build sql query
        my $UserLogin = lc $Param{UserLogin};

        return if !$DBObject->Prepare(
            SQL => "SELECT $Self->{UserTableUserID} FROM $Self->{UserTable} "
                . " WHERE $Self->{Lower}($Self->{UserTableUser}) = ?",
            Bind  => [ \$UserLogin ],
            Limit => 1,
        );

        # fetch the result
        my $ID;
        while ( my @Row = $DBObject->FetchrowArray() ) {
            $ID = $Row[0];
        }

        if ( !$ID ) {
            if ( !$Param{Silent} ) {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'error',
                    Message  => "No UserID found for '$Param{UserLogin}'!",
                );
            }
            return;
        }

        # set cache
        $Kernel::OM->Get('Cache')->Set(
            Type  => $Self->{CacheType},
            TTL   => $Self->{CacheTTL},
            Key   => $CacheKey,
            Value => $ID,
        );

        return $ID;
    }

    else {

        # check cache
        my $CacheKey = 'UserLookup::Login::' . $Param{UserID};
        my $Cache    = $Kernel::OM->Get('Cache')->Get(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );
        return $Cache if $Cache;

        # build sql query
        return if !$DBObject->Prepare(
            SQL => "SELECT $Self->{UserTableUser} FROM $Self->{UserTable} "
                . " WHERE $Self->{UserTableUserID} = ?",
            Bind  => [ \$Param{UserID} ],
            Limit => 1,
        );

        # fetch the result
        my $Login;
        while ( my @Row = $DBObject->FetchrowArray() ) {
            $Login = $Row[0];
        }

        if ( !$Login ) {
            if ( !$Param{Silent} ) {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'error',
                    Message  => "No UserLogin found for '$Param{UserID}'!",
                );
            }
            return;
        }

        # set cache
        $Kernel::OM->Get('Cache')->Set(
            Type  => $Self->{CacheType},
            TTL   => $Self->{CacheTTL},
            Key   => $CacheKey,
            Value => $Login,
        );

        return $Login;
    }
}

=item UserName()

get user name

    my $Name = $UserObject->UserName(
        UserLogin => 'some-login',
    );

    or

    my $Name = $UserObject->UserName(
        UserID => 123,
    );

=cut

sub UserName {
    my ( $Self, %Param ) = @_;

    my %User = $Self->GetUserData(%Param);

    return if !%User;
    return $User{Login};
}

=item UserList()

return a hash with all users

    my %List = $UserObject->UserList(
        Type          => 'Short', # Short|Long, default Short
        Valid         => 1,       # default 1
        NoOutOfOffice => 1,       # (optional) default 0
    );

=cut

sub UserList {
    my ( $Self, %Param ) = @_;

    my $Type = $Param{Type} || 'Short';

    # set valid option
    my $Valid = $Param{Valid} // 1;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    # get configuration for the full name order
    my $NoOutOfOffice = $Param{NoOutOfOffice} || 0;

    # check cache
    my $CacheKey = join '::', 'UserList', $Type, $Valid, $NoOutOfOffice, ($Param{Limit} ? $Param{Limit} : '');
    my $Cache = $Kernel::OM->Get('Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;

    my $SelectStr;
    if ( $Type eq 'Short' ) {
        $SelectStr = "u.$Self->{UserTableUserID}, u.$Self->{UserTableUser}";
    }
    else {
        $SelectStr
            = "u.$Self->{UserTableUserID}, c.last_name, c.first_name, u.$Self->{UserTableUser}";
    }

    my $SQL
        = "SELECT $SelectStr FROM $Self->{UserTable} u LEFT JOIN contact c ON u.id = c.user_id ";

    # sql query
    if ($Valid) {
        $SQL
            .= " WHERE u.valid_id IN ( ${\(join ', ', $Kernel::OM->Get('Valid')->ValidIDsGet())} )";
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    return if !$DBObject->Prepare(
        SQL   => $SQL,
        Limit => $Param{Limit},
    );

    # fetch the result
    my %UsersRaw;
    my %Users;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $UsersRaw{ $Row[0] } = \@Row;
    }

    if ( $Type eq 'Short' ) {
        for my $CurrentUserID ( sort keys %UsersRaw ) {
            $Users{$CurrentUserID} = $UsersRaw{$CurrentUserID}->[1];
        }
    }
    else {
        for my $CurrentUserID ( sort keys %UsersRaw ) {
            my @Data         = @{ $UsersRaw{$CurrentUserID} };
            my $UserFullname = $Kernel::OM->Get('Contact')->_ContactFullname(
                UserLogin => $Data[1],
                Firstname => $Data[2],
                Lastname  => $Data[3],
            );
            $Users{$CurrentUserID} = $UserFullname;
        }
    }

    # check vacation option
    if ( !$NoOutOfOffice ) {

        USERID:
        for my $UserID ( sort keys %Users ) {
            next USERID if !$UserID;

            my %User = $Self->GetUserData(
                UserID => $UserID,
            );
            if ( $User{Preferences}->{OutOfOfficeMessage} ) {
                $Users{$UserID} .= ' ' . $User{Preferences}->{OutOfOfficeMessage};
            }
        }
    }

    # set cache
    $Kernel::OM->Get('Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \%Users,
    );

    return %Users;
}

=item UserLoginExistsCheck()

return 1 if another user with this login (username) already exists

    $Exist = $UserObject->UserLoginExistsCheck(
        UserLogin => 'Some::UserLogin',
        UserID => 1, # optional
    );

=cut

sub UserLoginExistsCheck {
    my ( $Self, %Param ) = @_;

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    return if !$DBObject->Prepare(
        SQL =>
            "SELECT $Self->{UserTableUserID} FROM $Self->{UserTable} WHERE $Self->{UserTableUser} = ?",
        Bind => [ \$Param{UserLogin} ],
    );

    # fetch the result
    my $Flag;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        if ( !$Param{UserID} || $Param{UserID} ne $Row[0] ) {
            $Flag = 1;
        }
    }
    if ($Flag) {
        return 1;
    }
    return 0;
}

=item PermissionList()

return a list of all permission of a given user

    my %List = $UserObject->PermissionList(
        UserID => 123
        UsageContext => 'Agent'|'Customer',
        RoleID => 456,                           # optional, restrict result to this role
        Types  => [ 'Resource', 'Object' ],      # optional
        Valid  => 1                              # optional
    );

=cut

sub PermissionList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID!'
        );
        return;
    }

    # set default value
    my $Valid = $Param{Valid} ? 1 : 0;

    # check cache
    my $CacheKey
        = 'PermissionList::'
        . ( $Param{UserID} || '' ) . '::'
        . ( $Param{RoleID} || '' ) . '::'
        . ( $Param{UsageContext} || '' ) . '::'
        . $Valid . '::'
        . ( IsArrayRefWithData( $Param{Types} ) ? join( '::', @{ $Param{Types} } ) : '' );
    my $Cache = $Kernel::OM->Get('Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;

    # get all role ids of this user and usage context
    my @RoleIDs = $Self->RoleList(
        UserID       => $Param{UserID},
        UsageContext => $Param{UsageContext},
        Valid        => $Valid
    );

    return () if !@RoleIDs;

    # get all permissions from every valid role the user is assigned to
    my @Bind;

    my $SQL = 'SELECT id FROM role_permission WHERE role_id IN (' . (join(',', @RoleIDs)) . ')';

    if ( $Param{RoleID} ) {
        $SQL .= ' AND role_id = ?';
        push( @Bind, \$Param{RoleID} );
    }

    # filter specific permission types
    if ( IsArrayRefWithData( $Param{Types} ) ) {
        my %TypesMap = map { $_ => 1 } @{ $Param{Types} };
        my %PermissionTypeList = $Kernel::OM->Get('Role')->PermissionTypeList();
        my @PermissionTypeIDs;
        foreach my $ID ( sort keys %PermissionTypeList ) {
            next if !$TypesMap{ $PermissionTypeList{$ID} };
            push( @PermissionTypeIDs, $ID );
        }
        if (@PermissionTypeIDs) {
            $SQL .= ' AND type_id IN (' . join( ',', sort @PermissionTypeIDs ) . ')';
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind
    );

    # fetch the result
    my %Result;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Result{ $Row[0] } = $Row[1];
    }

    # resolve permissions for IDs
    foreach my $ID ( keys %Result ) {
        my %Permission = $Kernel::OM->Get('Role')->PermissionGet(
            ID => $ID
        );
        $Result{$ID} = \%Permission;
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

=item RoleList()

return a list of all roles of a given user

    my @RoleIDs = $UserObject->RoleList(
        UserID       => 123,                    # required
        UsageContext => 'Agent'|'Customer'      # optional, if not given, all assigned roles will be returned
        Valid        => 1,                      # optional
    );

=cut

sub RoleList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # set default value
    my $Valid = $Param{Valid} ? 1 : 0;

    # check cache
    my $CacheKey = 'RoleList::' . $Param{UserID} . '::' . $Valid . '::' . ($Param{UsageContext} || '');
    my $Cache    = $Kernel::OM->Get('Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return @{$Cache} if $Cache;

    # get user data
    my %UserData = $Self->GetUserData(
        UserID => $Param{UserID},
    );

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');
    my @Bind     = ();
    push @Bind, \$Param{UserID};

    # create sql
    my $SQL = 'SELECT u.role_id, r.usage_context FROM role_user u LEFT JOIN roles r ON r.id = u.role_id WHERE u.user_id = ?';

    if ( $Valid ) {
        $SQL .= ' AND valid_id = 1';
    }

    # get data
    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    # fetch the result
    my @Result;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        # check if this role is valid for the given usage context
        next if ( $Param{UsageContext} && ($Row[1] & Kernel::System::Role->USAGE_CONTEXT->{uc($Param{UsageContext})}) != Kernel::System::Role->USAGE_CONTEXT->{uc($Param{UsageContext})} );

        push(@Result, $Row[0]);
    }

    # set cache
    $Kernel::OM->Get('Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \@Result,
    );

    return @Result;
}

=item CheckResourcePermission()

returns true if the requested permission is granted

    my ($Granted, $ResultingPermission) = $UserObject->CheckResourcePermission(
        UserID              => 123,                     # required
        UsageContext        => 'Agent'|'Customer'       # required
        Target              => '/tickets',              # required
        RequestedPermission => 'READ'                   # required
    );

=cut

sub CheckResourcePermission {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    foreach my $Key ( qw(UserID UsageContext Target RequestedPermission) ) {
        if ( !$Param{$Key} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Key!"
            );
            return;
        }
    }

    # UserID 1 has God Mode without SecureMode ;)
    return ( 1, Kernel::System::Role::Permission::PERMISSION_CRUD )
        if ( !$Kernel::OM->Get('Config')->Get('SecureMode') && $Param{UserID} == 1 );

    my $StartTime;
    if ( $Self->{PermissionDebug} ) {
        $StartTime = Time::HiRes::time();
        $Self->_PermissionDebug($Self->{LevelIndent}, "checking $Param{RequestedPermission} permission for target $Param{Target}");

        if ( !IsHashRefWithData($Self->{PermissionCheckRoleList}) ) {
            # get list of all roles to resolve names
            $Self->{PermissionCheckRoleList} = { $Kernel::OM->Get('Role')->RoleList( Valid => 1 ) };
        }
    }

    if(!$Self->{PermissionCheckUserRoleList}->{$Param{UserID}}) {
        $Self->{PermissionCheckUserRoleList}->{$Param{UserID}} = ();
    }

    if ( !IsArrayRefWithData($Self->{PermissionCheckUserRoleList}->{$Param{UserID}} ) ) {
        # get all roles the user is assigned to
        my @UserRoleList = $Self->RoleList(
            UserID       => $Param{UserID},
            UsageContext => $Param{UsageContext},
            Valid        => 1,
        );
        $Self->{PermissionCheckUserRoleList}->{$Param{UserID}} = \@UserRoleList;

        if ( $Self->{PermissionDebug} ) {
            $Self->_PermissionDebug($Self->{LevelIndent}, "active roles assigned to UserID $Param{UserID}: " . join(', ', map { '"'.($Self->{PermissionCheckRoleList}->{$_} || '')."\" (ID $_)" } sort @{$Self->{PermissionCheckUserRoleList}->{$Param{UserID}}}));
        }
    }

    if(!$Self->{PermissionCheckUserRolePermissionList}->{$Param{UserID}}) {
        $Self->{PermissionCheckUserRolePermissionList}->{$Param{UserID}} = {};
    }

    if ( !IsHashRefWithData($Self->{PermissionCheckUserRolePermissionList}->{$Param{UserID}} ) ) {
        my %PermissionList = $Self->PermissionList(
            UserID   => $Param{UserID},
            Types    => ['Resource'],
            UserType => $Param{UserType}
        );
        foreach my $Permission ( values %PermissionList ) {
            $Self->{PermissionCheckUserRolePermissionList}->{$Param{UserID}}->{$Permission->{RoleID}}->{$Permission->{ID}} = $Permission;
        }
    }

    # check the permission for each target level (from top to bottom) and role
    my $ResultingPermission;
    my $Target;
    TARGETPART:
    foreach my $TargetPart ( split( /\//, $Param{Target} ) ) {
        next if !$TargetPart;

        # save parent for history
        my $ParentTarget = $Target;

        $Target .= "/$TargetPart";

        my $TargetPermission;
        ROLEID:
        foreach my $RoleID ( sort @{ $Self->{PermissionCheckUserRoleList}->{$Param{UserID}} } ) {
            my ( $RoleGranted, $RolePermission ) = $Self->_CheckResourcePermissionForRole(
                %Param,
                Target   => $Target,
                RoleID   => $RoleID,
                UserType => $Param{UserType}
            );

            # use parent permission if no permissions have been found
            if ( !defined $RolePermission && $ParentTarget ) {
                $RolePermission = $Self->{PermissionCache}->{$Param{UserID}}->{$ParentTarget}->{$RoleID};
                $Self->{PermissionCache}->{$Param{UserID}}->{$Target}->{$RoleID} = $RolePermission;
                $Self->_PermissionDebug($Self->{LevelIndent}, "no permissions found for role \"$Self->{PermissionCheckRoleList}->{$RoleID}\" on target $Target, using parent permission");
            }

            # init the value
            if ( !defined $TargetPermission ) {
                $TargetPermission = 0;
            }

            # combine permissions
            $TargetPermission |= ( $RolePermission || 0 );
        }

        # if we don't have a target permission don't try to use it
        next TARGETPART if !defined $TargetPermission;

        # combine permissions
        if ( defined $ResultingPermission ) {

            # only if we have READ upto here, we can expand(!) the permissions
            if ( $ResultingPermission
                && Kernel::System::Role::Permission::PERMISSION->{READ}
                == Kernel::System::Role::Permission::PERMISSION->{READ}
                && $TargetPermission > $ResultingPermission )
            {
                $ResultingPermission |= ( $TargetPermission || 0 );
            }
            else {
                # no READ no expansion
                $ResultingPermission &= ( $TargetPermission || 0 );
            }
        }
        else {
            $ResultingPermission = ( $TargetPermission || 0 );
        }

        if ( $Self->{PermissionDebug} ) {
            my $ResultingPermissionShort
                = $Kernel::OM->Get('Role')->GetReadablePermissionValue(
                Value  => $ResultingPermission,
                Format => 'Short'
                );

            $Self->_PermissionDebug($Self->{LevelIndent}, "resulting permission on target $Target: $ResultingPermissionShort");
        }
    }

    if ( $Self->{PermissionDebug} ) {
        my $TimeDiff = ( Time::HiRes::time() - $StartTime ) * 1000;
        $Self->_PermissionDebug($Self->{LevelIndent}, sprintf( "permission check on target $Target took %i ms", $TimeDiff ) );
    }

    # check if we have a DENY
    return 0
        if !defined $ResultingPermission
        || ( $ResultingPermission & Kernel::System::Role::Permission::PERMISSION->{DENY} )
        == Kernel::System::Role::Permission::PERMISSION->{DENY};

    my $Granted
        = ( $ResultingPermission
            & Kernel::System::Role::Permission::PERMISSION->{ $Param{RequestedPermission} } )
        == Kernel::System::Role::Permission::PERMISSION->{ $Param{RequestedPermission} };

    return ( $Granted, $ResultingPermission );
}

=item _CheckResourcePermissionForRole()

returns true if the requested permission is granted for a given role

    my ($Granted, $ResultingPermission) = $UserObject->_CheckResourcePermissionForRole(
        UserID              => 123,
        RoleID              => 456,
        Target              => '/tickets',
        RequestedPermission => 'READ'
    );

=cut

sub _CheckResourcePermissionForRole {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    foreach my $Key (qw(UserID RoleID Target RequestedPermission)) {
        if ( !$Param{$Key} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Key!"
            );
            return;
        }
    }

    # UserID 1 has God Mode ;)
    return ( 1, Kernel::System::Role::Permission::PERMISSION_CRUD )
        if ( !$Kernel::OM->Get('Config')->Get('SecureMode') && $Param{UserID} == 1 );

    if ( $Self->{PermissionDebug} ) {
        $Self->_PermissionDebug($Self->{LevelIndent}, "checking $Param{RequestedPermission} permission for role \"$Self->{PermissionCheckRoleList}->{$Param{RoleID}}\" on target $Param{Target}");
    }

    if ( exists $Self->{PermissionCache}->{$Param{UserID}}->{$Param{Target}}->{$Param{RequestedPermission}}->{$Param{RoleID}} ) {

        if ( IsArrayRefWithData($Self->{PermissionCache}->{$Param{UserID}}->{$Param{Target}}->{$Param{RequestedPermission}}->{$Param{RoleID}}) ) {
            my $Granted = $Self->{PermissionCache}->{$Param{UserID}}->{$Param{Target}}->{$Param{RequestedPermission}}->{$Param{RoleID}}->[0] ? 'granted' : 'denied';
            if ( $Self->{PermissionDebug} ) {
                $Self->_PermissionDebug($Self->{LevelIndent}, "using cache for role \"$Self->{PermissionCheckRoleList}->{$Param{RoleID}}\" on target $Param{Target}: $Param{RequestedPermission} = $Granted");
            }
        }
        elsif ( $Self->{PermissionDebug} ) {
            $Self->_PermissionDebug($Self->{LevelIndent}, "using cache for role \"$Self->{PermissionCheckRoleList}->{$Param{RoleID}}\" on target $Param{Target}: $Param{RequestedPermission} = denied by explicit DENY");
        }
    }

    my $Result = 0;
    my %RelevantPermissions;
    foreach my $ID ( sort keys %{$Self->{PermissionCheckUserRolePermissionList}->{$Param{UserID}}->{$Param{RoleID}}} ) {
        my $Permission = $Self->{PermissionCheckUserRolePermissionList}->{$Param{UserID}}->{$Param{RoleID}}->{$ID};

        # prepare target
        my $Target = $Permission->{Target};
        $Target =~ s/\//\\\//g;
        $Target =~ s/\*/(\\w|\\d)+?/g;

        # check if permission target matches the target to be checked (check whole resources)
        next if $Param{Target} !~ /^$Target$/;

        $RelevantPermissions{$ID} = $Permission;
    }

    $Self->_PermissionDebug($Self->{LevelIndent}, "relevant permissions for role \"$Self->{PermissionCheckRoleList}->{$Param{RoleID}}\" on target $Param{Target}: " . Dumper( \%RelevantPermissions ) );

    # return if no relevant permissions exist
    if ( !IsHashRefWithData( \%RelevantPermissions ) ) {
        if ( $Self->{PermissionDebug} ) {
            my $ResultingPermissionShort
                = $Kernel::OM->Get('Role')->GetReadablePermissionValue(
                Value  => 0,
                Format => 'Short'
                );
            $Self->_PermissionDebug($Self->{LevelIndent}, "no relevant permissions found, returning");
        }

        return 0;
    }

    # sum up all the relevant permissions
    my $ResultingPermission = 0;
    foreach my $ID ( sort { length( $RelevantPermissions{$a}->{Target} ) <=> length( $RelevantPermissions{$b}->{Target} ) } keys %RelevantPermissions ) {
        my $Permission = $RelevantPermissions{$ID};
        $ResultingPermission |= $Permission->{Value};
        if ( ( $ResultingPermission & Kernel::System::Role::Permission::PERMISSION->{DENY} )
            == Kernel::System::Role::Permission::PERMISSION->{DENY} )
        {
            if ( $Self->{PermissionDebug} ) {
                $Self->_PermissionDebug($Self->{LevelIndent},
                    "DENY in permission ID $Permission->{ID} for role $Param{RoleID} on target \"$Permission->{Target}\""
                        . ( $Permission->{Comment} ? "(Comment: $Permission->{Comment})" : '' ) );
            }
            last;
        }
    }

    # check if we have a DENY already
    return ( 0, Kernel::System::Role::Permission::PERMISSION->{DENY} )
        if ( $ResultingPermission & Kernel::System::Role::Permission::PERMISSION->{DENY} )
        == Kernel::System::Role::Permission::PERMISSION->{DENY};

    if ( $Self->{PermissionDebug} ) {
        my $ResultingPermissionShort
            = $Kernel::OM->Get('Role')->GetReadablePermissionValue(
            Value  => $ResultingPermission,
            Format => 'Short'
            );

        $Self->_PermissionDebug($Self->{LevelIndent}, "resulting permissions for role \"$Self->{PermissionCheckRoleList}->{$Param{RoleID}}\" on target $Param{Target}: $ResultingPermissionShort");
    }

    # check if we have a DENY
    if ( ( $ResultingPermission & Kernel::System::Role::Permission::PERMISSION->{DENY} ) == Kernel::System::Role::Permission::PERMISSION->{DENY} ) {
        $Self->{PermissionCache}->{$Param{UserID}}->{$Param{Target}}->{$Param{RequestedPermission}}->{$Param{RoleID}} = 0;
        return 0;
    }

    my $Granted
        = ( $ResultingPermission
            & Kernel::System::Role::Permission::PERMISSION->{ $Param{RequestedPermission} } )
        == Kernel::System::Role::Permission::PERMISSION->{ $Param{RequestedPermission} };

    $Self->{PermissionCache}->{$Param{UserID}}->{$Param{Target}}->{$Param{RequestedPermission}}->{$Param{RoleID}} = [ $Granted, $ResultingPermission ];
    $Self->{PermissionCache}->{$Param{UserID}}->{$Param{Target}}->{$Param{RoleID}} = $ResultingPermission;

    return ( $Granted, $ResultingPermission );
}

=item GenerateRandomPassword()

generate a random password

    my $Password = $UserObject->GenerateRandomPassword();

    or

    my $Password = $UserObject->GenerateRandomPassword(
        Size => 16,
    );

=cut

sub GenerateRandomPassword {
    my ( $Self, %Param ) = @_;

    # generated passwords are eight characters long by default.
    my $Size = $Param{Size} || 8;

    my $Password = $Kernel::OM->Get('Main')->GenerateRandomString(
        Length => $Size,
    );

    return $Password;
}

=item SetPreferences()

set user preferences

    $UserObject->SetPreferences(
        Key    => 'UserComment',
        Value  => 'some comment',
        UserID => 123,
    );

=cut

sub SetPreferences {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Key UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # get current setting
    my %User = $Self->GetUserData(
        UserID        => $Param{UserID},
        NoOutOfOffice => 1,
    );

    # no updated needed
    return 1
        if defined $User{ $Param{Key} }
        && defined $Param{Value}
        && $User{ $Param{Key} } eq $Param{Value};

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    # get user preferences config
    my $GeneratorModule = $ConfigObject->Get('User::PreferencesModule')
        || 'Kernel::System::User::Preferences::DB';

    # get generator preferences module
    my $PreferencesObject = $Kernel::OM->Get($GeneratorModule);

    # set preferences
    return $PreferencesObject->SetPreferences(%Param);
}

=item GetUserLanguage()

get user preferences

    my $Language = $UserObject->GetUserLanguage(
        UserID => 123,
    );

=cut

sub GetUserLanguage {
    my ( $Self, %Param ) = @_;

    return if (!$Param{UserID});

    my %Preferences = $Self->GetPreferences(
        UserID => $Param{UserID},
    );

    return $Preferences{UserLanguage};
}

=item GetPreferences()

get user preferences

    my %Preferences = $UserObject->GetPreferences(
        UserID => 123,
    );

=cut

sub GetPreferences {
    my ( $Self, %Param ) = @_;

    # get user preferences config
    my $GeneratorModule = $Kernel::OM->Get('Config')->Get('User::PreferencesModule')
        || 'Kernel::System::User::Preferences::DB';

    # get generator preferences module
    my $PreferencesObject = $Kernel::OM->Get($GeneratorModule);

    return $PreferencesObject->GetPreferences(%Param);
}

=item DeletePreferences()

delete a user preference

    my $Succes = $UserObject->DeletePreferences(
        UserID => 123,
        Key    => 'some pref key',
    );

=cut

sub DeletePreferences {
    my $Self = shift;

    # get user preferences config
    my $GeneratorModule = $Kernel::OM->Get('Config')->Get('User::PreferencesModule')
        || 'Kernel::System::User::Preferences::DB';

    # get generator preferences module
    my $PreferencesObject = $Kernel::OM->Get($GeneratorModule);

    return $PreferencesObject->DeletePreferences(@_);
}

=item SearchPreferences()

search in user preferences

    my %UserList = $UserObject->SearchPreferences(
        Key   => 'UserLogin',
        Value => 'some_name',   # optional, limit to a certain value/pattern
    );

=cut

sub SearchPreferences {
    my $Self = shift;

    # get user preferences config
    my $GeneratorModule = $Kernel::OM->Get('Config')->Get('User::PreferencesModule')
        || 'Kernel::System::User::Preferences::DB';

    # get generator preferences module
    my $PreferencesObject = $Kernel::OM->Get($GeneratorModule);

    return $PreferencesObject->SearchPreferences(@_);
}

=item TokenGenerate()

generate a random token

    my $Token = $UserObject->TokenGenerate(
        UserID => 123,
    );

=cut

sub TokenGenerate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Need UserID!"
        );
        return;
    }
    my $Token = $Kernel::OM->Get('Main')->GenerateRandomString(
        Length => 15,
    );

    # save token in preferences
    $Self->SetPreferences(
        Key    => 'UserToken',
        Value  => $Token,
        UserID => $Param{UserID},
    );

    return $Token;
}

=item TokenCheck()

check password token

    my $Valid = $UserObject->TokenCheck(
        Token  => $Token,
        UserID => 123,
    );

=cut

sub TokenCheck {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Token} || !$Param{UserID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need Token and UserID!'
        );
        return;
    }

    # get preferences token
    my %Preferences = $Self->GetPreferences(
        UserID => $Param{UserID},
    );

    # check requested vs. stored token
    if ( $Preferences{UserToken} && $Preferences{UserToken} eq $Param{Token} ) {

        # reset password token
        $Self->SetPreferences(
            Key    => 'UserToken',
            Value  => '',
            UserID => $Param{UserID},
        );

        # return true if token is valid
        return 1;
    }

    # return false if token is invalid
    return;
}

sub _AssignRolesByContext {
    my ( $Self, %Param ) = @_;

    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID!'
        );
        return;
    }

    my %User = $Self->GetUserData(
        UserID => $Param{UserID}
    );
    return if !%User;

    my $RoleObject = $Kernel::OM->Get('Role');

    # get system roles and create lookup
    my %SystemRoles = $RoleObject->RoleList(Valid => 1);
    my %SystemRolesReverse = reverse %SystemRoles;

    # get user roles
    my %UserRoleList = map {$_ => 1} ( $Self->RoleList(
        UserID => $Param{UserID},
        Valid  => 1,
    ) );
    my %UserRoleListCurrent = %UserRoleList;

    $UserRoleList{ $SystemRolesReverse{'Agent User'} } = ( $User{IsAgent} && $SystemRolesReverse{'Agent User'} ) ? 1 : 0;
    $UserRoleList{ $SystemRolesReverse{'Customer'} } = ( $User{IsCustomer} && $SystemRolesReverse{'Customer'} ) ? 1 : 0;

    ROLEID:
    foreach my $RoleID ( sort keys %UserRoleList ) {
        if ( $UserRoleList{$RoleID} && !$UserRoleListCurrent{$RoleID} ) {
            # assign role
            my $Result = $RoleObject->RoleUserAdd(
                AssignUserID  => $Param{UserID},
                RoleID        => $RoleID,
                UserID        => 1,
            );
            if ( !$Result ) {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'error',
                    Message  => "User: '$User{UserLogin}' unable to assign role \"$SystemRoles{$RoleID}\"!",
                );
            }
            else {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'info',
                    Message  => "User: '$User{UserLogin}' assigned role \"$SystemRoles{$RoleID}\"!",
                );
            }
        }
        elsif ( !$UserRoleList{$RoleID} && $UserRoleListCurrent{$RoleID} ) {
            # revoke role
            my $Result = $RoleObject->RoleUserDelete(
                UserID => $Param{UserID},
                RoleID => $RoleID,
            );
            if ( !$Result ) {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'error',
                    Message  => "User: '$User{UserLogin}' unable to revoke role \"$SystemRoles{$RoleID}\"!",
                );
            }
            else {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'info',
                    Message  => "User: '$User{UserLogin}' revoked role \"$SystemRoles{$RoleID}\"!",
                );
            }
        }
    }

    return 1;
}

sub _PermissionDebug {
    my ( $Self, $Indent, $Message ) = @_;

    return if ( !$Kernel::OM->Get('Config')->Get('Permission::Debug') );

    $Indent ||= '';

    printf STDERR "(%5i) %-15s %s%s\n", $$, "[Permission]", $Indent, $Message;
}

=end Internal:

=cut

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-AGPL for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
