# --
# Copyright (C) 2006-2018 c.a.p.e. IT GmbH, http://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console::Command::Maint::Cache::ShowStats;

use strict;
use warnings;

use base qw(Kernel::System::Console::BaseCommand);

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::Cache',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Shows statistics about the systems cache.');

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get cache object
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    my $CacheStats = $CacheObject->GetCacheStats();

    if (!IsHashRefWithData($CacheStats)) {
        $Self->Print("<yellow>No cache statistics are available.</yellow>\n");
        return $Self->ExitCodeOk();
    }

    $Self->Print("<white></white>\n");

    my $Line = '-------------------------------------------------------------------------------------------';
    printf("%-50s %10s %10s %10s %10s\n", 'Cache Type', '#Items', '#Access', '#Hits', 'Hitrate');
    printf("%.50s %.10s %.10s %.10s %.10s\n", $Line, $Line, $Line, $Line, $Line );

    my %Totals = (
        Items => 0,
        Access => 0,
        Hits => 0,
    );
    foreach my $Type (sort keys %{$CacheStats}) {
        my $StatsItem = $CacheStats->{$Type};

        my $Hitrate = ($StatsItem->{AccessCount} && $StatsItem->{HitCount}) ? $StatsItem->{HitCount} / $StatsItem->{AccessCount} * 100 : 0;
        $Totals{Items}  += $StatsItem->{KeyCount};
        $Totals{Access} += $StatsItem->{AccessCount} ? $StatsItem->{AccessCount} : 0;
        $Totals{Hits}   += $StatsItem->{HitCount} ? $StatsItem->{HitCount} : 0;

        printf("%-50s %10i %10i %10i %10i\n", $Type, $StatsItem->{KeyCount}, $StatsItem->{AccessCount} ? $StatsItem->{AccessCount} : 0, $StatsItem->{HitCount} ? $StatsItem->{HitCount} : 0, $Hitrate );
    }
    printf("%.50s %.10s %.10s %.10s %.10s\n", $Line, $Line, $Line, $Line, $Line );
    printf("%-50s %10i %10i %10i %10i\n\n", 'TOTAL', $Totals{Items}, $Totals{Access}, $Totals{Hits}, $Totals{Access} ? $Totals{Hits} / $Totals{Access} * 100 : 0 );

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
