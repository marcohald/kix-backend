# --
# Copyright (C) 2006-2018 c.a.p.e. IT GmbH, http://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Console::Command::List',
    'Kernel::System::Main',
    'Kernel::System::Log',
);

=head1 NAME

Kernel::System::Console - handle console commands

=head1 SYNOPSIS

Log file functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item Run()

execute a command. Returns the shell status code to be used by exit().

    my $StatusCode = $ConsoleObject->Run( @ARGV );

=cut

sub Run {
    my ( $Self, @CommandlineArguments ) = @_;

    my $CommandName;

    # always disable cache debugging
    $Kernel::OM->Get('Kernel::Config')->Set(Key => 'Cache::Debug', Value => 0);

    # Catch bash completion calls
    if ( $ENV{COMP_LINE} ) {
        $CommandName = 'Kernel::System::Console::Command::Internal::BashCompletion';
        return $Kernel::OM->Get($CommandName)->Execute(@CommandlineArguments);
    }

    # If we don't have any arguments OR the first argument is an option and not a command name,
    #   show the overview screen instead.
    if ( !@CommandlineArguments || substr( $CommandlineArguments[0], 0, 2 ) eq '--' ) {
        $CommandName = 'Kernel::System::Console::Command::List';
        return $Kernel::OM->Get($CommandName)->Execute(@CommandlineArguments);
    }

    # Ok, let's try to find the command.
    $CommandName = 'Kernel::System::Console::Command::' . $CommandlineArguments[0];

    if ( $Kernel::OM->Get('Kernel::System::Main')->Require( $CommandName, Silent => 1 ) ) {

        # Regular case: everything was ok, execute command.
        # Remove first parameter (command itself) to not confuse further parsing
        shift @CommandlineArguments;
        return $Kernel::OM->Get($CommandName)->Execute(@CommandlineArguments);
    }

    # If the command cannot be found/loaded, also show the overview screen.
    my $CommandObject = $Kernel::OM->Get('Kernel::System::Console::Command::List');
    $CommandObject->PrintError("Could not find $CommandName.\n\n");
    $CommandObject->Execute();
    return 127;    # EXIT_CODE_COMMAND_NOT_FOUND, see http://www.tldp.org/LDP/abs/html/exitcodes.html
}

=item CommandGet()

returns information about the command (description + parameters)

    my @Commands = $CommandObject->CommandGet(
        Command => 'Maint::Cache::Delete'
    );

returns

    (
        Description => '...',
        Parameters  => [
            {...}
            {...}
        ]
    )

=cut

sub CommandGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Command)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my $CommandName = $Param{Command};
    if ( $CommandName !~ /^Kernel::System::Console::Command::/ ) {
        $CommandName = 'Kernel::System::Console::Command::' . $CommandName;
    }

    # get command object
    my $CommandObject = $Kernel::OM->Get($CommandName);

    if ( !$CommandObject ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Console command $Param{Command} not found!"
        );
        return;
    }

    my @Options;

    if ( IsArrayRefWithData($CommandObject->{_Options}) ) {
        @Options = @{$CommandObject->{_Options}};
    }
    if ( IsArrayRefWithData($CommandObject->{_GlobalOptions}) ) {
        @Options = ( @Options, @{$CommandObject->{_GlobalOptions}} );
    }

    # special handling for regexp options
    my @ValidOptions;
    foreach my $Option ( @Options ) {
        next if $Option->{Invisible};
        my %OptionClone = %{$Option};
        delete $OptionClone{ValueRegex};
        push @ValidOptions, \%OptionClone;
    }   
    
    my @Arguments;
    if ( IsArrayRefWithData($CommandObject->{_Arguments}) ) {
        @Arguments = @{$CommandObject->{_Arguments}};
    }
    
    # special handling for regexp arguments
    my @ValidArguments;
    foreach my $Arg ( @Arguments ) {
        my %ArgClone = %{$Arg};
        delete $ArgClone{ValueRegex};     
        push @ValidArguments, \%ArgClone;
    }   

    $Param{Command} =~ s/Kernel::System::Console::Command:://;

    my %Command = (
        Command        => $Param{Command},
        Description    => $CommandObject->Description(),
        AdditionalHelp => $Kernel::OM->Get($CommandName)->AdditionalHelp(),
        Parameters     => \@ValidOptions,
        Arguments      => \@ValidArguments,
    );

    return %Command;
}

=item CommandList()

returns all available commands, sorted first by directory and then by file name.

    my @Commands = $CommandObject->CommandList();

