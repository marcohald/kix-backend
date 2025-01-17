# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::PostMaster::Filter::SystemMonitoringX;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Config',
    'DynamicField',
    'LinkObject',
    'Log',
    'Main',
    'Ticket',
    'Time',
);

# the base name for dynamic fields
# defines the name of a dynamic field even if the name is not set
our $DynamicFieldTicketTextPrefix  = 'TicketDynamicField';
our $DynamicFieldArticleTextPrefix = 'ArticleDynamicField';

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{Debug}                = $Param{Debug} || 0;
    $Self->{MainObject}           = $Kernel::OM->Get('Main');
    $Self->{ParserObject}         = $Param{ParserObject} || die "Got no ParserObject!";
    $Self->{GeneralCatalogObject} = $Kernel::OM->Get('GeneralCatalog');
    $Self->{ConfigItemObject}     = $Kernel::OM->Get('ITSMConfigItem');

    $Self->{Config} = {
        Module                         => 'Kernel::System::PostMaster::Filter::SystemMonitoringX',
        'DynamicFieldContent::Ticket'  => 'SysMonXHost,SysMonXService,SysMonXAddress,SysMonXAlias,SysMonXState',
        'DynamicFieldContent::Article' => '',

        AcknowledgeName      => 'Nagios1',
        AffectedAssetName    => 'AffectedAsset',

        CreateTicketType     => 'Incident',
        CreateTicketState    => 'new',
        CreateSenderType     => 'system',
        CreateChannel        => 'note',
        CreateTicketQueue    => '',
        CreateTicketSLA      => '',

        CloseNotIfLocked     => '0',
        StopAfterMatch       => '1',
        FromAddressRegExp    => '.*',
        ToAddressRegExp      => '.*',

        SysMonXAddressRegExp => '\s*Address:\s+(.*)\s*',
        SysMonXAliasRegExp   => '\s*Alias:\s+(.*)\s*',
        SysMonXStateRegExp   => '\s*State:\s+(\S+)',
        SysMonXHostRegExp    => '\s*Host:\s+(.*)\s*',
        SysMonXServiceRegExp => '\s*Service:\s+(.*)\s*',
        DefaultService       => 'Host',

        NewTicketRegExp      => 'CRITICAL|DOWN|WARNING',
        CloseTicketRegExp    => 'OK|UP',
        CloseActionState     => 'closed',
        ClosePendingTime     => 60 * 60 * 24 * 2,
    };

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Config');

    # get config options, use defaults unless value specified
    if ( $Param{JobConfig} && ref $Param{JobConfig} eq 'HASH' ) {

        for my $Key ( keys( %{ $Param{JobConfig} } ) ) {

            $Self->{Config}->{$Key} = $Param{JobConfig}->{$Key};
        }
    }

    # replace KIX_CONFIG tags
    for my $Key ( keys %{ $Self->{Config} } ) {
        next if !$Self->{Config}->{$Key};
        $Self->{Config}->{$Key} =~ s{<KIX_CONFIG_(.+?)>}{$Self->{Config}->Get($2)}egx;
    }

    # see, whether to-address is of interest regarding system-monitoring
    my $ReceipientOfInterest = 0;
    if ( $Self->{Config}->{ToAddressRegExp} ) {
        my $Recipient = '';
        for my $CurrKey (qw(To Cc Resent-To)) {
            if ( $Param{GetParam}->{$CurrKey} ) {
                if ($Recipient) {
                    $Recipient .= ', ';
                }
                $Recipient .= $Param{GetParam}->{$CurrKey};
            }
        }

        my @EmailAddresses = $Self->{ParserObject}->SplitAddressLine(
            Line => $Recipient,
        );
        for my $CurrKey (@EmailAddresses) {
            my $Address = $Self->{ParserObject}->GetEmailAddress( Email => $CurrKey ) || '';
            if ( $Address && $Address =~ /$Self->{Config}->{ToAddressRegExp}/i ) {
                $ReceipientOfInterest = 1;
                last;
            }
        }
    }
    else {
        $ReceipientOfInterest = 1;
    }

    $Kernel::OM->Get('Log')->Log(
        Priority => 'debug',
        Message  => "SysMon Mail: Receipient relevant <$ReceipientOfInterest>.",
    );

    return 1 if !$ReceipientOfInterest;

    # check if sender is of interest
    return 1 if !$Param{GetParam}->{From};

    return 1 if $Param{GetParam}->{From} !~ /$Self->{Config}->{FromAddressRegExp}/i;
    $Kernel::OM->Get('Log')->Log(
        Priority => 'debug',
        Message  => 'SysMon Mail: From accepted.',
    );

    $Self->_MailParse(%Param);

    # set default sysmon service...
    $Self->{SysMonXService} ||= $Self->{Config}->{DefaultService};

    $Kernel::OM->Get('Log')->Log(
        Priority => 'debug',
        Message  => "SysMon Mail: mail parsed - Host: ".$Self->{SysMonXHost}
            . ", State: ".$Self->{SysMonXState}
            . ", Service: ".$Self->{SysMonXService},
    );

    # we need State and Host to proceed
    if ( !$Self->{SysMonXHost} || !$Self->{SysMonXState} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'notice',
            Message  => 'SysMon Mail: '
                . 'SysMon Mail: Could not find host address '
                . 'and/or state in mail => Ignoring',
        );

        return 1;
    }

    # search ticket if followup...
    my $TicketID = $Self->_TicketSearch() || '';
    $Kernel::OM->Get('Log')->Log(
        Priority => 'debug',
        Message  => 'SysMon Mail: TID found <$TicketID>.',
    );

    # OK, found ticket to deal with
    if ($TicketID) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'debug',
            Message  => 'SysMon Mail: FUP for TID <$TicketID> received.',
        );
        $Self->_TicketUpdate(
            TicketID => $TicketID,
            Param    => \%Param,
        );
    }
    elsif ( $Self->{SysMonXState} =~ /$Self->{Config}->{NewTicketRegExp}/ ) {
        $Self->_TicketCreate( \%Param );
    }
    else {
        $Self->_TicketDrop( \%Param );
    }

    return 1;
}


