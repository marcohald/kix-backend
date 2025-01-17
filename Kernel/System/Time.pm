# --
# Modified version of the work: Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-AGPL for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Time;

use strict;
use warnings;

use Time::Local;
use DateTime;
use DateTime::TimeZone;
use Date::Pcalc qw(Add_Delta_YMDHMS);

use Kernel::System::VariableCheck qw( :all );

our @ObjectDependencies = (
    'Config',
    'Cache',
    'Log',
);

=head1 NAME

Kernel::System::Time - time functions

=head1 SYNOPSIS

This module is managing time functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create a time object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $TimeObject = $Kernel::OM->Get('Time');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # 0=off; 1=on;
    $Self->{Debug} = 0;

    $Self->{TimeZone} = $Param{TimeZone}
        || $Param{UserTimeZone}
        || $Kernel::OM->Get('Config')->Get('TimeZone')
        || 'Etc/UTC';   # fallback

    $Self->{TimeSecDiff} = 0;
    if ( lc $Self->{TimeZone} ne 'local' ) {
        my $TimeZoneObject   = DateTime::TimeZone->new(name => $Self->{TimeZone});
        $Self->{TimeSecDiff} = $TimeZoneObject->offset_for_datetime(DateTime->now);     # time zone offset in seconds
    }

    $Self->{CacheObject} = $Kernel::OM->Get('Cache');
    $Self->{CacheType}   = 'Time';

    return $Self;
}

=item SystemTime()

returns the number of non-leap seconds since what ever time the
system considers to be the epoch (that's 00:00:00, January 1, 1904
for Mac OS, and 00:00:00 UTC, January 1, 1970 for most other systems).

This will the time that the server considers to be the local time (based on
time zone configuration) plus the configured KIX "TimeZone" diff (only recommended
for systems running in UTC).

    my $SystemTime = $TimeObject->SystemTime();

=cut

sub SystemTime {
    my $Self = shift;

    return time() + $Self->{TimeSecDiff};
}

=item SystemTime2TimeStamp()

returns a time stamp for a given system time in "yyyy-mm-dd 23:59:59" format.

    my $TimeStamp = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $SystemTime,
    );

If you need the short format "23:59:59" for dates that are "today",
pass the Type parameter like this:

    my $TimeStamp = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $SystemTime,
        Type       => 'Short',
    );

=cut

sub SystemTime2TimeStamp {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !defined $Param{SystemTime} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need SystemTime!',
        );
        return;
    }

    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $Self->SystemTime2Date(%Param);
    if ( $Param{Type} && $Param{Type} eq 'Short' ) {
        my ( $CSec, $CMin, $CHour, $CDay, $CMonth, $CYear ) = $Self->SystemTime2Date(
            SystemTime => $Self->SystemTime(),
        );
        if ( $CYear == $Year && $CMonth == $Month && $CDay == $Day ) {
            return "$Hour:$Min:$Sec";
        }
        return "$Year-$Month-$Day $Hour:$Min:$Sec";
    }
    return "$Year-$Month-$Day $Hour:$Min:$Sec";
}

=item CurrentTimestamp()

returns a time stamp of the local system time (see L<SystemTime()>)
in "yyyy-mm-dd 23:59:59" format.

    my $TimeStamp = $TimeObject->CurrentTimestamp();

=cut

sub CurrentTimestamp {
    my ( $Self, %Param ) = @_;

    return $Self->SystemTime2TimeStamp( SystemTime => $Self->SystemTime() );
}

=item SystemTime2Date()

converts a system time to a structured date array.

    my ($Sec, $Min, $Hour, $Day, $Month, $Year, $WeekDay) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
    );

$WeekDay is the day of the week, with 0 indicating Sunday and 3 indicating Wednesday.

=cut

sub SystemTime2Date {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !defined $Param{SystemTime} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need SystemTime!',
        );
        return;
    }

    # get time format
    my ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WDay ) = localtime $Param{SystemTime};    ## no critic
    $Year  += 1900;
    $Month += 1;
    $Month = sprintf "%02d", $Month;
    $Day   = sprintf "%02d", $Day;
    $Hour  = sprintf "%02d", $Hour;
    $Min   = sprintf "%02d", $Min;
    $Sec   = sprintf "%02d", $Sec;

    return ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WDay );
}

=item TimeStamp2SystemTime()

converts a given time stamp to local system time.

    my $SystemTime = $TimeObject->TimeStamp2SystemTime(
        String => '2004-08-14 22:45:00',
    );

simple calculations using time units can be used to calculate a relative point in time. 
supported units: Y(years),M(months),w(weeks),d(days),h(hours),m(minutes),s(seconds).

    my $SystemTime = $TimeObject->TimeStamp2SystemTime(
        String => '2004-08-14 22:45:00 +1w',
    );

    my $SystemTime = $TimeObject->TimeStamp2SystemTime(
        String => '2004-08-14 22:45:00 -1w -2d +7h',
    );

if no timestamp is used in the calculation, the current system time will be used
    my $SystemTime = $TimeObject->TimeStamp2SystemTime(
        String => '+1w',
    );

=cut

