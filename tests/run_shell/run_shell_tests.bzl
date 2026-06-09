"""Analysis tests for `ctx.actions.run_shell`."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load(
    ":fixtures.bzl",
    "command_list",
    "command_no_arguments",
    "command_string",
    "command_with_tools",
    "invalid_mnemonic",
    "lazy_args",
    "long_command",
    "medium_command",
    "two_long_commands",
)

def _test_command_string(name):
    util.helper_target(
        command_string,
        name = name + "_subject",
        srcs = ["a.txt", "b.img"],
    )
    analysis_test(
        name = name,
        impl = _test_command_string_impl,
        target = name + "_subject",
    )

def _test_command_string_impl(env, target):
    action = env.expect.that_target(target).action_named("DummyMnemonic")

    action.argv().contains_at_least([
        "-c",
        "dummy_command",
        "",
        "--a",
        "--b",
    ]).in_order()

    action.inputs().contains_at_least_predicates([
        matching.file_basename_equals("a.txt"),
        matching.file_basename_equals("b.img"),
    ])

    action.env().contains_exactly({"a": "b"})

def _test_command_no_arguments(name):
    util.helper_target(
        command_no_arguments,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_command_no_arguments_impl,
        target = name + "_subject",
    )

def _test_command_no_arguments_impl(env, target):
    action = env.expect.that_target(target).action_generating(
        "{package}/{name}.out",
    )

    action.argv().has_size(3)
    action.argv().contains_at_least(["-c"]).in_order()
    action.argv().not_contains("")

def _test_command_with_tools(name):
    util.helper_target(
        command_with_tools,
        name = name + "_subject",
        tool = "t.exe",
    )
    analysis_test(
        name = name,
        impl = _test_command_with_tools_impl,
        target = name + "_subject",
    )

def _test_command_with_tools_impl(env, target):
    action = env.expect.that_target(target).action_generating("{package}/{name}.out")

    action.inputs().contains_predicate(matching.file_basename_equals("t.exe"))

def _test_command_with_tools_also_in_inputs(name):
    util.helper_target(
        command_with_tools,
        name = name + "_subject",
        tool = "t.exe",
        tool_in_inputs = True,
    )
    analysis_test(
        name = name,
        impl = _test_command_with_tools_also_in_inputs_impl,
        target = name + "_subject",
    )

def _test_command_with_tools_also_in_inputs_impl(env, target):
    action = env.expect.that_target(target).action_generating("{package}/{name}.out")

    action.inputs().contains_predicate(matching.file_basename_equals("t.exe"))

def _test_command_list_rejected_by_default(name):
    util.helper_target(
        command_list,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_command_list_rejected_by_default_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_command_list_rejected_by_default_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*'command' must be of type string*"),
    )

def _test_invalid_mnemonic_rejected(name):
    util.helper_target(
        invalid_mnemonic,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_invalid_mnemonic_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_invalid_mnemonic_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*mnemonic must only contain letters and/or digits*"),
    )

def _test_lazy_args(name):
    util.helper_target(
        lazy_args,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_lazy_args_impl,
        target = name + "_subject",
    )

def _test_lazy_args_impl(env, target):
    action = env.expect.that_target(target).action_named("DummyMnemonic")

    action.argv().contains_at_least(["", "--foo"]).in_order()

def _test_long_command_uses_helper_script(name):
    util.helper_target(
        long_command,
        name = name + "_subject",
        # Force a Unix execution platform so that the longer Unix command length limit applies.
        exec_compatible_with = ["@platforms//os:linux"],
    )
    analysis_test(
        name = name,
        impl = _test_long_command_uses_helper_script_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:extra_execution_platforms": [
                "//tests/run_shell:linux_exec",
            ],
        },
    )

def _test_long_command_uses_helper_script_impl(env, target):
    helper = env.expect.that_target(target).action_generating(
        "{package}/{name}.run_shell_0.sh",
    )
    helper.content().contains("echo xxx6999 ;")

    spawn = env.expect.that_target(target).action_named("LongMnemonic")
    spawn.inputs().contains_predicate(
        matching.file_basename_contains(".run_shell_0.sh"),
    )

def _test_windows_threshold(name):
    util.helper_target(
        medium_command,
        name = name + "_subject",
        # Force a Windows execution platform so that the shorter Windows command length limit applies.
        exec_compatible_with = ["@platforms//os:windows"],
    )
    analysis_test(
        name = name,
        impl = _test_windows_threshold_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:extra_execution_platforms": [
                "//tests/run_shell:windows_exec",
            ],
        },
    )

def _test_windows_threshold_impl(env, target):
    helper = env.expect.that_target(target).action_generating(
        "{package}/{name}.run_shell_0.sh",
    )
    helper.content().contains("echo zzz999 ;")

def _test_medium_command_does_not_use_helper_script(name):
    util.helper_target(
        medium_command,
        name = name + "_subject",
        # Force a Linux execution platform so that the larger non-Windows command length limit applies.
        exec_compatible_with = ["@platforms//os:linux"],
    )
    analysis_test(
        name = name,
        impl = _test_medium_command_does_not_use_helper_script_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:extra_execution_platforms": [
                "//tests/run_shell:linux_exec",
            ],
        },
    )

def _test_medium_command_does_not_use_helper_script_impl(env, target):
    # On Linux the command length limit is 64000, so a ~14000 char command is
    # passed inline instead of being spilled into a helper script.
    action = env.expect.that_target(target).action_named("MediumMnemonic")
    action.argv().contains_predicate(matching.str_matches("*echo zzz999*"))
    action.inputs().not_contains_predicate(
        matching.file_basename_contains(".run_shell_0.sh"),
    )

def _test_two_run_shell_calls(name):
    util.helper_target(
        two_long_commands,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_two_run_shell_calls_impl,
        target = name + "_subject",
    )

def _test_two_run_shell_calls_impl(env, target):
    # Each run_shell call in a rule gets its own helper script, numbered by an
    # incrementing per-rule counter (run_shell_0.sh, run_shell_1.sh, ...).
    helper0 = env.expect.that_target(target).action_generating(
        "{package}/{name}.run_shell_0.sh",
    )
    helper0.content().contains("echo xxx6999 ;")

    helper1 = env.expect.that_target(target).action_generating(
        "{package}/{name}.run_shell_1.sh",
    )
    helper1.content().contains("echo yyy6999 ;")

def run_shell_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_command_string,
            _test_command_no_arguments,
            _test_command_with_tools,
            _test_command_with_tools_also_in_inputs,
            _test_command_list_rejected_by_default,
            _test_invalid_mnemonic_rejected,
            _test_lazy_args,
            _test_long_command_uses_helper_script,
            _test_windows_threshold,
            _test_medium_command_does_not_use_helper_script,
            _test_two_run_shell_calls,
        ],
    )