returns

    (
        'Kernel::System::Command::Help',
        'Kernel::System::Command::List',
        ...
    )

=cut

sub CommandList {
    my ( $Self, %Param ) = @_;

    my $Home = $Kernel::OM->Get('Kernel::Config')->Get('Home');

    my @Folders = ( $Home . '/Kernel/System/Console/Command' );
    foreach my $TmpDir (@INC) {
        last if $TmpDir =~ /\/Custom$/;
        my $NewDir = $TmpDir."/Kernel/System/Console/Command";
        next if !( -e $NewDir );
        push @Folders, $NewDir;
    }

    my @CommandFiles = ();
    for my $CommandDirectory (@Folders) {

        my @CommandFilesTmp = $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
            Directory => $CommandDirectory,
            Filter    => '*.pm',
            Recursive => 1,
        );

        @CommandFiles = ( @CommandFiles, @CommandFilesTmp );
    }

    my @Commands;

    COMMAND_FILE:
    for my $CommandFile (@CommandFiles) {
        next COMMAND_FILE if ( $CommandFile =~ m{/Internal/}xms );
        $CommandFile =~ s{^.*(Kernel/System.*)[.]pm$}{$1}xmsg;
        $CommandFile =~ s{/+}{::}xmsg;
        push @Commands, $CommandFile;
    }

    # Sort first by directory, then by File
    my $Sort = sub {
        my ( $DirA, $FileA ) = split( /::(?=[^:]+$)/smx, $a );
        my ( $DirB, $FileB ) = split( /::(?=[^:]+$)/smx, $b );
        return $DirA cmp $DirB || $FileA cmp $FileB;
    };

    @Commands = sort $Sort @Commands;

    return @Commands;
}

=item FileList()

get list of console files

    my %List = $ConsoleObject->FileList();

=cut

sub FileList {
    my ( $Self, %Param ) = @_;
    my @FileList;

    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    my $FileDir = $Kernel::OM->Get('Kernel::Config')->Get('Console::FilePath');

    my @Files = $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
        Directory => $FileDir,
        Filter    => '*',
        Recursive => 1,
    );

    foreach my $File ( sort @Files ) {
        next if $File =~ /\.gitkeep/;        
        next if ! -f $File;

        my $Filename = $File;
        $Filename =~ s{$FileDir/}{}g;

        my $Stat = $Kernel::OM->Get('Kernel::System::Main')->FileStat(
            Location => $File,
        );

        if ( !$Stat ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Unable to stat file $File!",
            );
            return;
        }

        my $MD5sum = $Kernel::OM->Get('Kernel::System::Main')->MD5sum(
            String => $Filename
        );

        my %File = (
            ID             => $MD5sum,
            Filename       => $Filename,
            AccessTimeUnix => $Stat->atime(),
            AccessTime     => $TimeObject->SystemTime2TimeStamp( SystemTime => $Stat->atime()),
            CreateTimeUnix => $Stat->ctime(),
            CreateTime     => $TimeObject->SystemTime2TimeStamp( SystemTime => $Stat->ctime()),
            ModifyTimeUnix => $Stat->mtime(),
            ModifyTime     => $TimeObject->SystemTime2TimeStamp( SystemTime => $Stat->mtime()),
        );

        # rename Filesize to FilesizeRaw
        $File{FilesizeRaw} = 0 + $Stat->size();

        # human readable file size
        if ( $File{FilesizeRaw} ) {
            if ( $File{FilesizeRaw} > ( 1024 * 1024 ) ) {
                $File{Filesize} = sprintf "%.1f MBytes", ( $File{FilesizeRaw} / ( 1024 * 1024 ) );
            }
            elsif ( $File{FilesizeRaw} > 1024 ) {
                $File{Filesize} = sprintf "%.1f KBytes", ( ( $File{FilesizeRaw} / 1024 ) );
            }
            else {
                $File{Filesize} = $File{FilesizeRaw} . ' Bytes';
            }
        }

        push @FileList, \%File;
    }

    return @FileList;
}

=item FileDelete()

delete console file

    my %Console = $ConsoleObject->FileDelete(
        ID        => '...'           # required
    );

=cut

sub FileDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(ID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my %FileList = map { $_->{MD5sum} = $_ } $Self->FileList();

    my $FileDir = $Kernel::OM->Get('Kernel::Config')->Get('Console::FilePath');

    my $Result = $Kernel::OM->Get('Kernel::System::Main')->FileDelete(
        Location => $FileDir.'/'.$FileList{$Param{ID}}->{Filename}
    );

    return $Result;
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