sub TimeStamp2SystemTime {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{String} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need String!',
        );
        return;
    }

    my $SystemTime = 0;
    my $TimeStamp;

    my @Parts = split(/\s+/, $Param{String});

    if ( $Parts[0] !~ /^[+-]\d+[YMwdhms]?/ ) {
        # we have a real timestamp
        $TimeStamp = (shift @Parts) . ' ' . (shift @Parts);
    }
    else {
        # we have to use NOW as TimeStamp
        $TimeStamp = $Self->CurrentTimestamp();
    }

    # match iso date format
    if ( $TimeStamp =~ /(\d{4})-(\d{1,2})-(\d{1,2})\s(\d{1,2}):(\d{1,2}):(\d{1,2})/ ) {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $1,
            Month  => $2,
            Day    => $3,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # match iso date format (wrong format)
    elsif ( $TimeStamp =~ /(\d{1,2})-(\d{1,2})-(\d{4})\s(\d{1,2}):(\d{1,2}):(\d{1,2})/ ) {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $3,
            Month  => $2,
            Day    => $1,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # match euro time format
    elsif ( $TimeStamp =~ /(\d{1,2})\.(\d{1,2})\.(\d{4})\s(\d{1,2}):(\d{1,2}):(\d{1,2})/ ) {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $3,
            Month  => $2,
            Day    => $1,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # match yyyy-mm-ddThh:mm:ss+tt:zz time format
    elsif (
        $TimeStamp
        =~ /(\d{4})-(\d{1,2})-(\d{1,2})T(\d{1,2}):(\d{1,2}):(\d{1,2})(\+|\-)((\d{1,2}):(\d{1,2}))/i
        )
    {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $1,
            Month  => $2,
            Day    => $3,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # match mail time format
    elsif (
        $TimeStamp
        =~ /((...),\s+|)(\d{1,2})\s(...)\s(\d{4})\s(\d{1,2}):(\d{1,2}):(\d{1,2})\s((\+|\-)(\d{2})(\d{2})|...)/
        )
    {
        my $DiffTime = 0;
        if ( $10 && $10 eq '+' ) {

            #            $DiffTime = $DiffTime - ($11 * 60 * 60);
            #            $DiffTime = $DiffTime - ($12 * 60);
        }
        elsif ( $10 && $10 eq '-' ) {

            #            $DiffTime = $DiffTime + ($11 * 60 * 60);
            #            $DiffTime = $DiffTime + ($12 * 60);
        }
        my @MonthMap    = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
        my $Month       = 1;
        my $MonthString = $4;
        for my $MonthCount ( 0 .. $#MonthMap ) {
            if ( $MonthString =~ /$MonthMap[$MonthCount]/i ) {
                $Month = $MonthCount + 1;
            }
        }
        $SystemTime = $Self->Date2SystemTime(
            Year   => $5,
            Month  => $Month,
            Day    => $3,
            Hour   => $6,
            Minute => $7,
            Second => $8,
        ) + $DiffTime + $Self->{TimeSecDiff};
    }
    elsif (    # match yyyy-mm-ddThh:mm:ssZ
        $TimeStamp =~ /(\d{4})-(\d{1,2})-(\d{1,2})T(\d{1,2}):(\d{1,2}):(\d{1,2})Z$/
        )
    {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $1,
            Month  => $2,
            Day    => $3,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # return error
    if ( !defined $SystemTime ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Invalid Date '$Param{String}'!",
        );
    }

    # do calculations if we have to
    if ( @Parts ) {
        my %Diffs = map { $_ => 0 } qw(Y M w d h m s);
        CALC:
        foreach my $Calc ( @Parts ) {
            if ( $Calc !~ /^([+-])(\d+)([YMwdhms])?$/ ) {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'error',
                    Message  => "Invalid timestamp calculation '$Calc'!",
                );
                next CALC;
            }
            my ( $Operator, $Diff, $Unit ) = ( $1, $2, $3 );
            $Unit = 's' if !$Unit;

            eval "\$Diffs{\$Unit} = $Diffs{$Unit} $Operator $Diff";
        }

        # add one year to the current timestamp
        my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $Self->SystemTime2Date(
            SystemTime => $SystemTime
        );
        ($Year,$Month,$Day, $Hour,$Min,$Sec) = Add_Delta_YMDHMS(
            $Year,$Month,$Day,$Hour,$Min,$Sec, 
            $Diffs{Y},$Diffs{M},$Diffs{w}*7 + $Diffs{d},$Diffs{h},$Diffs{m},$Diffs{s}
        );
        $SystemTime = $Self->Date2SystemTime(
            Year   => $Year,
            Month  => $Month,
            Day    => $Day,
            Hour   => $Hour,
            Minute => $Min,
            Second => $Sec,
        );
    }

    # return system time
    return $SystemTime;

}

=item Date2SystemTime()

converts a structured date array to local system time.

    my $SystemTime = $TimeObject->Date2SystemTime(
        Year   => 2004,
        Month  => 8,
        Day    => 14,
        Hour   => 22,
        Minute => 45,
        Second => 0,
    );

=cut

sub Date2SystemTime {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Year Month Day Hour Minute Second)) {
        if ( !defined $Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!",
            );
            return;
        }
    }
    my $SystemTime = eval {
        timelocal(
            $Param{Second}, $Param{Minute}, $Param{Hour}, $Param{Day}, ( $Param{Month} - 1 ),
            $Param{Year}
        );
    };

    if ( !defined $SystemTime ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message =>
                "Invalid Date '$Param{Year}-$Param{Month}-$Param{Day} $Param{Hour}:$Param{Minute}:$Param{Second}'!",
        );
        return;
    }

    return $SystemTime;
}

