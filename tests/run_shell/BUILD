load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load(
    ":exec_fixtures.bzl",
    "run_shell_helper_script_args",
    "run_shell_long_output",
    "run_shell_output",
    "run_shell_output_with_action_env",
    "run_shell_script_args",
)
load(":run_shell_tests.bzl", "run_shell_test_suite")

run_shell_test_suite(name = "run_shell_tests")

platform(
    name = "linux_exec",
    constraint_values = ["@platforms//os:linux"],
)

platform(
    name = "windows_exec",
    constraint_values = ["@platforms//os:windows"],
)

run_shell_output(
    name = "basic_output",
    command = "echo 'hello world' > $1",
)

diff_test(
    name = "basic_output_test",
    size = "small",
    file1 = ":basic_output",
    file2 = "basic_output.golden",
)

run_shell_output(
    name = "positional_arguments",
    command = "echo \"$2 $3\" > $1",
    extra_arguments = [
        "foo",
        "bar",
    ],
)

diff_test(
    name = "positional_arguments_test",
    size = "small",
    file1 = ":positional_arguments",
    file2 = "positional_arguments.golden",
)

run_shell_output(
    name = "env",
    command = "echo \"$FOO\" > $1",
    env = {"FOO": "bar"},
)

diff_test(
    name = "env_test",
    size = "small",
    file1 = ":env",
    file2 = "env.golden",
)

# positional parameters of the command string, not of the script it runs.
# Codifies https://github.com/bazelbuild/bazel/issues/6391 (working as intended).
run_shell_script_args(
    name = "script_args_not_forwarded",
    forward_arguments = False,
)

diff_test(
    name = "script_args_not_forwarded_test",
    size = "small",
    file1 = ":script_args_not_forwarded",
    file2 = "script_args_not_forwarded.golden",
)

# Explicitly forwarding with "$@" passes `arguments` through to the script.
run_shell_script_args(
    name = "script_args_forwarded",
    forward_arguments = True,
)

diff_test(
    name = "script_args_forwarded_test",
    size = "small",
    file1 = ":script_args_forwarded",
    file2 = "script_args_forwarded.golden",
)

# A command referencing $1 receives `arguments` when it runs inline...
run_shell_helper_script_args(
    name = "helper_script_args_inline",
    long = False,
)

diff_test(
    name = "helper_script_args_inline_test",
    size = "small",
    file1 = ":helper_script_args_inline",
    file2 = "helper_script_args_inline.golden",
)

# ...but the same command spilled into a helper script does not: $1 is empty.
# Codifies https://github.com/bazelbuild/bazel/issues/29365 (currently open bug).
run_shell_helper_script_args(
    name = "helper_script_args_spilled",
    long = True,
)

diff_test(
    name = "helper_script_args_spilled_test",
    size = "small",
    file1 = ":helper_script_args_spilled",
    file2 = "helper_script_args_spilled.golden",
)

run_shell_long_output(
    name = "long_command",
)

diff_test(
    name = "long_command_test",
    size = "small",
    file1 = ":long_command",
    file2 = "long_command.golden",
)

run_shell_output_with_action_env(
    name = "use_default_shell_env",
    command = "echo \"$FROM_ACTION_ENV\" > $1",
    use_default_shell_env = True,
)

diff_test(
    name = "use_default_shell_env_test",
    size = "small",
    file1 = ":use_default_shell_env",
    file2 = "use_default_shell_env.golden",
)

run_shell_output_with_action_env(
    name = "fixed_env_overrides_action_env",
    command = "echo \"$FROM_ACTION_ENV\" > $1",
    env = {"FROM_ACTION_ENV": "fixed_env_value"},
    use_default_shell_env = True,
)

diff_test(
    name = "fixed_env_overrides_action_env_test",
    size = "small",
    file1 = ":fixed_env_overrides_action_env",
    file2 = "fixed_env_overrides_action_env.golden",
)