# the following are optional modules from the ITSM Kernel::System::GeneralCatalog and Kernel::System::ITSMConfigItem

sub _MailParse {
    my ( $Self, %Param ) = @_;

    if ( !$Param{GetParam} || !$Param{GetParam}->{Subject} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Need Subject!",
        );

        return;
    }

    my @DynamicFieldContentTicket = split( ',', $Self->{Config}->{'DynamicFieldContent::Ticket'} );
    my @DynamicFieldContentArticle = split( ',', ($Self->{Config}->{'DynamicFieldContent::Article'} || ''));
    my @DynamicFieldContent = ( @DynamicFieldContentTicket, @DynamicFieldContentArticle );

    my $Subject = $Param{GetParam}->{Subject};
    my %AlreadyMatched;

    # examine email SUBJECT...
    my @SubjectLines = split /\n/, $Subject;
    for my $Line (@SubjectLines) {

        # extract to SysMon-State, -Host, -Service, -Address from email BODY
        ITEM:
        for my $Item (@DynamicFieldContent) {
            next ITEM if !$Self->{Config}->{ $Item . 'RegExp' };
            my $Regex = $Self->{Config}->{ $Item . 'RegExp' };
            if ( $Line =~ /$Regex/ ) {
                $Self->{$Item} = $1;
                $AlreadyMatched{$Item} = 1;
            }
        }
    }

    # examine email BODY line by line...
    my $Body = $Param{GetParam}->{Body} || die "Message has no Body";
    my @BodyLines = split /\n/, $Body;

    LINE:
    for my $Line (@BodyLines) {

        # extract to SysMon-State, -Host, -Service, -Address from email BODY
        ITEM:
        for my $Item (@DynamicFieldContent) {
            next ITEM if !$Self->{Config}->{ $Item . 'RegExp' };
            next ITEM if $AlreadyMatched{$Item};

            my $Regex = $Self->{Config}->{ $Item . 'RegExp' };
            if ( $Line =~ /$Regex/ ) {
                $Self->{$Item} = $1;
                $AlreadyMatched{$Item} = 1;
            }
        }
    }

    return 1;
}