=item ServerLocalTimeOffsetSeconds()

returns the computed difference in seconds between UTC time and local time.

    my $ServerLocalTimeOffsetSeconds = $TimeObject->ServerLocalTimeOffsetSeconds(
        SystemTime => $SystemTime,  # optional, otherwise call time()
    );

=cut

sub ServerLocalTimeOffsetSeconds {
    my ( $Self, %Param ) = @_;

    my $ServerTime = $Param{SystemTime} || time();
    my $ServerLocalTime = Time::Local::timegm_nocheck( localtime($ServerTime) );

    # Check if local time and UTC time are different
    return $ServerLocalTime - $ServerTime;

}

=item MailTimeStamp()

returns the current time stamp in RFC 2822 format to be used in email headers:
"Wed, 22 Sep 2014 16:30:57 +0200".

    my $MailTimeStamp = $TimeObject->MailTimeStamp();

=cut

sub MailTimeStamp {
    my ( $Self, %Param ) = @_;

    # According to RFC 2822, section 3.3

    # The date and time-of-day SHOULD express local time.
    #
    # The zone specifies the offset from Coordinated Universal Time (UTC,
    # formerly referred to as "Greenwich Mean Time") that the date and
    # time-of-day represent.  The "+" or "-" indicates whether the
    # time-of-day is ahead of (i.e., east of) or behind (i.e., west of)
    # Universal Time.  The first two digits indicate the number of hours
    # difference from Universal Time, and the last two digits indicate the
    # number of minutes difference from Universal Time.  (Hence, +hhmm
    # means +(hh * 60 + mm) minutes, and -hhmm means -(hh * 60 + mm)
    # minutes).  The form "+0000" SHOULD be used to indicate a time zone at
    # Universal Time.  Though "-0000" also indicates Universal Time, it is
    # used to indicate that the time was generated on a system that may be
    # in a local time zone other than Universal Time and therefore
    # indicates that the date-time contains no information about the local
    # time zone.

    my @DayMap   = qw/Sun Mon Tue Wed Thu Fri Sat/;
    my @MonthMap = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;

    # Here we cannot use the KIX "TimeZone" because KIX uses localtime()
    #   and does not know if that is UTC or another time zone.
    #   Therefore KIX cannot generate the correct offset for the mail timestamp.
    #   So we need to use the real time configuration of the server to determine this properly.

    my $ServerTime = time();
    my $ServerTimeDiff = $Self->ServerLocalTimeOffsetSeconds( SystemTime => $ServerTime );

    # calculate offset - should be '+0200', '-0600', '+0545' or '+0000'
    my $Direction   = $ServerTimeDiff < 0 ? '-' : '+';
    my $DiffHours   = abs int( $ServerTimeDiff / 3600 );
    my $DiffMinutes = abs int( ( $ServerTimeDiff % 3600 ) / 60 );

    my ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WeekDay ) = $Self->SystemTime2Date(
        SystemTime => $ServerTime,
    );

    my $TimeString = sprintf "%s, %d %s %d %02d:%02d:%02d %s%02d%02d",
        $DayMap[$WeekDay],    # 'Sat'
        $Day, $MonthMap[ $Month - 1 ], $Year,    # '2', 'Aug', '2014'
        $Hour,      $Min,       $Sec,            # '12', '34', '36'
        $Direction, $DiffHours, $DiffMinutes;    # '+', '02', '00'

    return $TimeString;
}

=item WorkingTime()

get the working time in seconds between these local system times.

    my $WorkingTime = $TimeObject->WorkingTime(
        StartTime => $Created,
        StopTime  => $TimeObject->SystemTime(),
    );

    my $WorkingTime = $TimeObject->WorkingTime(
        StartTime => $Created,
        StopTime  => $TimeObject->SystemTime(),
        Calendar  => 3, # '' is default
    );

=cut

