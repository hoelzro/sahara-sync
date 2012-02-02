package DB;

use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

sub DB {}

my %package_test_methods;
my %package_method_timings;

sub sub {
    my $fn = $DB::sub;
    unless(ref($fn)) {
        $fn = \&{$fn};
    }
    for(1) {
        last if ref $DB::sub;

        my ( $package, $method ) = $DB::sub =~ /(.*)::(.*)/;

        last if $package eq 'Test::Class';
        last if $package eq 'UNIVERSAL';

        last unless $package->isa('Test::Class');

        my $methods = $package_test_methods{$package};
        unless($methods) {
            $methods = $package_test_methods{$package} = {};

            my @method_list = $package->_get_methods(qw/startup shutdown setup teardown test/);
            @{$methods}{@method_list} = ( 1 ) x @method_list;
        }
        last unless $methods->{$method};

        my @return_values;
        my $return_value;
        my $exception;

        my $start = clock_gettime(CLOCK_MONOTONIC);

        eval {
            if(defined wantarray) {
                if(wantarray) {
                    @return_values = &$DB::sub;
                } else {
                    $return_value = &$DB::sub;
                }
            } else {
                &$DB::sub;
            }
        };

        if($@) {
            $exception = $@;
        }

        my $end     = clock_gettime(CLOCK_MONOTONIC);
        my $delta_t = $end - $start;

        my $package_timings = $package_method_timings{$package};
        unless($package_timings) {
            $package_timings = $package_method_timings{$package} = {};
        }
        my $method_timings = $package_timings->{$method};
        unless($method_timings) {
            $method_timings = $package_timings->{$method} = {
                total => 0,
                count => 0,
                min   => 1_000_000, # should be big enough
                max   => 0,
            };
        }

        $method_timings->{'total'} += $delta_t;
        $method_timings->{'count'}++;

        if($delta_t > $method_timings->{'max'}) {
            $method_timings->{'max'} = $delta_t;
        }

        if($delta_t < $method_timings->{'min'}) {
            $method_timings->{'min'} = $delta_t;
        }

        if(defined $exception) {
            die $exception;
        }

        if(defined wantarray) {
            if(wantarray) {
                return @return_values;
            } else {
                return $return_value;
            }
        } else {
            return;
        }
    }
    return &$DB::sub;
}

END {
    foreach my $package (sort keys %package_method_timings) {
        print STDERR "$package\n";
        print STDERR '=' x length($package), "\n";
        print STDERR "\n";

        my $method_timings = $package_method_timings{$package};

        foreach my $timings (values %{$method_timings}) {
            my ( $total, $count ) = @{$timings}{qw/total count/};

            $timings->{'average'} = $total / $count;
        }

        my @sorted_by_average = sort {
            $method_timings->{$a}{'average'} <=>
            $method_timings->{$b}{'average'}
        } keys(%{$method_timings});

        foreach my $method (@sorted_by_average) {
            print STDERR "  $method\n";
            print STDERR '  ', '-' x length($method), "\n";
            print STDERR "\n";

            my $timings = $method_timings->{$method};
            my ( $total, $count, $min, $max, $average ) = @{$timings}{qw/total count min max average/};

            printf STDERR "    total   = %.2f\n", $total;
            print  STDERR "    count   = $count\n";
            printf STDERR "    average = %.2f\n", $average;
            printf STDERR "    min     = %.2f\n", $min;
            printf STDERR "    max     = %.2f\n", $max;
            print  STDERR "\n";
        }
    }
}

1;
