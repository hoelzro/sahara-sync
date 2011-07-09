package SaharaSync::Config::Test;

use strict;
use warnings;
use parent 'Test::Class';

require File::Temp;
require JSON;

use Test::Deep::NoTest qw(cmp_details deep_diag);
use Test::More;
use Test::Exception;

__PACKAGE__->SKIP_CLASS(1);

my %file_tests;
my $run_file_tests;

sub File : ATTR(CODE) {
    my ( $package, $symbol ) = @_;

    $file_tests{$package . '::' . *{$symbol}{NAME}} = 1;
}

sub required_params {
    die "required_params needs to be implemented in SaharaSync::Config::Test subclasses!\n";
}

sub optional_params {
    die "optional_params needs to be implemented in SaharaSync::Config::Test subclasses!\n";
}

sub config_class {
    die "config_class needs to be implemented in SaharaSync::Config::Test subclasses!\n";
}

sub file_formats {
    return {
        json => 'JSON::encode_json',
    };
}

sub bad_params {
    die "bad_params needs to be implemented in SaharaSync::Config::Test subclasses!\n";
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

sub check_params {
    my ( $self, $config, $params ) = @_;

    my $tb = $self->builder;

    unless($config) {
        $tb->ok(0, "config is not defined!");
        return;
    }

    my $optional = $self->optional_params;
    foreach my $k (keys %$optional) {
        next if exists $params->{$k};

        my $v = $optional->{$k}{'default'};
        $params->{$k} = $v;
    }
    my @diag;
    foreach my $k (keys %$params) {
        my $got      = $config->$k();
        my $expected = $params->{$k};

        my ( $ok, $stack ) = cmp_details($got, $expected);

        unless($ok) {
            push @diag, "attribute '$k' doesn't match: " . deep_diag($stack);
        }
    }
    return $tb->ok(!@diag) || diag(join("\n", map { "  $_" } @diag));
}

sub test_empty_params : Test(2) {
    my ( $self ) = @_;

    my $required = $self->required_params;

    if(%$required) {
        my $re = join('|', keys %$required);
        throws_ok {
            $self->config_class->new({});
        } qr/Attribute.*($re).*is\s+required/, 'Cannot build a config object with no parameters';
        pass;
    } else {
        my $config;
        lives_ok {
            $config = $self->config_class->new({});
        } 'Building a config object with no parameters should succeed';

        $self->check_params($config, {});
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
            plan tests => @required * 2;

            foreach my $params (@required) {
                my $config;
                lives_ok {
                    $config = $class->new($params);
                } "Building a config object with only required params should succeed";

                $self->check_params($config, $params);
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
            plan tests => $count * 2;

            foreach my $k (%$optional) {
                my $values = $optional->{$k}{'values'};
                foreach my $v (@$values) {
                    my %params = ( %required, $k => $v );

                    my $config;
                    lives_ok {
                        $config = $class->new(\%params);
                    } "Building a config object with a $k parameter should succeed";
                    $self->check_params($config, \%params);
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

sub test_bad_params : Test {
    my ( $self ) = @_;

    my %required   = %{ $self->required_params };
    my $bad_params = $self->bad_params;
    my $class      = $self->config_class;

    for my $k (keys %required) {
        my $v = $required{$k};
        if(ref($v) eq 'ARRAY') {
            $required{$k} = $v->[0];
        }
    }

    if(@$bad_params) {
        subtest 'Testing bad parameters' => sub {
            plan tests => @$bad_params / 2;

            for(my $i = 0; $i < @$bad_params; $i += 2) {
                my ( $k, $v ) = @{$bad_params}[$i, $i + 1];
                my %params = ( %required, $k => $v );

                throws_ok {
                    $class->new(\%params);
                } qr/Validation failed/;
            }
        };
    } else {
        return "$class has no bad parameter values";
    }
}

sub test_nonexistent_file :Test :File {
    my ( $self ) = @_;

    my %required = %{ $self->required_params };
    my $class    = $self->config_class;

    for my $k (keys %required) {
        my $v = $required{$k};
        if(ref($v) eq 'ARRAY') {
            $required{$k} = $v->[0];
        }
    }

    my $temp = File::Temp->new(SUFFIX => '.json');
    print $temp JSON::encode_json(\%required);
    close $temp;
    unlink $temp->filename;
    throws_ok {
        $class->new_from_file($temp->filename);
    } qr/Unable to read/, "Loading a non-existent file should fail";
}

sub test_bad_permissions :Test :File {
    my ( $self ) = @_;

    my %required = %{ $self->required_params };
    my $class    = $self->config_class;

    for my $k (keys %required) {
        my $v = $required{$k};
        if(ref($v) eq 'ARRAY') {
            $required{$k} = $v->[0];
        }
    }

    my $temp = File::Temp->new(SUFFIX => '.json');
    print $temp JSON::encode_json(\%required);
    close $temp;
    chmod 0000, $temp->filename;
    throws_ok {
        $class->new_from_file($temp->filename);
    } qr/Unable to read/, "Loading a non-existent file should fail";
}

sub test_bad_content :Test :File {
    my ( $self ) = @_;

    my $class = $self->config_class;

    my $temp = File::Temp->new(SUFFIX => '.json');
    print $temp "random text!!!\n";
    close $temp;
    throws_ok {
        $class->new_from_file($temp->filename);
    } qr/Error parsing/, "Loading a non-existent file should fail";
}

sub runtests {
    my ( $class ) = @_;

    my @test_classes = Test::Class->_test_classes;
    @test_classes = grep { $_ ne __PACKAGE__ && $_->isa(__PACKAGE__) } @test_classes;

    my @proxy_classes;

    my $file    = __FILE__;

    foreach my $test_class (@test_classes) {
        my $config_class = $test_class->config_class;
        my $formats      = $test_class->file_formats;

        foreach my $ext (keys %$formats) {
            my $method  = $formats->{$ext};
            my $line_no = __LINE__ + 3; # the actual start is 3 lines down
            my $ok = eval <<PERL;
#line $line_no '$file'
package ${test_class}::Proxy::${ext};

use strict;
use warnings;
use parent -norequire, '$test_class';

sub config_class {
    return '${config_class}::Proxy::${ext}';
}

package ${config_class}::Proxy::${ext};

use strict;
use warnings;
use parent '$config_class';

sub new {
    my ( \$class, \%params );

    if(\@_ == 2) {
        \$class  = shift;
        \%params = \%{ \$_[0] };
    } else {
        ( \$class, \%params ) = \@_;
    }

    my \$temp = File::Temp->new(SUFFIX => '.${ext}');
    print \$temp ${method}(\\\%params);
    close \$temp;

    return ${config_class}->new_from_file(\$temp->filename);
}

1;
PERL
            unless($ok) {
                die "PERL EVALUATION FAILED! THE DEVELOPER F'ED UP! ($@)";
            }
            push @proxy_classes, $test_class . '::Proxy::' . $ext;
        }

        my $line_no = __LINE__ + 3;
        my $ok      = eval <<PERL;
#line $line_no '$file'
package ${test_class}::Proxy::ExpandHashRef;

use strict;
use warnings;
use parent -norequire, '$test_class';

sub config_class {
    return '${config_class}::Proxy::ExpandHashRef';
}

package ${config_class}::Proxy::ExpandHashRef;

use strict;
use warnings;
use parent '$config_class';

sub new {
    my ( \$class, \%params );

    if(\@_ == 2) {
        \$class  = shift;
        \%params = \%{ \$_[0] };
    } else {
        ( \$class, \%params ) = \@_;
    }

    return ${config_class}->new(\%params);
}

1;
PERL
        unless($ok) {
            die "PERL EVALUATION FAILED! THE DEVELOPER F'ED UP! ($@)";
        }
        push @proxy_classes, $test_class . '::Proxy::ExpandHashRef';
    }
    my $num_tests = 0;

    $run_file_tests = 1;
    foreach my $class (@test_classes) {
        $num_tests += $class->expected_tests;
    }
    $run_file_tests = 0;
    foreach my $class(@proxy_classes) {
        $num_tests += $class->expected_tests;
    }

    plan tests => $num_tests;

    $run_file_tests = 1;
    Test::Class->runtests(@test_classes);
    $run_file_tests = 0;
    unless(Test::Class->builder->is_passing) {
        Test::Class->builder->BAIL_OUT('Tests for config failed; not running transparent tests');
    }

    Test::Class->runtests(@proxy_classes);
}

__PACKAGE__->add_filter(sub {
    my ( $class, $method ) = @_;

    return 1 if $run_file_tests;
    return !$file_tests{$class . '::' . $method};
});
1;