sub WorkingTime {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(StartTime StopTime)) {
        if ( !defined $Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!",
            );
            return;
        }
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    my $TimeWorkingHours        = $ConfigObject->Get('TimeWorkingHours');
    my $TimeVacationDays        = $Self->GetVacationDays();
    my $TimeVacationDaysOneTime = $Self->GetVacationDaysOneTime();
    if ( $Param{Calendar} ) {
        if ( $ConfigObject->Get( "TimeZone::Calendar" . $Param{Calendar} . "Name" ) ) {
            $TimeWorkingHours        = $ConfigObject->Get( "TimeWorkingHours::Calendar" . $Param{Calendar} );
            $TimeVacationDays        = $Self->GetVacationDays( Calendar => $Param{Calendar} );
            $TimeVacationDaysOneTime = $Self->GetVacationDaysOneTime( Calendar => $Param{Calendar} );

            my $Zone = $ConfigObject->Get( "TimeZone::Calendar" . $Param{Calendar} );
            if ($Zone) {
                my $TimeZoneObject   = DateTime::TimeZone->new(
                    name => $Zone
                );
                $Zone = $TimeZoneObject->offset_for_datetime(DateTime->now);     # time zone offset in seconds
                $Param{StartTime} += $Zone;
                $Param{StopTime}  += $Zone;
            }
        }
    }

    # get TimeWorking
    my %TimeWorking;
    if (ref($TimeWorkingHours) eq 'HASH') {
        %TimeWorking = $Self->_GetTimeWorking(
            TimeWorkingHours => $TimeWorkingHours,
            Calendar         => $Param{Calendar} || '',
        );
    }

    my %LDay = (
        1 => 'Mon',
        2 => 'Tue',
        3 => 'Wed',
        4 => 'Thu',
        5 => 'Fri',
        6 => 'Sat',
        0 => 'Sun',
    );

    my $Counted = 0;
    my ( $ASec, $AMin, $AHour, $ADay, $AMonth, $AYear, $AWDay ) = localtime $Param{StartTime};    ## no critic
    $AYear  += 1900;
    $AMonth += 1;
    my $ADate  = $AYear . "-" . sprintf("%02d", $AMonth) . "-" . sprintf("%02d", $ADay);
    my ( $BSec, $BMin, $BHour, $BDay, $BMonth, $BYear, $BWDay ) = localtime $Param{StopTime};     ## no critic
    $BYear  += 1900;
    $BMonth += 1;
    my $BDate  = $BYear . "-" . sprintf("%02d", $BMonth) . "-" . sprintf("%02d", $BDay);
    my $NextDay;

    my $CInit = 1;
    WORKINGDAY:
    while ( 1 ) {
        my ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WDay ) = localtime $Param{StartTime};       ## no critic
        $Year  += 1900;
        $Month += 1;
        my $CDate  = $Year . "-" . sprintf("%02d", $Month) . "-" . sprintf("%02d", $Day);
        my $CTime00 = $Param{StartTime} - ( ( $Hour * 60 + $Min ) * 60 + $Sec );                  # 00:00:00

        # compensate for switching to/from daylight saving time
        # in case daylight saving time from 00:00:00 turned backward 1 hour to 23:00:00
        if ( $NextDay && $Hour == 23 ) {
            $Param{StartTime} += 3600;
            $CTime00 = $Param{StartTime};

            # get $Year, $Month, $Day for $CDate
            # there is needed next day, but $Day++ would be wrong in case it was end of month
            ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WDay ) = localtime $Param{StartTime} + 1;
            $Year  += 1900;
            $Month += 1;
            $CDate = $Year . "-" . sprintf("%02d", $Month) . "-" . sprintf("%02d", $Day);;
        }
        if ( $CInit ) {
            $CInit = 0;

            $Day     = $ADay;
            $Month   = $AMonth;
            $Year    = $AYear;
            $WDay    = $AWDay;
            $CDate   = $ADate;
            $CTime00 = $Param{StartTime} - ( ( $AHour * 60 + $AMin ) * 60 + $ASec );
        }

        # stop if actual date is after end date
        if ($BDate lt $CDate) {
            last WORKINGDAY;
        }

        if ( %TimeWorking ) {
            # get WorkingDay
            my $WorkingDay = $LDay{$WDay};
            # check for VacationDay
            if ( $TimeVacationDays->{$Month}->{$Day} ) {
                $WorkingDay = $TimeVacationDays->{$Month}->{$Day};
            }
            if ( $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day} ) {
                $WorkingDay = $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day};
            }

            # process working minutes
            if ( $TimeWorking{ $WorkingDay } ) {
                WORKINGHOUR:
                for my $WorkingHour ( sort{ $a <=> $b }( keys( %{ $TimeWorking{$WorkingDay} } ) ) ) {

                    # not date of start or end
                    if (
                        $CDate ne $ADate
                        && $CDate ne $BDate
                    ) {
                        $Counted += $TimeWorking{$WorkingDay}->{-1}->{'DayWorkingTime'};
                        last WORKINGHOUR;
                    }

                    # no service time this hour
                    elsif (
                        !$TimeWorking{$WorkingDay}->{$WorkingHour}->{'WorkingTime'}
                    ) {}

                    # same date and same hour of start/end date within service time
                    # and 60 minute working time this hour
                    elsif (
                        $ADate eq $BDate
                        && $AHour == $BHour
                        && $AHour == $WorkingHour
                        && $TimeWorking{$WorkingDay}->{$WorkingHour}->{'WorkingTime'} == 3600
                    ) {
                        return $Param{StopTime} - $Param{StartTime};
                    }
                    # same date and same hour of start/end date within service hour
                    elsif (
                        $ADate eq $BDate
                        && $AHour == $BHour
                        && $AHour == $WorkingHour
                    ) {
                        for my $WorkingMin (qw($AMin..$BMin)) {
                            if ($TimeWorking{$WorkingDay}->{$WorkingHour}->{$WorkingMin}) {
                                $Counted += 60;
                            }
                        }
                        last WORKINGHOUR;
                    }

                    # date of start and before service time
                    elsif (
                        $CDate eq $ADate
                        && $WorkingHour < $AHour
                    ) {}

                    # date and hour of start
                    # and 60 minute working time this hour
                    elsif (
                        $CDate eq $ADate
                        && $AHour == $WorkingHour
                        && $TimeWorking{$WorkingDay}->{$WorkingHour}->{'WorkingTime'} == 3600
                    ) {
                        $Counted += ((59 - $AMin) * 60) + (60 - $ASec);
                    }

                    # date and hour of start
                    elsif (
                        $CDate eq $ADate
                        && $AHour == $WorkingHour
                    ) {
                        for my $WorkingMin (qw($AMin..59)) {
                            if ($TimeWorking{$WorkingDay}->{$WorkingHour}->{$WorkingMin}) {
                                if ($AMin == $WorkingMin) {
                                    $Counted += (60 - $ASec);
                                } else {
                                    $Counted += 60;
                                }
                            }
                        }
                    }

                    # date of end and after service time
                    elsif (
                        $CDate eq $BDate
                        && $WorkingHour > $BHour
                    ) {}

                    # date and hour from end
                    # and 60 minute working time this hour
                    elsif (
                        $CDate eq $BDate
                        && $BHour == $WorkingHour
                        && $TimeWorking{$WorkingDay}->{$WorkingHour}->{'WorkingTime'} == 3600
                    ) {
                        $Counted += ($BMin * 60) + $BSec;
                    }

                    # date and hour from end
                    elsif (
                        $CDate eq $BDate
                        && $BHour == $WorkingHour
                    ) {
                        for my $WorkingMin (qw(0..$BMin)) {
                            if ($TimeWorking{$WorkingDay}->{$WorkingHour}->{$WorkingMin}) {
                                if ($BMin == $WorkingMin) {
                                    $Counted += $BSec;
                                } else {
                                    $Counted += 60;
                                }
                            }
                        }
                    }

                    # service time that is not first or last hour
                    else {
                        $Counted += $TimeWorking{$WorkingDay}->{$WorkingHour}->{'WorkingTime'};
                    }
                }
            }
        }
        # FALLBACK
        else {
            # count nothing because of vacation
            if (
                $TimeVacationDays->{$Month}->{$Day}
                || $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day}
                )
            {

                # do nothing
            }
            else {
                if ( $TimeWorkingHours->{ $LDay{$WDay} } ) {
                    for my $WorkingHour ( @{ $TimeWorkingHours->{ $LDay{$WDay} } } ) {

                        # same date and same hour of start/end date within service hour
                        # => start counting and finish immediatly
                        if ( $ADate eq $BDate && $AHour == $BHour && $AHour == $WorkingHour ) {
                            return $Param{StopTime} - $Param{StartTime};
                        }

                        # do nothing because we are on start day and not yet within service hour
                        elsif ( $CDate eq $ADate && $WorkingHour < $AHour ) {
                        }

                        # we are on start day and within start hour => count to end of this hour
                        elsif ( $CDate eq $ADate && $AHour == $WorkingHour ) {
                            $Counted
                                += ( $CTime00 + ( $WorkingHour + 1 ) * 60 * 60 ) - $Param{StartTime};
                        }

                        # do nothing because we are on end day but greater than service hour
                        elsif ( $CDate eq $BDate && $BHour < $WorkingHour ) {
                        }

                        # we are on end day and within end hour => count from start of this hour
                        elsif ( $CDate eq $BDate && $BHour == $WorkingHour ) {
                            $Counted += $Param{StopTime} - ( $CTime00 + $WorkingHour * 60 * 60 );
                        }

                        # count full hour because we are in service hour that is greater than
                        # start hour and smaller than end hour
                        else {
                            $Counted = $Counted + ( 60 * 60 );
                        }
                    }
                }
            }
        }

        # reduce time => go to next day 00:00:00
        $Param{StartTime} = $Self->Date2SystemTime(
            Year   => $Year,
            Month  => $Month,
            Day    => $Day,
            Hour   => 23,
            Minute => 59,
            Second => 59,
        ) + 1;

        # it will be used for checking daylight saving time
        $NextDay = 1;

    }
    return $Counted;
}

