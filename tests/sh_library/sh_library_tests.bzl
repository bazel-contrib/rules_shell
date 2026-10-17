"""Analysis tests for sh_library."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//shell:sh_info.bzl", "ShInfo")
load("//shell:sh_library.bzl", "sh_library")

def _test_files_and_runfiles(name):
    util.helper_target(
        sh_library,
        name = name + "_subject",
        srcs = ["lib.sh"],
        data = ["data.txt"],
        deps = [":dep"],
    )
    analysis_test(
        name = name,
        impl = _test_files_and_runfiles_impl,
        target = name + "_subject",
    )

def _test_files_and_runfiles_impl(env, target):
    subject = env.expect.that_target(target)

    # srcs, deps and data are treated the same way, also transitively.
    subject.default_outputs().contains_exactly([
        "{package}/data.txt",
        "{package}/dep.sh",
        "{package}/lib.sh",
        "{package}/nested_data.txt",
        "{package}/nested_dep.sh",
    ])
    subject.runfiles().contains_exactly([
        "{workspace}/{package}/data.txt",
        "{workspace}/{package}/dep.sh",
        "{workspace}/{package}/lib.sh",
        "{workspace}/{package}/nested_data.txt",
        "{workspace}/{package}/nested_dep.sh",
    ])
    subject.has_provider(ShInfo)

def _test_deps_require_sh_info(name):
    util.helper_target(
        sh_library,
        name = name + "_subject",
        srcs = ["lib.sh"],
        deps = [":not_a_library"],
    )
    analysis_test(
        name = name,
        impl = _test_deps_require_sh_info_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_deps_require_sh_info_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*not_a_library*does not have mandatory providers*ShInfo*"),
    )

def _test_instrumented_files(name):
    util.helper_target(
        sh_library,
        name = name + "_subject",
        srcs = ["lib.sh"],
        data = [
            "data.txt",
            ":data_lib",
        ],
        deps = [":dep"],
    )
    analysis_test(
        name = name,
        impl = _test_instrumented_files_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:collect_code_coverage": True,
            "//command_line_option:instrumentation_filter": "^//tests/sh_library[/:]",
        },
    )

def _test_instrumented_files_impl(env, target):
    info = env.expect.that_target(target).provider(InstrumentedFilesInfo)
    info.instrumented_files().contains_exactly([
        "{package}/data_lib.sh",
        "{package}/dep.sh",
        "{package}/lib.sh",
        "{package}/nested_dep.sh",
    ])

def _test_not_instrumented_without_coverage(name):
    util.helper_target(
        sh_library,
        name = name + "_subject",
        srcs = ["lib.sh"],
    )
    analysis_test(
        name = name,
        impl = _test_not_instrumented_without_coverage_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:collect_code_coverage": False,
        },
    )

def _test_not_instrumented_without_coverage_impl(env, target):
    info = env.expect.that_target(target).provider(InstrumentedFilesInfo)
    info.instrumented_files().contains_exactly([])

def sh_library_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_files_and_runfiles,
            _test_deps_require_sh_info,
            _test_instrumented_files,
            _test_not_instrumented_without_coverage,
        ],
    )
