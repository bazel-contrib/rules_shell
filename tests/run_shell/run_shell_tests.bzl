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
    )
    analysis_test(
        name = name,
        impl = _test_long_command_uses_helper_script_impl,
        target = name + "_subject",
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
        ],
    )