=item DestinationTime()

get the destination time based on the current calendar working time (fallback: default
system working time) configuration.

The algorithm roughly works as follows:
    - Check if the start time is actually in the configured working time.
        - If not, set it to the next working time second. Example: start time is
            on a weekend, start time would be set to 8:00 on the following Monday.
    - Then the diff time (in seconds) is added to the start time incrementally, only considering
        the configured working times. So adding 24 hours could actually span multiple days because
        they would be spread over the configured working hours. If we have 8-20, 24 hours would be
        spread over 2 days (13/11 hours).

NOTE: Currently, the implementation stops silently after 600 iterations, making it impossible to
    specify longer escalation times, for example.

    my $DestinationTime = $TimeObject->DestinationTime(
        StartTime => $Created,
        Time      => 60*60*24*2,
    );

    my $DestinationTime = $TimeObject->DestinationTime(
        StartTime => $Created,
        Time      => 60*60*24*2,
        Calendar  => 3, # '' is default
    );

=cut

sub DestinationTime {
    my ( $Self, %Param ) = @_;

    # "Time zone" diff in seconds
    my $Zone = 0;

    # check needed stuff
    for (qw(StartTime Time)) {
        if ( !defined $Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!",
            );
            return;
        }
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    my $TimeWorkingHours        = $ConfigObject->Get('TimeWorkingHours');
    my $TimeVacationDays        = $Self->GetVacationDays();
    my $TimeVacationDaysOneTime = $Self->GetVacationDaysOneTime();
    if ( $Param{Calendar} ) {
        if ( $ConfigObject->Get( "TimeZone::Calendar" . $Param{Calendar} . "Name" ) ) {
            $TimeWorkingHours        = $ConfigObject->Get( "TimeWorkingHours::Calendar" . $Param{Calendar} );
            $TimeVacationDays        = $Self->GetVacationDays( Calendar => $Param{Calendar} );
            $TimeVacationDaysOneTime = $Self->GetVacationDaysOneTime( Calendar => $Param{Calendar} );

            my $TimeZoneObject   = DateTime::TimeZone->new(
                name => $ConfigObject->Get( "TimeZone::Calendar" . $Param{Calendar} )
            );
            $Zone = $TimeZoneObject->offset_for_datetime(DateTime->now);     # time zone offset in seconds
            $Param{StartTime} += $Zone;
        }
    }
    my $DestinationTime = $Param{StartTime};
    my $CTime           = $Param{StartTime};

    # get TimeWorking
    my %TimeWorking;
    if (ref($TimeWorkingHours) eq 'HASH') {
        %TimeWorking = $Self->_GetTimeWorking(
            TimeWorkingHours => $TimeWorkingHours,
            Calendar         => $Param{Calendar} || '',
        );
    }

    my %LDay = (
        1 => 'Mon',
        2 => 'Tue',
        3 => 'Wed',
        4 => 'Thu',
        5 => 'Fri',
        6 => 'Sat',
        0 => 'Sun',
    );

    my $LoopCounter;
    my $DayLightSaving;

    LOOP:
    while ( $Param{Time} > 1 ) {
        $LoopCounter++;
        last LOOP if $LoopCounter > 5000;

        my ( $Second, $Minute, $Hour, $Day, $Month, $Year, $WDay ) = localtime $CTime;    ## no critic
        $Year  += 1900;
        $Month += 1;
        my $CTime00 = $CTime - ( ( $Hour * 60 + $Minute ) * 60 + $Second );               # 00:00:00

        # compensate for switching to/from daylight saving time
        # in case daylight saving time from 00:00:00 turned backward 1 hour to 23:00:00
        if ( $DayLightSaving && $Hour == 23 ) {
            $CTime += 3600;
            $CTime00 = $CTime;

            # there is needed next day, but $Day++ would be wrong in case it was end of month
            ( $Second, $Minute, $Hour, $Day, $Month, $Year, $WDay ) = localtime $CTime + 1;
            $Year  += 1900;
            $Month += 1;

            $DestinationTime += 3600;
        }

        if ( %TimeWorking ) {

            # get WorkingDay
            my $WorkingDay = $LDay{$WDay};

            # check for VacationDay
            if ( $TimeVacationDays->{$Month}->{$Day} ) {
                $WorkingDay = $TimeVacationDays->{$Month}->{$Day};
            }
            if ( $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day} ) {
                $WorkingDay = $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day};
            }

            # Skip days without working hours
            if ( !$TimeWorking{$WorkingDay}->{-1}->{'DayWorkingTime'} ) {

                # Set destination time to next day, 00:00:00
                $DestinationTime = $Self->Date2SystemTime(
                    Year   => $Year,
                    Month  => $Month,
                    Day    => $Day,
                    Hour   => 23,
                    Minute => 59,
                    Second => 59,
                ) + 1;
            }

            # Working time
            else {
                HOUR:
                for my $WorkingHour ( $Hour .. 23 ) {
                    my $DiffDestTime = 0;
                    my $DiffWorkTime = 0;

                    # Working hour
                    if ( $TimeWorking{$WorkingDay}->{$WorkingHour} ) {
                        MINUTE:
                        for my $Min ( $Minute..59 ) {

                            # Working minute
                            if ( $TimeWorking{$WorkingDay}->{$WorkingHour}->{$Min} ) {
                                if ( ($Param{Time} - $DiffWorkTime) > (60 - $Second) ) {
                                    $DiffDestTime += (60 - $Second);
                                    $DiffWorkTime += (60 - $Second);
                                } else {
                                    $DiffDestTime += ($Param{Time} - $DiffWorkTime);
                                    $DiffWorkTime += ($Param{Time} - $DiffWorkTime);
                                    last MINUTE;
                                }
                            }

                            # Not working minute
                            else {
                                $DiffDestTime += (60 - $Second);
                            }
                            $Second = 0;
                        }
                    }

                    # Not working hour
                    else {
                        $DiffDestTime = 3600 - ( $Minute * 60 + $Second );
                    }

                    # update time params
                    $DestinationTime += $DiffDestTime;
                    $Param{Time}     -= $DiffWorkTime;
                    $Minute = 0;
                    $Second = 0;

                    # check time left
                    if ($Param{Time} == 0) {
                        last HOUR;
                    }
                }
            }
        }
        # FALLBACK
        else {

            # Skip vacation days, or days without working hours, do not count.
            if (
                $TimeVacationDays->{$Month}->{$Day}
                || $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day}
                || !$TimeWorkingHours->{ $LDay{$WDay} }
                )
            {
                # Set destination time to next day, 00:00:00
                $DestinationTime = $Self->Date2SystemTime(
                    Year   => $Year,
                    Month  => $Month,
                    Day    => $Day,
                    Hour   => 23,
                    Minute => 59,
                    Second => 59,
                ) + 1;
            }

            # Regular day with working hours
            else {
                HOUR:
                for my $H ( $Hour .. 23 ) {

                    # Check if we have a working hour
                    if ( grep { $H == $_ } @{ $TimeWorkingHours->{ $LDay{$WDay} } } ) {
                        if ( $Param{Time} > 60 * 60 ) {
                            my $RestOfHour = 3600 - ( $Minute * 60 + $Second );
                            $DestinationTime += $RestOfHour;
                            $Param{Time} -= $RestOfHour;
                        }
                        else {
                            $DestinationTime += $Param{Time};
                            last LOOP;
                        }
                    }

                    # Not a working hour
                    else {
                        my $RestOfHour = 3600 - ( $Minute * 60 + $Second );
                        $DestinationTime += $RestOfHour;
                    }

                    # Here we are always aligned at an hour boundary
                    $Minute = 0;
                    $Second = 0;
                }
            }
        }

        # Find the unix time stamp for the next day at 00:00:00 to start for calculation.
        my $NewCTime = $Self->Date2SystemTime(
            Year   => $Year,
            Month  => $Month,
            Day    => $Day,
            Hour   => 23,
            Minute => 59,
            Second => 59,
        ) + 1;

        if ( !%TimeWorking ) {

            # Compensate for switching to/from daylight saving time
            # (day is shorter or longer than 24h)
            if ( $NewCTime != $CTime00 + 24 * 60 * 60 ) {
                my $Diff = $NewCTime - $CTime00 - 24 * 60 * 60;
                $DestinationTime += $Diff;
                $DayLightSaving = 1;
            }
        }

        # Set next loop time to 00:00:00 of next day.
        $CTime = $NewCTime;
    }

    # return destination time - e. g. with diff of calendar time zone
    return $DestinationTime - $Zone;
}

