package SaharaSync::Config::Test;

use strict;
use warnings;
use parent 'Test::Class';

use Test::More;
use Test::Exception;

__PACKAGE__->SKIP_CLASS(1);

sub required_params {
    die "required_params needs to be implemented in SaharaSync::Config::Test subclasses!\n";
}

sub optional_params {
    die "optional_params needs to be implemented in SaharaSync::Config::Test subclasses!\n";
}

sub config_class {
    die "config_class needs to be implemented in SaharaSync::Config::Test subclasses!\n";
}

sub test_use_ok :Test(startup => 1) {
    my ( $self ) = @_;

    use_ok($self->config_class);
}

sub test_empty_params : Test {
    my ( $self ) = @_;

    my $required = $self->required_params;

    if(%$required) {
        my $re = join('|', keys %$required);
        throws_ok {
            $self->config_class->new({});
        } qr/Attribute.*($re).*is\s+required/, 'Cannot build a config object with no parameters';
    } else {
        lives_ok {
            $self->config_class->new({});
        } 'Building a config object with no parameters should succeed';
    }
}

sub test_required_params_only : Test {
    my ( $self ) = @_;

    my $required = $self->required_params;
    my $class    = $self->config_class;

    unless(%$required) {
        return "$class has no required params";
    } else {
        lives_ok {
            $class->new($required);
        } "Building a config object with only required params should succeed";
    }
}

sub test_missing_required_param : Test {
    my ( $self ) = @_;

    my $required = $self->required_params;
    my $class    = $self->config_class;

    unless(%$required) {
        return "$class has no required params";
    } else {
        subtest 'Testing required params' => sub {
            plan tests => scalar(keys(%$required));

            foreach my $k (keys %$required) {
                my %params = %$required;
                delete $params{$k};

                throws_ok {
                    $class->new(\%params);
                } qr/Attribute.*$k.*is\s+required/, "Building a config object without a $k parameter should fail";
            }
        };
    }
}

sub test_individual_optional_params : Test {
    my ( $self ) = @_;

    my $required = $self->required_params;
    my $optional = $self->optional_params;
    my $class    = $self->config_class;

    unless(%$optional) {
        return "$class has no optional params";
    } else {
        subtest 'Testing optional params' => sub {
            plan tests => scalar(keys(%$optional));

            foreach my $k (keys %$optional) {
                my $v      = $optional->{$k}{'value'};
                my %params = ( %$required, $k => $v );

                lives_ok {
                    $class->new(\%params);
                } "Building a config object with a $k parameter should succeed";
            }
        };
    }
}

sub test_unknown_param : Test {
    my ( $self ) = @_;

    my $required = $self->required_params;
    my $optional = $self->optional_params;
    my $class    = $self->config_class;

    my %good_params = map { $_ => 1 } (keys %$required, keys %$optional);
    my $bad_param   = 'aaaaaa';
    $bad_param++ while exists $good_params{$bad_param};

    my %params = (
        %$required,
        $bad_param => 1,
    );

    throws_ok {
        $class->new(\%params);
    } qr/Found unknown attribute/, "Cannot build a config object with an invalid parameter";
}

1;