sub _LogMessage {
    my ( $Self, %Param ) = @_;

    if ( !$Param{MessageText} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Need MessageText!",
        );

        return;
    }

    my $MessageText = $Param{MessageText};

    # define log message
    $Self->{SysMonXService} ||= "No Service";
    $Self->{SysMonXState}   ||= "No State";
    $Self->{SysMonXHost}    ||= "No Host";
    $Self->{SysMonXAddress} ||= "No Address";
    $Self->{SysMonXAlias}   ||= "No Alias";

    my $LogMessage = $MessageText . " - "
        . "Host: $Self->{SysMonXHost}, "
        . "State: $Self->{SysMonXState}, "
        . "Address: $Self->{SysMonXAddress}, "
        . "Alias: $Self->{SysMonXAlias}, "
        . "Service: $Self->{SysMonXService}";

    $Kernel::OM->Get('Log')->Log(
        Priority => 'notice',
        Message  => 'SysMon Mail: '.$LogMessage,
    );

    return 1;
}

sub _TicketSearch {
    my ( $Self, %Param ) = @_;

    # search Open tickets with SysMonService and SysMonHost...
    my $DynamicFieldObject = $Kernel::OM->Get('DynamicField');
    my $Errors = 0;
    my @Conditions = qw{};
    my %StateTypeCriteria = (
            Field    =>'StateType',
            Operator => 'EQ',
            Value    => 'Open',
    );
    push( @Conditions, \%StateTypeCriteria );

    ITEM:
    for my $DFName (qw(SysMonXHost SysMonXService)) {
        my $DynamicField = $DynamicFieldObject->DynamicFieldGet(
            Name => $DFName,
        );

        if ( !IsHashRefWithData($DynamicField) ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "SysMon Mail DF <".$DFName. "> does not exists.",
            );
            $Errors = 1;
            next ITEM;
        }

        my %DFCriteria = (
           Field    => "DynamicField_$DFName",
           Operator => 'EQ',
           Value    => $Self->{$DFName},
        );
        push( @Conditions, \%DFCriteria );

    }

    # Is there a ticket for this Host/Service pair?
    my %Query = (
        Result   => 'ARRAY',
        Limit    => 1,
        UserID   => 1,
        'Search' => {
            'AND' => \@Conditions,
        },
    );

    # get 1st ticket for search (if there is one)...
    my $TicketID;
    if ( !$Errors ) {
        my @TicketIDs = $Kernel::OM->Get('Ticket')->TicketSearch( %Query );
        if (@TicketIDs) {
            $TicketID = shift( @TicketIDs );
        }
    }

    return $TicketID;
}

# Side Effect Notice: this sub modifies param hash!
sub _TicketUpdate {
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(TicketID Param)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    my $TicketID = $Param{TicketID};
    my $Param    = $Param{Param};

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Ticket');

    # get ticket number
    my $TicketNumber = $TicketObject->TicketNumberLookup(
        TicketID => $TicketID,
        UserID   => 1,
    );

    # build subject
    $Param->{GetParam}->{Subject} = $TicketObject->TicketSubjectBuild(
        TicketNumber => $TicketNumber,
        Subject      => $Param->{GetParam}->{Subject},
    );

    # set sender type and article channel and sysmon state
    $Param->{GetParam}->{'X-KIX-FollowUp-SenderType'} = $Self->{Config}->{CreateSenderType};
    $Param->{GetParam}->{'X-KIX-FollowUp-Channel'}    = $Self->{Config}->{CreateChannel};
    if( $Self->{Config}->{SysMonXStateName} ) {
      my $DFSMStateFilter = 'X-KIX-FollowUp-DynamicField-'.$Self->{Config}->{SysMonXStateName};
      $Param->{GetParam}->{$DFSMStateFilter} = $Self->{SysMonXState};
    }

    if ( $Self->{SysMonXState} =~ /$Self->{Config}->{CloseTicketRegExp}/ ) {

        if (
            $Self->{Config}->{CloseActionState} ne 'OLD'
            && !(
                $Self->{Config}->{CloseNotIfLocked}
                && $TicketObject->TicketLockGet( TicketID => $TicketID )
            )
        )
        {
            $Param->{GetParam}->{'X-KIX-FollowUp-State'} = $Self->{Config}->{CloseActionState};
            my $TimeStamp = $Kernel::OM->Get('Time')->SystemTime2TimeStamp(
                SystemTime => $Kernel::OM->Get('Time')->SystemTime() + $Self->{Config}->{ClosePendingTime},
            );
            $Param->{GetParam}->{'X-KIX-State-PendingTime'} = $TimeStamp;
        }

        $Self->_LogMessage( MessageText => 'Recovered' );

    }
    else {
        $Self->_LogMessage( MessageText => 'New Notice' );
    }

    return 1;
}

