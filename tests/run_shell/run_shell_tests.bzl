"""Analysis tests for the `run_shell` function."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load(
    ":fixtures.bzl",
    "command_in_exec_group",
    "command_list",
    "command_no_arguments",
    "command_of_given_length",
    "command_string",
    "command_with_optional_toolchain",
    "command_with_other_toolchain",
    "command_with_resource_set",
    "command_with_tools",
    "command_without_toolchain",
    "env_and_execution_requirements",
    "invalid_mnemonic",
    "lazy_args",
    "lazy_args_with_param_file",
    "long_command",
    "medium_command",
    "no_outputs",
    "string_arguments",
    "string_outputs",
    "tuple_arguments",
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

    env.expect.that_collection([f.basename for f in action.actual.outputs.to_list()]).contains_exactly([
        target.label.name + "_a.txt",
        target.label.name + "_b.img",
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
    env.expect.that_bool(action.actual.argv[2].startswith("echo foo123")).equals(True)

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

def _passes_command_inline(action, command_marker):
    argv = action.actual.argv or []
    return any([
        argv[i] == "-c" and command_marker in argv[i + 1]
        for i in range(len(argv) - 1)
    ])

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
    # A command above the length limit is spilled rather than passed inline.
    spawn = env.expect.that_target(target).action_named("LongMnemonic")
    env.expect.that_bool(_passes_command_inline(spawn, "echo xxx6999 ;")).equals(False)

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
    # On Windows the command length limit is 8000, so a ~14000 char command is
    # spilled even though it stays below the 64000 limit used on other
    # platforms: it is not passed to the interpreter inline.
    spawn = env.expect.that_target(target).action_named("MediumMnemonic")
    env.expect.that_bool(_passes_command_inline(spawn, "echo zzz999 ;")).equals(False)

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
    # passed to the interpreter inline via `-c` instead of being spilled.
    spawn = env.expect.that_target(target).action_named("MediumMnemonic")
    env.expect.that_bool(_passes_command_inline(spawn, "echo zzz999 ;")).equals(True)

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
    # Two run_shell calls in one rule spill independently; neither command is
    # passed to the interpreter inline.
    spawn1 = env.expect.that_target(target).action_named("Mnemonic1")
    env.expect.that_bool(_passes_command_inline(spawn1, "echo xxx6999 ;")).equals(False)

    spawn2 = env.expect.that_target(target).action_named("Mnemonic2")
    env.expect.that_bool(_passes_command_inline(spawn2, "echo yyy6999 ;")).equals(False)

# Execution platforms with different maximum command lengths and shell exec
# toolchains with recognizable paths.
_LINUX_AND_WINDOWS_EXEC = {
    "//command_line_option:extra_execution_platforms": [
        "//tests/run_shell:linux_exec",
        "//tests/run_shell:windows_exec",
    ],
    "//command_line_option:extra_toolchains": [
        "//tests/run_shell:custom_linux_sh_exec_toolchain",
        "//tests/run_shell:custom_windows_sh_exec_toolchain",
    ],
}

def _test_exec_group(name):
    util.helper_target(
        command_in_exec_group,
        name = name + "_subject",
        use_exec_group = "windows",
        # Force a Linux execution platform for the default exec group so that
        # only the "windows" exec group applies the shorter Windows command
        # length limit.
        exec_compatible_with = ["@platforms//os:linux"],
    )
    analysis_test(
        name = name,
        impl = _test_exec_group_impl,
        target = name + "_subject",
        config_settings = _LINUX_AND_WINDOWS_EXEC,
    )

def _test_exec_group_impl(env, target):
    # The given exec group resolves to a Windows execution platform.
    spawn = env.expect.that_target(target).action_named("ExecGroupMnemonic")
    env.expect.that_str(spawn.actual.argv[0]).equals("C:/custom/windows/bash.exe")
    env.expect.that_bool(_passes_command_inline(spawn, "echo zzz999 ;")).equals(False)

def _test_default_exec_group(name):
    util.helper_target(
        command_in_exec_group,
        name = name + "_subject",
        exec_compatible_with = ["@platforms//os:linux"],
    )
    analysis_test(
        name = name,
        impl = _test_default_exec_group_impl,
        target = name + "_subject",
        config_settings = _LINUX_AND_WINDOWS_EXEC,
    )

def _test_default_exec_group_impl(env, target):
    # Without an exec group, the default exec group is used.
    spawn = env.expect.that_target(target).action_named("ExecGroupMnemonic")
    env.expect.that_str(spawn.actual.argv[0]).equals("/custom/linux/bash")
    env.expect.that_bool(_passes_command_inline(spawn, "echo zzz999 ;")).equals(True)

def _test_env_and_execution_requirements(name):
    util.helper_target(
        env_and_execution_requirements,
        name = name + "_subject",
        tags = ["no-remote"],
    )
    analysis_test(
        name = name,
        impl = _test_env_and_execution_requirements_impl,
        target = name + "_subject",
    )

def _test_env_and_execution_requirements_impl(env, target):
    action = env.expect.that_target(target).action_named("DummyMnemonic")

    action.env().contains_exactly({"a": "b"})

    # "timeout" is not a recognized execution requirement and filtered out, the
    # "no-remote" tag of the target is propagated.
    env.expect.that_dict(action.actual.execution_info).contains_exactly({
        "block-network": "foo",
        "no-remote": "",
    })

def _test_lazy_args_with_param_file(name):
    util.helper_target(
        lazy_args_with_param_file,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_lazy_args_with_param_file_impl,
        target = name + "_subject",
    )

def _test_lazy_args_with_param_file_impl(env, target):
    action = env.expect.that_target(target).action_named("DummyMnemonic")

    # `argv` reflects the contents of the Args object's param file, which
    # follow the padding for $0. tests/run_shell:param_file_args_* verify that
    # the param file is used at execution time.
    action.argv().contains_at_least_predicates([
        matching.equals_wrapper("-c"),
        matching.str_startswith("touch "),
        matching.equals_wrapper(""),
        matching.equals_wrapper("--foo"),
    ]).in_order()

def _test_tuple_arguments(name):
    util.helper_target(
        tuple_arguments,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_tuple_arguments_impl,
        target = name + "_subject",
    )

def _test_tuple_arguments_impl(env, target):
    action = env.expect.that_target(target).action_named("DummyMnemonic")

    action.argv().contains_at_least(["-c", "dummy_command", "", "--foo", "--bar", "--baz"]).in_order()

def _test_string_arguments_rejected(name):
    util.helper_target(
        string_arguments,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_string_arguments_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_string_arguments_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*got value of type 'string'*"),
    )

def _test_no_outputs_rejected(name):
    util.helper_target(
        no_outputs,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_no_outputs_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_no_outputs_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*param 'outputs' may not be empty*"),
    )

def _test_string_outputs_rejected(name):
    util.helper_target(
        string_outputs,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_string_outputs_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_string_outputs_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*at index 0 of outputs, got element of type string, want File*"),
    )

def _test_unknown_exec_group_rejected(name):
    util.helper_target(
        command_in_exec_group,
        name = name + "_subject",
        use_exec_group = "honeydew",
    )
    analysis_test(
        name = name,
        impl = _test_unknown_exec_group_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
        config_settings = {
            "//command_line_option:extra_execution_platforms": [
                "//tests/run_shell:windows_exec",
            ],
        },
    )

def _test_unknown_exec_group_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*exec group 'honeydew'*"),
    )

def _test_auto_exec_groups(name):
    util.helper_target(
        command_no_arguments,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_auto_exec_groups_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:incompatible_auto_exec_groups": True,
        },
    )

def _test_auto_exec_groups_impl(env, target):
    action = env.expect.that_target(target).action_generating("{package}/{name}.out")

    action.argv().contains_at_least(["-c"]).in_order()

def _test_auto_exec_groups_with_exec_group(name):
    util.helper_target(
        command_in_exec_group,
        name = name + "_subject",
        use_exec_group = "windows",
        exec_compatible_with = ["@platforms//os:linux"],
    )
    analysis_test(
        name = name,
        impl = _test_exec_group_impl,
        target = name + "_subject",
        config_settings = _LINUX_AND_WINDOWS_EXEC | {
            "//command_line_option:incompatible_auto_exec_groups": True,
        },
    )

def _other_toolchain_test(name, *, auto_exec_groups):
    util.helper_target(
        command_with_other_toolchain,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = lambda env, target: _other_toolchain_test_impl(env, target, auto_exec_groups = auto_exec_groups),
        target = name + "_subject",
        config_settings = _LINUX_AND_WINDOWS_EXEC | {
            "//command_line_option:extra_toolchains": _LINUX_AND_WINDOWS_EXEC["//command_line_option:extra_toolchains"] + [
                "//tests/run_shell:windows_only_toolchain",
            ],
            "//command_line_option:incompatible_auto_exec_groups": auto_exec_groups,
        },
    )

def _other_toolchain_test_impl(env, target, *, auto_exec_groups):
    # Without automatic exec groups, the action runs on the only execution
    # platform that has all toolchains of the rule. With them, it runs on the
    # first execution platform with a shell exec toolchain.
    spawn = env.expect.that_target(target).action_named("OtherToolchainMnemonic")
    env.expect.that_str(spawn.actual.argv[0]).equals(
        "/custom/linux/bash" if auto_exec_groups else "C:/custom/windows/bash.exe",
    )

def _test_other_toolchain_with_auto_exec_groups(name):
    _other_toolchain_test(name, auto_exec_groups = True)

def _test_other_toolchain_without_auto_exec_groups(name):
    _other_toolchain_test(name, auto_exec_groups = False)

def _test_missing_toolchain_rejected(name):
    util.helper_target(
        command_without_toolchain,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_missing_toolchain_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_missing_toolchain_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*run_shell requires the shell exec toolchain type to be declared on the rule or aspect*"),
    )

def _test_missing_toolchain_in_exec_group_rejected(name):
    util.helper_target(
        command_without_toolchain,
        name = name + "_subject",
        use_exec_group = "no_toolchain",
    )
    analysis_test(
        name = name,
        impl = _test_missing_toolchain_in_exec_group_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_missing_toolchain_in_exec_group_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*run_shell requires the shell exec toolchain type to be declared in exec group 'no_toolchain'*"),
    )

def _test_optional_toolchain_not_found(name):
    util.helper_target(
        command_with_optional_toolchain,
        name = name + "_subject",
        exec_compatible_with = ["@platforms//os:none"],
    )
    analysis_test(
        name = name,
        impl = _test_optional_toolchain_not_found_impl,
        target = name + "_subject",
        expect_failure = True,
        config_settings = {
            "//command_line_option:extra_execution_platforms": [
                "//tests/run_shell:no_os_exec",
            ],
        },
    )

def _test_optional_toolchain_not_found_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*No shell exec toolchain found for the execution platform of this action*"),
    )

def _command_of_given_length_test(name, *, length, inline):
    util.helper_target(
        command_of_given_length,
        name = name + "_subject",
        length = length,
    )
    analysis_test(
        name = name,
        impl = lambda env, target: _command_of_given_length_test_impl(env, target, length = length, inline = inline),
        target = name + "_subject",
        config_settings = {
            "//command_line_option:extra_toolchains": [
                "//tests/run_shell:short_sh_exec_toolchain",
            ],
        },
    )

def _command_of_given_length_test_impl(env, target, *, length, inline):
    # Commands up to and including the max_command_length of the toolchain are
    # passed inline.
    spawn = env.expect.that_target(target).action_named("CommandOfGivenLength")
    env.expect.that_bool(_passes_command_inline(spawn, "#" * length)).equals(inline)

def _test_command_at_max_length(name):
    _command_of_given_length_test(name, length = 10, inline = True)

def _test_command_above_max_length(name):
    _command_of_given_length_test(name, length = 11, inline = False)

def _default_shell_test(name, *, os):
    util.helper_target(
        command_no_arguments,
        name = name + "_subject",
        exec_compatible_with = ["@platforms//os:" + os],
    )
    analysis_test(
        name = name,
        impl = _default_shell_test_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:extra_execution_platforms": [
                "//tests/run_shell:%s_exec" % os,
            ],
        },
    )

def _default_shell_test_impl(env, target):
    # Not the host OS of any CI platform, so the default shell path is used,
    # also on Windows hosts, where Bazel always sets BAZEL_SH.
    action = env.expect.that_target(target).action_generating("{package}/{name}.out")
    env.expect.that_str(action.actual.argv[0]).equals("/usr/local/bin/bash")

def _test_default_shell_freebsd(name):
    _default_shell_test(name, os = "freebsd")

def _test_default_shell_openbsd(name):
    _default_shell_test(name, os = "openbsd")

def _test_resource_set(name):
    util.helper_target(
        command_with_resource_set,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_resource_set_impl,
        target = name + "_subject",
    )

def _test_resource_set_impl(env, target):
    action = env.expect.that_target(target).action_named("ResourceSetMnemonic")
    action.argv().contains_at_least(["-c"])

def _test_invalid_resource_set_rejected(name):
    util.helper_target(
        command_with_resource_set,
        name = name + "_subject",
        valid = False,
    )
    analysis_test(
        name = name,
        impl = _test_invalid_resource_set_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_invalid_resource_set_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*parameter 'resource_set' got value of type 'string'*"),
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
            _test_windows_threshold,
            _test_medium_command_does_not_use_helper_script,
            _test_two_run_shell_calls,
            _test_exec_group,
            _test_default_exec_group,
            _test_env_and_execution_requirements,
            _test_lazy_args_with_param_file,
            _test_tuple_arguments,
            _test_string_arguments_rejected,
            _test_no_outputs_rejected,
            _test_string_outputs_rejected,
            _test_unknown_exec_group_rejected,
            _test_auto_exec_groups,
            _test_auto_exec_groups_with_exec_group,
            _test_other_toolchain_with_auto_exec_groups,
            _test_other_toolchain_without_auto_exec_groups,
            _test_missing_toolchain_rejected,
            _test_missing_toolchain_in_exec_group_rejected,
            _test_optional_toolchain_not_found,
            _test_command_at_max_length,
            _test_command_above_max_length,
            _test_default_shell_freebsd,
            _test_default_shell_openbsd,
            _test_resource_set,
            _test_invalid_resource_set_rejected,
        ],
    )
