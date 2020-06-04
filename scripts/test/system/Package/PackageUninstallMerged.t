# --
# Modified version of the work: Copyright (C) 2006-2020 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-AGPL for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# get needed objects
my $ConfigObject  = $Kernel::OM->Get('Config');
my $PackageObject = $Kernel::OM->Get('Package');

# get KIX Version
my $KIXVersion = $ConfigObject->Get('Version');

# leave only major and minor level versions
$KIXVersion =~ s{ (\d+ \. \d+) .+ }{$1}msx;

# add x as patch level version
$KIXVersion .= '.x';

# find out if it is an developer installation with files
# from the version control system.
my $DeveloperSystem = 0;
my $Home            = $ConfigObject->Get('Home');
my $Version         = $ConfigObject->Get('Version');
if (
    !-e $Home . '/ARCHIVE'
    && $Version =~ m{git}
    )
{
    $DeveloperSystem = 1;
}

# check #13 doesn't work on developer systems because there is no ARCHIVE file!
if ( !$DeveloperSystem ) {

    # install package normally
    my $String = '<?xml version="1.0" encoding="utf-8" ?>
    <kix_package version="1.0">
      <Name>Test</Name>
      <Version>0.0.1</Version>
      <Vendor>c.a.p.e. IT GmbH</Vendor>
      <URL>http://www.cape-it.de/</URL>
      <License>GNU GENERAL PUBLIC LICENSE Version 2, June 1991</License>
      <ChangeLog>2005-11-10 New package (some test &lt; &gt; &amp;).</ChangeLog>
      <Description Lang="en">A test package (some test &lt; &gt; &amp;).</Description>
      <Description Lang="de">Ein Test Paket (some test &lt; &gt; &amp;).</Description>
      <ModuleRequired Version="1.112">Encode</ModuleRequired>
      <Framework>' . $KIXVersion . '</Framework>
      <BuildDate>2005-11-10 21:17:16</BuildDate>
      <BuildHost>yourhost.example.com</BuildHost>
      <Filelist>
        <File Location="Test" Permission="644" Encode="Base64">aGVsbG8K</File>
        <File Location="var/Test" Permission="644" Encode="Base64">aGVsbG8K</File>
      </Filelist>
    </kix_package>
    ';
    my $PackageInstall = $PackageObject->PackageInstall( String => $String );

    # check that the package is installed and files exists
    $Self->True(
        $PackageInstall,
        'PackageInstall() - package installed with true',
    );
    for my $File (qw( Test var/Test )) {
        my $RealFile = $Home . '/' . $File;
        $RealFile =~ s/\/\//\//g;
        $Self->True(
            -e $RealFile,
            "FileExists - $RealFile with true",
        );
    }

    # modify the installed package including one framework file, this will simulate that the
    # package was installed before feature merge into the framework, the idea is that the package
    # will be uninstalled, the not framework files will be removed and the framework files will
    # remain
    $String = '<?xml version="1.0" encoding="utf-8" ?>
    <kix_package version="1.0">
      <Name>Test</Name>
      <Version>0.0.1</Version>
      <Vendor>c.a.p.e. IT GmbH</Vendor>
      <URL>http://www.cape-it.de/</URL>
      <License>GNU GENERAL PUBLIC LICENSE Version 2, June 1991</License>
      <ChangeLog>2005-11-10 New package (some test &lt; &gt; &amp;).</ChangeLog>
      <Description Lang="en">A test package (some test &lt; &gt; &amp;).</Description>
      <Description Lang="de">Ein Test Paket (some test &lt; &gt; &amp;).</Description>
      <ModuleRequired Version="1.112">Encode</ModuleRequired>
      <Framework>' . $KIXVersion . '</Framework>
      <BuildDate>2005-11-10 21:17:16</BuildDate>
      <BuildHost>yourhost.example.com</BuildHost>
      <Filelist>
        <File Location="Test" Permission="644" Encode="Base64">aGVsbG8K</File>
        <File Location="var/Test" Permission="644" Encode="Base64">aGVsbG8K</File>
        <File Location="bin/kix.CheckSum.pl" Permission="755" Encode="Base64">aGVsbG8K</File>
      </Filelist>
    </kix_package>
    ';
    my $PackageName = 'Test';

    # the modifications has to be at DB level, otherwise a .save file will be generated for the
    # framework file, and we are trying to prevent it
    $Kernel::OM->Get('DB')->Do(
        SQL => '
            UPDATE package_repository
            SET content = ?
            WHERE name = ?',
        Bind => [ \$String, \$PackageName ],
    );

    my $Content = 'Test 12345678';

    # now create an .save file for the framework file, content doesn't matter as it will be deleted
    my $Write = $Kernel::OM->Get('Main')->FileWrite(
        Location   => $Home . '/bin/kix.CheckSum.pl.save',
        Content    => \$Content,
        Mode       => 'binmode',
        Permission => '644',
    );
    $Self->True(
        $Write,
        '#FileWrite() - bin/kix.CheckSum.pl.save',
    );

    # create PackageObject again to make sure cache is cleared
    my $PackageObject = Kernel::System::Package->new( %{$Self} );

    # run PackageUninstallMerged()
    my $Success = $PackageObject->_PackageUninstallMerged( Name => $PackageName );
    $Self->True(
        $Success,
        "_PackageUninstallMerged() - Executed with true",
    );

    # check that the original files from the package does not exist anymore
    # these files are suppose to be old files that are not required anymore by the merged package
    for my $File (qw( Test var/Test bin/kix.CheckSum.pl.save )) {
        my $RealFile = $Home . '/' . $File;
        $RealFile =~ s/\/\//\//g;
        $Self->False(
            -e $RealFile,
            "FileExists - $RealFile with false",
        );
    }

    # check that the framework file still exists
    for my $File (qw( bin/kix.CheckSum.pl )) {
        my $RealFile = $Home . '/' . $File;
        $RealFile =~ s/\/\//\//g;
        $Self->True(
            -e $RealFile,
            "FileExists - $RealFile with true",
        );
    }

    # check that the package is uninstalled
    my $PackageInstalled = $PackageObject->PackageIsInstalled(
        Name => $PackageName,
    );
    $Self->False(
        $PackageInstalled,
        'PackageIsInstalled() - with false',
    );
}

# cleanup cache
$Kernel::OM->Get('Cache')->CleanUp();

1;



=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-AGPL for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
