# --
# Modified version of the work: Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-AGPL for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::DynamicField::Driver::Base;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'DynamicFieldValue',
    'Log',
);

=head1 NAME

Kernel::System::DynamicField::Driver::Base - common fields backend functions

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

sub ValueGet {
    my ( $Self, %Param ) = @_;

    my $DFValue = $Kernel::OM->Get('DynamicFieldValue')->ValueGet(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
    );

    return if !$DFValue;
    return if !IsArrayRefWithData($DFValue);
    return if !IsHashRefWithData( $DFValue->[0] );

    # extract real values
    my @ReturnData;
    for my $Item ( @{$DFValue} ) {
        push @ReturnData, $Item->{ValueText}
    }

    return \@ReturnData;
}

sub ValueIsDifferent {
    my ( $Self, %Param ) = @_;

    # special cases where the values are different but they should be reported as equals
    if (
        !defined $Param{Value1}
        && ref $Param{Value2} eq 'ARRAY'
        && !IsArrayRefWithData( $Param{Value2} )
        )
    {
        return
    }
    if (
        !defined $Param{Value2}
        && ref $Param{Value1} eq 'ARRAY'
        && !IsArrayRefWithData( $Param{Value1} )
        )
    {
        return
    }

    # compare the results
    return DataIsDifferent(
        Data1 => \$Param{Value1},
        Data2 => \$Param{Value2}
    );
}

sub ValueDelete {
    my ( $Self, %Param ) = @_;

    my $Success = $Kernel::OM->Get('DynamicFieldValue')->ValueDelete(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
        UserID   => $Param{UserID},
    );

    return $Success;
}

sub AllValuesDelete {
    my ( $Self, %Param ) = @_;

    my $Success = $Kernel::OM->Get('DynamicFieldValue')->AllValuesDelete(
        FieldID => $Param{DynamicFieldConfig}->{ID},
        UserID  => $Param{UserID},
    );

    return $Success;
}

sub HasBehavior {
    my ( $Self, %Param ) = @_;

    # return fail if Behaviors hash does not exists
    return if !IsHashRefWithData( $Self->{Behaviors} );

    # return success if the dynamic field has the expected behavior
    return IsPositiveInteger( $Self->{Behaviors}->{ $Param{Behavior} } );

    # otherwise return fail
    return;
}

sub SearchFieldPreferences {
    my ( $Self, %Param ) = @_;

    my @Preferences = (
        {
            Type        => '',
            LabelSuffix => '',
        },
    );

    return \@Preferences;
}

=item EditLabelRender()

creates the label HTML to be used in edit masks.

    my $LabelHTML = $BackendObject->EditLabelRender(
        DynamicFieldConfig => $DynamicFieldConfig,      # complete config of the DynamicField
        FieldName          => 'TheField',               # the value to be set on the 'for' attribute
        AdditionalText     => 'Between'                 # other text to be placed next to FieldName
        Mandatory          => 1,                        # 0 or 1,
    );

=cut

sub EditLabelRender {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(DynamicFieldConfig FieldName)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # check DynamicFieldConfig (general)
    if ( !IsHashRefWithData( $Param{DynamicFieldConfig} ) ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "The field configuration is invalid",
        );
        return;
    }

    # check DynamicFieldConfig (internally)
    for my $Needed (qw(Label)) {
        if ( !$Param{DynamicFieldConfig}->{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed in DynamicFieldConfig!"
            );
            return;
        }
    }

    my $Name      = $Param{FieldName};
    my $LabelText = $Param{DynamicFieldConfig}->{Label};

    my $LabelID    = 'Label' . $Param{FieldName};
    my $HTMLString = '';

    if ( $Param{Mandatory} ) {

        # opening tag
        $HTMLString = <<"EOF";
<label id="$LabelID" for="$Name" class="Mandatory">
    <span class="Marker">*</span>
EOF
    }
    else {

        # opening tag
        $HTMLString = <<"EOF";
<label id="$LabelID" for="$Name">
EOF
    }

    # text
    $HTMLString .= $Param{LayoutObject}->Ascii2Html(
        Text => $Param{LayoutObject}->{LanguageObject}->Translate("$LabelText")
    );
    if ( $Param{AdditionalText} ) {
        $HTMLString .= " (";
        $HTMLString .= $Param{LayoutObject}->Ascii2Html(
            Text => $Param{LayoutObject}->{LanguageObject}->Translate("$Param{AdditionalText}")
        );
        $HTMLString .= ")";
    }
    $HTMLString .= ":\n";

    # closing tag
    $HTMLString .= <<"EOF";
</label>
EOF

    return $HTMLString;
}

sub ObjectMatch {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # return false if field is not defined
    return 0 if ( !defined $Param{ObjectAttributes}->{$FieldName} );

    my @Values;
    if ( ref  $Param{ObjectAttributes}->{$FieldName} eq 'ARRAY' ) {
        @Values = @{  $Param{ObjectAttributes}->{$FieldName} };
    }
    else {
        @Values = (  $Param{ObjectAttributes}->{$FieldName} );
    }

    my $Match = 0;
    # search in all values for this attribute
    VALUE:
    for my $AttributeValue ( @Values ) {

        next VALUE if !defined $AttributeValue;

        # only need to match one
        if ( $Param{Value} eq $AttributeValue ) {
            $Match = 1;
            last VALUE;
        }
    }

    return $Match;
}

sub HTMLDisplayValueRender {
    my ( $Self, %Param ) = @_;

    return $Self->DisplayValueRender(%Param);
}

sub ShortDisplayValueRender {
    my ( $Self, %Param ) = @_;

    return $Self->DisplayValueRender(%Param);
}

sub DisplayKeyRender {
    my ( $Self, %Param ) = @_;

    return $Self->DisplayValueRender(%Param);
}

sub GetCacheDependencies {
    my ( $Self, %Param ) = @_;

    return;
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
