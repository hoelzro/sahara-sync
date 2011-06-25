use Module::Build;

my $builder = Module::Build->new(
    module_name          => 'SaharaSync::Hostd',
    recursive_test_files => 1,
    use_tap_harness      => 1,
    tap_harness_args     => {
        lib => ['lib', 't/lib', 'json-streaming-reader/lib'],
    },
##{ $plugin->get_prereqs ##}
##{ $plugin->get_default('share_dir') ##}
);
$builder->create_build_script;