=item VacationCheck()

check if the selected day is a vacation (it doesn't matter if you
insert 01 or 1 for month or day in the function or in the SysConfig)

returns (true) vacation day if exists, returns false if date is no
vacation day

    $TimeObject->VacationCheck(
        Year     => 2005,
        Month    => 7 || '07',
        Day      => 13,
    );

    $TimeObject->VacationCheck(
        Year     => 2005,
        Month    => 7 || '07',
        Day      => 13,
        Calendar => 3, # '' is default; 0 is handled like ''
    );

=cut

sub VacationCheck {
    my ( $Self, %Param ) = @_;

    # check required params
    for (qw(Year Month Day)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "VacationCheck: Need $_!",
            );
            return;
        }
    }

    my $Year  = $Param{Year};
    my $Month = sprintf "%02d", $Param{Month};
    my $Day   = sprintf "%02d", $Param{Day};

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    my $TimeVacationDays        = $Self->GetVacationDays();
    my $TimeVacationDaysOneTime = $Self->GetVacationDaysOneTime();
    if ( $Param{Calendar} ) {
        if ( $ConfigObject->Get( "TimeZone::Calendar" . $Param{Calendar} . "Name" ) ) {
            $TimeVacationDays        = $Self->GetVacationDays( Calendar => $Param{Calendar} );
            $TimeVacationDaysOneTime = $Self->GetVacationDaysOneTime( Calendar => $Param{Calendar} );
        }
    }

    # '01' - format
    if ( defined $TimeVacationDays->{$Month}->{$Day} ) {
        return $TimeVacationDays->{$Month}->{$Day};
    }
    if ( defined $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day} ) {
        return $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day};
    }

    # 1 - int format
    $Month = int $Month;
    $Day   = int $Day;
    if ( defined $TimeVacationDays->{$Month}->{$Day} ) {
        return $TimeVacationDays->{$Month}->{$Day};
    }
    if ( defined $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day} ) {
        return $TimeVacationDaysOneTime->{$Year}->{$Month}->{$Day};
    }

    return;
}

