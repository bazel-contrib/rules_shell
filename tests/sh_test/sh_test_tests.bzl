"""Analysis tests for sh_test."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "subjects")
load("@rules_testing//lib:util.bzl", "util")
load("//shell:sh_binary_info.bzl", "ShBinaryInfo")
load("//shell:sh_test.bzl", "sh_test")

def _test_providers(name):
    util.helper_target(
        sh_test,
        name = name + "_subject",
        srcs = ["pass.sh"],
        env = {"FOO": "bar"},
        env_inherit = ["INHERITED"],
    )
    analysis_test(
        name = name,
        impl = _test_providers_impl,
        target = name + "_subject",
    )

def _test_providers_impl(env, target):
    subject = env.expect.that_target(target)
    subject.has_provider(ShBinaryInfo)
    info = subject.provider(RunEnvironmentInfo)
    info.environment().contains_exactly({"FOO": "bar"})
    info.inherited_environment().contains_exactly(["INHERITED"])

def _test_no_coverage_output_generator(name):
    util.helper_target(
        sh_test,
        name = name + "_subject",
        srcs = ["pass.sh"],
    )
    analysis_test(
        name = name,
        impl = _test_no_coverage_output_generator_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:collect_code_coverage": False,
        },
    )

def _test_no_coverage_output_generator_impl(env, target):
    # The coverage output generator is only a dependency in coverage mode.
    env.expect.that_target(target).attr(
        "_lcov_merger",
        factory = lambda value, meta: subjects.bool(value == None, meta = meta),
    ).equals(True)

def _test_coverage_output_generator(name):
    util.helper_target(
        sh_test,
        name = name + "_subject",
        srcs = ["pass.sh"],
    )
    analysis_test(
        name = name,
        impl = _test_coverage_output_generator_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:collect_code_coverage": True,
            "//command_line_option:coverage_output_generator": str(Label(":fake_lcov_merger")),
        },
    )

def _test_coverage_output_generator_impl(env, target):
    env.expect.that_target(target).attr(
        "_lcov_merger",
        factory = lambda value, meta: subjects.label(value.label, meta = meta),
    ).equals(Label(":fake_lcov_merger"))

def _instrumented_files_test(name, *, instrument_test_targets):
    util.helper_target(
        sh_test,
        name = name + "_subject",
        srcs = ["pass.sh"],
        deps = [":lib"],
    )
    analysis_test(
        name = name,
        impl = lambda env, target: _instrumented_files_test_impl(env, target, instrument_test_targets = instrument_test_targets),
        target = name + "_subject",
        config_settings = {
            "//command_line_option:collect_code_coverage": True,
            "//command_line_option:instrument_test_targets": instrument_test_targets,
            "//command_line_option:instrumentation_filter": "^//tests/sh_test[/:]",
        },
    )

def _instrumented_files_test_impl(env, target, *, instrument_test_targets):
    # The test script itself is only instrumented with --instrument_test_targets,
    # its dependencies always are.
    info = env.expect.that_target(target).provider(InstrumentedFilesInfo)
    info.instrumented_files().contains_exactly(
        (["{package}/pass.sh"] if instrument_test_targets else []) + ["{package}/lib.sh"],
    )

def _test_instrumented_files(name):
    _instrumented_files_test(name, instrument_test_targets = True)

def _test_instrumented_files_without_test_targets(name):
    _instrumented_files_test(name, instrument_test_targets = False)

def sh_test_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_providers,
            _test_no_coverage_output_generator,
            _test_coverage_output_generator,
            _test_instrumented_files,
            _test_instrumented_files_without_test_targets,
        ],
    )
