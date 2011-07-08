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

sub _required_perms_helper {
    my ( $required, $results, $current, @keys ) = @_;

    if(@keys) {
        my $key    = shift @keys;
        my $values = $required->{$key};

        if(ref($values) eq 'ARRAY') {
            foreach my $value (@$values) {
                _required_perms_helper($required, $results, { %$current, $key => $value }, @keys);
            }
        } else {
            $current->{$key} = $values;
            _required_perms_helper($required, $results, $current, @keys);
        }
    } else {
        push @$results, $current;
    }
}

sub required_permutations {
    my ( $self ) = @_;

    my $required = $self->required_params;
    my @permutations;
    _required_perms_helper($required, \@permutations, {}, keys %$required);
    return @permutations;
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

    my @required = $self->required_permutations;
    my $class    = $self->config_class;

    unless(@required) {
        return "$class has no required params";
    } else {
        subtest 'Testing required parameters' => sub {
            plan tests => scalar(@required);

            foreach my $params (@required) {
                lives_ok {
                    $class->new($params);
                } "Building a config object with only required params should succeed";
            }
        };
    }
}

sub test_missing_required_param : Test {
    my ( $self ) = @_;

    my @required_names = keys %{ $self->required_params };
    my @required       = $self->required_permutations;
    my $class          = $self->config_class;

    unless(@required) {
        return "$class has no required params";
    } else {
        subtest 'Testing missing required params' => sub {
            plan tests => @required * @required_names;

            foreach my $param (@required) {
                foreach my $k (@required_names) {
                    my %new_params = %$param;
                    delete $new_params{$k};

                    throws_ok {
                        $class->new(\%new_params);
                    } qr/Attribute.*$k.*is\s+required/, "Building a config object without a $k parameter should fail"
                }
            }
        };
    }
}

sub test_individual_optional_params : Test {
    my ( $self ) = @_;

    my %required = %{ $self->required_params };
    my $optional = $self->optional_params;
    my $class    = $self->config_class;

    foreach my $k (keys %required) {
        my $v = $required{$k};
        if(ref($v) eq 'ARRAY') {
            $required{$k} = $v->[0];
        }
    }

    unless(%$optional) {
        return "$class has no optional params";
    } else {
        my $count = 0;
        foreach my $v (values %$optional) {
            my $values = $v->{'values'};
            $count += @$values;
        }

        subtest 'Testing optional params' => sub {
            plan tests => $count;

            foreach my $k (%$optional) {
                my $values = $optional->{$k}{'values'};
                foreach my $v (@$values) {
                    my %params = ( %required, $k => $v );

                    lives_ok {
                        $class->new(\%params);
                    } "Building a config object with a $k parameter should succeed";
                }
            }
        };
    }
}

sub test_unknown_param : Test {
    my ( $self ) = @_;

    my %required = %{ $self->required_params };
    my $optional = $self->optional_params;
    my $class    = $self->config_class;

    for my $k (keys %required) {
        my $v = $required{$k};
        if(ref($v) eq 'ARRAY') {
            $required{$k} = $v->[0];
        }
    }

    my %good_params = map { $_ => 1 } (keys %required, keys %$optional);
    my $bad_param   = 'aaaaaa';
    $bad_param++ while exists $good_params{$bad_param};

    my %params = (
        %required,
        $bad_param => 1,
    );

    throws_ok {
        $class->new(\%params);
    } qr/Found unknown attribute/, "Cannot build a config object with an invalid parameter";
}

1;