=item GetVacationDays()

get TimeVacationDays from Config and prepare internal representation

    $TimeObject->GetVacationDays(
        Calendar => '...'           # optional
    );


=cut

sub GetVacationDays {
    my ( $Self, %Param ) = @_;
    my $Result;

    my $TimeVacationDays = $Kernel::OM->Get('Config')->Get('TimeVacationDays');
    if ( $Param{Calendar} ) {
        if ( $Kernel::OM->Get('Config')->Get( "TimeZone::Calendar" . $Param{Calendar} . "Name" ) ) {
            $TimeVacationDays = $Kernel::OM->Get('Config')->Get( 'TimeVacationDays::Calendar' . $Param{Calendar} );
        }
    }

    return {} if !IsArrayRefWithData($TimeVacationDays);

    foreach my $Item ( @{$TimeVacationDays} ) {
        $Result->{$Item->{Month}}->{$Item->{Day}} = $Item->{content}
    }

    return $Result;
}

=item GetVacationDaysOneTime()

get TimeVacationDaysOneTime from Config and prepare internal representation

    $TimeObject->GetVacationDaysOneTime(
        Calendar => '...'           # optional
    );


=cut

sub GetVacationDaysOneTime {
    my ( $Self, %Param ) = @_;
    my $Result;

    my $TimeVacationDays = $Kernel::OM->Get('Config')->Get('TimeVacationDaysOneTime');
    if ( $Param{Calendar} ) {
        if ( $Kernel::OM->Get('Config')->Get( "TimeZone::Calendar" . $Param{Calendar} . "Name" ) ) {
            $TimeVacationDays = $Kernel::OM->Get('Config')->Get( 'TimeVacationDaysOneTime::Calendar' . $Param{Calendar} );
        }
    }

    return {} if !IsArrayRefWithData($TimeVacationDays);

    foreach my $Item ( @{$TimeVacationDays} ) {
        $Result->{$Item->{Year}}->{$Item->{Month}}->{$Item->{Day}} = $Item->{content}
    }

    return $Result;
}

