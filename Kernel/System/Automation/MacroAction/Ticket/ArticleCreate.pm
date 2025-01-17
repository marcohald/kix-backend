# --
# Modified version of the work: Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-AGPL for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Automation::MacroAction::Ticket::ArticleCreate;

use strict;
use warnings;
use utf8;

use MIME::Base64;

use Kernel::System::VariableCheck qw(:all);

use base qw(Kernel::System::Automation::MacroAction::Ticket::Common);

our @ObjectDependencies = (
    'Log',
    'Ticket',
    'User',
);

=head1 NAME

Kernel::System::Automation::MacroAction::Ticket::ArticleCreate - A module to create an article

=head1 SYNOPSIS

All ArticleCreate functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item Describe()

Describe this macro action module.

=cut

sub Describe {
    my ( $Self, %Param ) = @_;

    $Self->Description(Kernel::Language::Translatable('Creates an article for a ticket.'));
    $Self->AddOption(
        Name        => 'Channel',
        Label       => Kernel::Language::Translatable('Channel'),
        Description => Kernel::Language::Translatable('(Optional) The channel of the new article. "note" will be used if omitted.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'SenderType',
        Label       => Kernel::Language::Translatable('Sender Type'),
        Description => Kernel::Language::Translatable('(Optional) The sender type of the new article. "agent" will be used if omitted.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'From',
        Label       => Kernel::Language::Translatable('From'),
        Description => Kernel::Language::Translatable('(Optional) The email address of the sender for the new article. Agent data will be used if omitted.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'To',
        Label       => Kernel::Language::Translatable('To'),
        Description => Kernel::Language::Translatable('(Optional) The email addresses of the receiver of the new article.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'Cc',
        Label       => Kernel::Language::Translatable('Cc'),
        Description => Kernel::Language::Translatable('(Optional) The email addresses of the Cc receiver of the new article.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'Bcc',
        Label       => Kernel::Language::Translatable('Bcc'),
        Description => Kernel::Language::Translatable('(Optional) The email addresses of the Bcc receiver of the new article.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'CustomerVisible',
        Label       => Kernel::Language::Translatable('Show in Customer Portal'),
        Description => Kernel::Language::Translatable('If the new article is visible for customers'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'Subject',
        Label       => Kernel::Language::Translatable('Subject'),
        Description => Kernel::Language::Translatable('The subject of the new article.'),
        Required    => 1,
    );
    $Self->AddOption(
        Name        => 'Body',
        Label       => Kernel::Language::Translatable('Body'),
        Description => Kernel::Language::Translatable('The text of the new article.'),
        Required    => 1,
    );
    $Self->AddOption(
        Name        => 'AccountTime',
        Label       => Kernel::Language::Translatable('Account Time'),
        Description => Kernel::Language::Translatable('An integer value which will be accounted for the new article (as minutes).'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'AttachmentObject1',
        Label       => Kernel::Language::Translatable('Attachment Object 1'),
        Description => Kernel::Language::Translatable('An attachment object containing the attributes "Filename", "ContentType" and "Content" generated by the macro action "AssembleObject". Binary content needs to be base64 coded.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'AttachmentObject2',
        Label       => Kernel::Language::Translatable('Attachment Object 2'),
        Description => Kernel::Language::Translatable('An attachment object containing the attributes "Filename", "ContentType" and "Content" generated by the macro action "AssembleObject". Binary content needs to be base64 coded.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'AttachmentObject3',
        Label       => Kernel::Language::Translatable('Attachment Object 3'),
        Description => Kernel::Language::Translatable('An attachment object containing the attributes "Filename", "ContentType" and "Content" generated by the macro action "AssembleObject". Binary content needs to be base64 coded.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'AttachmentObject4',
        Label       => Kernel::Language::Translatable('Attachment Object 4'),
        Description => Kernel::Language::Translatable('An attachment object containing the attributes "Filename", "ContentType" and "Content" generated by the macro action "AssembleObject". Binary content needs to be base64 coded.'),
        Required    => 0,
    );
    $Self->AddOption(
        Name        => 'AttachmentObject5',
        Label       => Kernel::Language::Translatable('Attachment Object 5'),
        Description => Kernel::Language::Translatable('An attachment object containing the attributes "Filename", "ContentType" and "Content" generated by the macro action "AssembleObject". Binary content needs to be base64 coded.'),
        Required    => 0,
    );

    # FIXME: add if necessary
    # Charset          => 'utf-8',                                # 'ISO-8859-15'
    # MimeType         => 'text/plain',
    # HistoryType      => 'OwnerUpdate',                          # EmailCustomer|Move|AddNote|PriorityUpdate|...
    # HistoryComment   => 'Some free text!',
    # UnlockOnAway     => 1,                                      # Unlock ticket if owner is away
    # ForceNotificationToUserID
    # ExcludeNotificationToUserID
    # ExcludeMuteNotificationToUserID

    $Self->AddResult(
        Name        => 'NewArticleID',
        Description => Kernel::Language::Translatable('The ID of the new article.'),
    );

    return;
}

=item Run()

Run this module. Returns 1 if everything is ok.

Example:
    my $Success = $Object->Run(
        TicketID => 123,
        Config   => {
            Channel          => 'note',
            SenderType       => 'agent',
            Subject          => 'some short description',
            Body             => 'the message text',
        },
        UserID   => 123
    );

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # check incoming parameters
    return if !$Self->_CheckParams(%Param);

    # FIXME: needed?
    # convert scalar items into array references
    for my $Attribute ( qw(ForceNotificationToUserID ExcludeNotificationToUserID ExcludeMuteNotificationToUserID) ) {
        if ( IsStringWithData( $Param{Config}->{$Attribute} ) ) {
            $Param{Config}->{$Attribute} = $Self->_ConvertScalar2ArrayRef(
                Data => $Param{Config}->{$Attribute},
            );
        }
    }

    # if "From" is not set use current user
    if ( !$Param{Config}->{From} ) {
        my %Contact = $Kernel::OM->Get('Contact')->ContactGet(
            UserID => $Param{UserID},
        );
        if (IsHashRefWithData(\%Contact)) {
            $Param{Config}->{From} = $Contact{Fullname} . ' <' . $Contact{Email} . '>';
        }
    }

    $Param{Config}->{CustomerVisible} = $Param{Config}->{CustomerVisible} // 0,
    $Param{Config}->{Channel} = $Param{Config}->{Channel} || 'note';
    $Param{Config}->{SenderType} = $Param{Config}->{SenderType} || 'agent';
    $Param{Config}->{Charset} = $Param{Config}->{Charset} || 'utf-8';
    $Param{Config}->{MimeType} = $Param{Config}->{MimeType} || 'text/html';
    $Param{Config}->{HistoryType} = $Param{Config}->{HistoryType} || 'AddNote';
    $Param{Config}->{HistoryComment} = $Param{Config}->{HistoryComment} || 'Added during job execution.';

    if ( $Param{Config}->{Channel} ) {
        my $ChannelID = $Kernel::OM->Get('Channel')->ChannelLookup( Name => $Param{Config}->{Channel} );

        if ( !$ChannelID ) {
            $Kernel::OM->Get('Automation')->LogError(
                Referrer => $Self,
                Message  => "Couldn't create article for ticket $Param{TicketID}. Can't find channel with name \"$Param{Config}->{Channel}\"!",
                UserID   => $Param{UserID}
            );
            return;
        }
    }

    if ( $Param{Config}->{SenderType} ) {
        my $SenderTypeID = $Kernel::OM->Get('Ticket')->ArticleSenderTypeLookup( SenderType => $Param{Config}->{SenderType} );

        if ( !$SenderTypeID ) {
            $Kernel::OM->Get('Automation')->LogError(
                Referrer => $Self,
                Message  => "Couldn't create article for ticket $Param{TicketID}. Can't find sender type with name \"$Param{Config}->{SenderType}\"!",
                UserID   => $Param{UserID}
            );
            return;
        }
    }

    # replace placeholders in non-richtext attributes
    for my $Attribute ( qw(Channel SenderType To From Cc Bcc AccountTime) ) {
        next if !defined $Param{Config}->{$Attribute};

        $Param{Config}->{$Attribute} = $Self->_ReplaceValuePlaceholder(
            %Param,
            Value => $Param{Config}->{$Attribute}
        );
    }

    # replace placeholders in attachment attributes
    for my $ID ( 1..5 ) {
        next if !defined $Param{Config}->{"AttachmentObject$ID"};

        $Param{Config}->{"AttachmentObject$ID"} = $Self->_ReplaceValuePlaceholder(
            %Param,
            Value => $Param{Config}->{"AttachmentObject$ID"},
        );
    }

    $Param{Config}->{Subject} = $Self->_ReplaceValuePlaceholder(
        %Param,
        Value     => $Param{Config}->{Subject},
        Translate => 1
    );

    $Param{Config}->{Body} = $Self->_ReplaceValuePlaceholder(
        %Param,
        Value     => $Param{Config}->{Body},
        Translate => 1,
        Richtext  => 1
    );

    # prepare subject if necessary
    if ( $Param{Config}->{Channel} && $Param{Config}->{Channel} eq 'email' ) {
        my %Ticket = $Kernel::OM->Get('Ticket')->TicketGet(
            TicketID => $Param{TicketID},
        );
        if (IsHashRefWithData(\%Ticket)) {
            $Param{Config}->{Subject} = $Kernel::OM->Get('Ticket')->TicketSubjectBuild(
                TicketNumber => $Ticket{TicketNumber},
                Subject      => $Param{Config}->{Subject},
                Type         => 'New'
            );
        }
    }

    # prepare attachments
    my @Attachments;
    foreach my $ID ( 1..5 ) {
        next if !$Param{Config}->{"AttachmentObject$ID"} || !IsObject($Param{Config}->{"AttachmentObject$ID"}, $Kernel::OM->GetModuleFor('Automation::Helper::Object'));

        my $Attachment = $Param{Config}->{"AttachmentObject$ID"}->AsObject();
        if ( IsBase64($Attachment->{Content}) ) {
            $Attachment->{Content} = MIME::Base64::decode_base64($Attachment->{Content});
        }
        # convert back from byte sequence to prevent double encoding when storing the attachment
        utf8::decode($Attachment->{Content});

        push @Attachments, $Attachment;
    }

    my $ArticleID = $Kernel::OM->Get('Ticket')->ArticleCreate(
        %{ $Param{Config} },
        TimeUnit   => $Param{Config}->{AccountTime},
        TicketID   => $Param{TicketID},
        UserID     => $Param{UserID},
        Attachment => \@Attachments
    );

    if ( !$ArticleID ) {
        $Kernel::OM->Get('Automation')->LogError(
            Referrer => $Self,
            Message  => "Couldn't update ticket $Param{TicketID} - creating new article failed!",
            UserID   => $Param{UserID}
        );
        return;
    }

    $Self->SetResult(Name => 'NewArticleID', Value => $ArticleID);

    return 1;
}

=item ValidateConfig()

Validates the parameters of the config.

Example:
    my $Valid = $Self->ValidateConfig(
        Config => {}                # required
    );

=cut

sub ValidateConfig {
    my ( $Self, %Param ) = @_;

    return if !$Self->SUPER::ValidateConfig(%Param);

    if ( $Param{Config}->{AccountTime} && $Param{Config}->{AccountTime} !~ m/^(<|&lt;)KIX_.+>|\$\{\w+\}$/ ) {
        return 1 if (
            $Param{Config}->{AccountTime} =~ m/^-?\d+$/ &&
            $Param{Config}->{AccountTime} <= 86400 &&
            $Param{Config}->{AccountTime} >= -86400
        );

        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Validation of parameter \"AccountTime\" failed."
        );
        return;
    }

    return 1;
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