# Side Effect Notice: this sub modifies param hash!
sub _TicketCreate {
    my ( $Self, $Param ) = @_;

    my @DynamicFieldContentTicket
        = split( ',', ($Self->{Config}->{'DynamicFieldContent::Ticket'} || '') );
    my @DynamicFieldContentArticle
        = split( ',', ($Self->{Config}->{'DynamicFieldContent::Article'} || '') );
    my @DynamicFieldContent = ( @DynamicFieldContentTicket, @DynamicFieldContentArticle );

    for my $ConfiguredDynamicField (@DynamicFieldContentTicket) {
        my $DynamicField = $Kernel::OM->Get('DynamicField')->DynamicFieldGet(
            'Name' => $ConfiguredDynamicField,
        );
        if ( !IsHashRefWithData($DynamicField) ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "SysMon Mail DF <" . $ConfiguredDynamicField
                    . "> does not exist.",
            );
        }
        $Param->{GetParam}->{ 'X-KIX-DynamicField-' . $ConfiguredDynamicField }
            = $Self->{$ConfiguredDynamicField};
    }

    # set basic ticket- and article params...
    $Param->{GetParam}->{'X-KIX-SenderType'} = $Self->{Config}->{CreateSenderType}
        || $Param->{GetParam}->{'X-KIX-SenderType'};
    $Param->{GetParam}->{'X-KIX-Channel'} = $Self->{Config}->{CreateChannel}
        || $Param->{GetParam}->{'X-KIX-Channel'};
    if($Param->{GetParam}->{'X-KIX-Queue'}  ne ''){
        my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
        if( $QueueObject->NameExistsCheck( Name =>  $Param->{GetParam}->{'X-KIX-Queue'},)){
            $Kernel::OM->Get('Log')->Log(
                Priority => 'notice',
                Message  => "X-KIX-Queue is already set to " . $Param->{GetParam}->{'X-KIX-Queue'},
            );
        }else{
            $Kernel::OM->Get('Log')->Log(
                Priority => 'notice',
                Message  => "X-KIX-Queue set to " . $Param->{GetParam}->{'X-KIX-Queue'} . " but the Queue was not found, using standard " . $Self->{Config}->{CreateTicketQueue},
            );
            $Param->{GetParam}->{'X-KIX-Queue'} = $Self->{Config}->{CreateTicketQueue};
        }
    }else{
        $Param->{GetParam}->{'X-KIX-Queue'} = $Self->{Config}->{CreateTicketQueue}
            || $Param->{GetParam}->{'X-KIX-Queue'};
    }    
    $Param->{GetParam}->{'X-KIX-State'} = $Self->{Config}->{CreateTicketState}
        || $Param->{GetParam}->{'X-KIX-State'};
    $Param->{GetParam}->{'X-KIX-Type'} = $Self->{Config}->{CreateTicketType}
        || $Param->{GetParam}->{'X-KIX-Type'};
    $Param->{GetParam}->{'X-KIX-SLA'} = $Self->{Config}->{CreateTicketSLA}
        || $Param->{GetParam}->{'X-KIX-SLA'};

    # set DF AcknowledgeNameField to allow later sysmon source identification...
    if ( $Self->{Config}->{AcknowledgeName} ) {
        my $AcknowledgeNameField = $Kernel::OM->Get('Config')->Get('Tool::Acknowledge::RegistrationAllocation');
        if ($AcknowledgeNameField) {
            if ( $AcknowledgeNameField =~ /^\d+$/ ) {
                $AcknowledgeNameField = $DynamicFieldTicketTextPrefix . $AcknowledgeNameField
            }
            my $DynamicField = $Kernel::OM->Get('DynamicField')->DynamicFieldGet(
                'Name' => $AcknowledgeNameField,
            );
            if ( !IsHashRefWithData($DynamicField) ) {
                $Kernel::OM->Get('Log')->Log(
                    Priority => 'error',
                    Message  => "SysMon Mail DF <" . $AcknowledgeNameField
                        . "> does not exist.",
                );
            }
            else {
                $Param->{GetParam}->{ 'X-KIX-DynamicField-' . $AcknowledgeNameField }
                    = $Self->{Config}->{AcknowledgeName} || 'Nagios';
            }
        }
    }

    # set AffectedAssetNameField (thus linking ticket with asset and set inci state)
    if ( $Self->{Config}->{AffectedAssetName} ) {
        my $AffectedAssetNameField = $Self->{Config}->{AffectedAssetName};
        my $DynamicField = $Kernel::OM->Get('DynamicField')->DynamicFieldGet(
            'Name' => $AffectedAssetNameField,
        );
        if ( !IsHashRefWithData($DynamicField) ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "SysMon Mail DF <" . $AffectedAssetNameField
                    . "> does not exist.",
            );
        }
        else {
            my $AssetID = "";

            # search for CI by SysMonHost-Name...
            my $ConfigItemIDs = $Self->{ConfigItemObject}->ConfigItemSearchExtended(
                Name => $Self->{SysMonXHost},
            );
            if ( IsArrayRefWithData($ConfigItemIDs) ) {
                if ( scalar @{$ConfigItemIDs} > 1 ) {
                    $Kernel::OM->Get('Log')->Log(
                        Priority => 'notice',
                        Message  => "Multiple assets for SysMon host <"
                            .$Self->{Host}
                            . "> found, using first item only!",
                    );
                }
                $AssetID = $ConfigItemIDs->[0];
            }

            # if no CI found by SysMonHost-Name, search for SysMonService...
            else {
              $ConfigItemIDs = $Self->{ConfigItemObject}->ConfigItemSearchExtended(
                  Name => $Self->{SysMonXService},
              );
              if (  IsArrayRefWithData($ConfigItemIDs) ) {
                    if ( scalar @{$ConfigItemIDs} > 1 ) {
                        $Kernel::OM->Get('Log')->Log(
                            Priority => 'notice',
                            Message  => "Multiple assets for SysMon service <"
                                .$Self->{Host}
                                . "> found, using first item only!",
                        );
                    }
                    $AssetID = $ConfigItemIDs->[0];
              }
            }

            # set affected asset in ticket...
            if ( $AssetID ) {
              $Param->{GetParam}->{ 'X-KIX-DynamicField-' . $AffectedAssetNameField } = $AssetID;
            }

            $Kernel::OM->Get('Log')->Log(
                Priority => 'debug',
                Message  => 'SysMon Mail: asset found <$AssetID>.',
            );

        }
    }

    # set log message
    $Self->_LogMessage( MessageText => 'New Ticket' );

    return 1;
}

# Side Effect Notice: this sub modifies param hash!
sub _TicketDrop {
    my ( $Self, $Param ) = @_;

    # No existing ticket and no open condition -> drop silently
    $Param->{GetParam}->{'X-KIX-Ignore'} = 'yes';
    $Kernel::OM->Get('Log')->Log(
        Priority => 'notice',
        Message  => "Mail dropped - no matching ticket found "
            . "nor new ticket on this system monitoring state!",
    );

    return 1;
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