sub _GetTimeWorking {
    my ( $Self, %Param ) = @_;

    # check cache
    my $TimeWorkingCache = $Self->{CacheObject}->Get(
        Type => $Self->{CacheType},
        Key  => "TimeWorkingHours::Calendar" . $Param{Calendar},
    );
    return %{$TimeWorkingCache} if ( defined($TimeWorkingCache) );

    # set WorkingTime
    my %TimeWorking;
    for my $Entry ( keys( %{$Param{TimeWorkingHours}} ) ) {
        my @ConfigEntries = split(',', $Param{TimeWorkingHours}->{$Entry});
        for my $Config ( @ConfigEntries ) {
            if (
                $Config =~ m/^\s*([0-1]?[0-9]|2[0-3]):([0-5][0-9])-([0-1]?[0-9]|2[0-3]):([0-5][0-9])\s*$/
                || $Config =~ m/^\s*([0-1]?[0-9]|2[0-3]):([0-5][0-9])-(24):(00)\s*$/
            ) {
                my $StartHour   = $1;
                my $StartMin    = $2;
                my $StopHour    = $3;
                my $StopMin     = $4;
                $StartHour =~ s/0([0-9])/$1/;
                $StartMin =~ s/0([0-9])/$1/;
                $StopHour =~ s/0([0-9])/$1/;
                $StopMin =~ s/0([0-9])/$1/;
                while (
                    $StopHour > $StartHour
                    || $StopMin > $StartMin
                ) {
                    $TimeWorking{$Entry}->{$StartHour}->{$StartMin} = 1;
                    $StartMin++;
                    if ($StartMin == 60) {
                        $StartHour++;
                        $StartMin = 0;
                    }
                }
            } else {
                if ( $Param{Calendar} ) {
                    $Kernel::OM->Get('Log')->Log(
                        Priority => 'error',
                        Message  => 'Invalid entry in TimeWorkingHours::Calendar' . $Param{Calendar} . ' <' . $Entry . '>',
                    );
                } else {
                    $Kernel::OM->Get('Log')->Log(
                        Priority => 'error',
                        Message  => 'Invalid entry in TimeWorkingHours <' . $Entry . '>',
                    );
                }
            }
        }
    }
    # prepare WorkingMinutes per day and hour
    for my $WorkingDay ( keys( %TimeWorking ) ) {
        my $DayWorkingMinutes = 0;
        for my $Hour ( keys( %{$TimeWorking{$WorkingDay}} ) ) {
            my $WorkingMinutes = 0;
            for my $Minute ( keys( %{$TimeWorking{$WorkingDay}->{$Hour}} ) ) {
                $DayWorkingMinutes++;
                $WorkingMinutes++;
            }
            $TimeWorking{$WorkingDay}->{$Hour}->{'WorkingTime'} = $WorkingMinutes * 60;
        }
        $TimeWorking{$WorkingDay}->{-1}->{'DayWorkingTime'} = $DayWorkingMinutes * 60;
    }
    $Self->{CacheObject}->Set(
        Type  => $Self->{CacheType},
        Key   => "TimeWorkingHours::Calendar" . $Param{Calendar},
        Value => \%TimeWorking,
        TTL   => 5 * 60,
        Depends => ['SysConfig'] # delete also if config is changed (TimeWorkingHours)
    );
    return %TimeWorking;
}

1;


=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-AGPL for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
