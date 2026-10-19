load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("//shell:sh_binary.bzl", "sh_binary")
load("//shell/toolchains:sh_exec_toolchain.bzl", "sh_exec_toolchain")
load(
    ":exec_fixtures.bzl",
    "files_to_run_sh_exec_toolchain",
    "run_shell_arguments_as_command",
    "run_shell_aspect_output",
    "run_shell_helper_script_args",
    "run_shell_long_output",
    "run_shell_output",
    "run_shell_output_with_action_env",
    "run_shell_output_with_files_to_run_interpreter",
    "run_shell_param_file_args",
    "run_shell_script_args",
    "run_shell_three_commands",
    "run_shell_tool_output",
    "run_shell_tree_artifact_args",
    "run_shell_with_env_and_input",
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

platform(
    name = "freebsd_exec",
    constraint_values = ["@platforms//os:freebsd"],
)

platform(
    name = "openbsd_exec",
    constraint_values = ["@platforms//os:openbsd"],
)

# No shell exec toolchain is registered for this platform.
platform(
    name = "no_os_exec",
    constraint_values = ["@platforms//os:none"],
)

# Shell exec toolchains with recognizable paths and limits, used by the
# analysis tests via --extra_toolchains.
sh_exec_toolchain(
    name = "custom_linux_sh_exec",
    max_command_length = 64000,
    path = "/custom/linux/bash",
)

toolchain(
    name = "custom_linux_sh_exec_toolchain",
    exec_compatible_with = ["@platforms//os:linux"],
    toolchain = ":custom_linux_sh_exec",
    toolchain_type = "//shell:exec_toolchain_type",
)

sh_exec_toolchain(
    name = "custom_windows_sh_exec",
    max_command_length = 8000,
    path = "C:/custom/windows/bash.exe",
)

toolchain(
    name = "custom_windows_sh_exec_toolchain",
    exec_compatible_with = ["@platforms//os:windows"],
    toolchain = ":custom_windows_sh_exec",
    toolchain_type = "//shell:exec_toolchain_type",
)

# A toolchain type that only has a toolchain for Windows execution platforms.
toolchain_type(name = "windows_only_toolchain_type")

toolchain(
    name = "windows_only_toolchain",
    exec_compatible_with = ["@platforms//os:windows"],
    toolchain = ":custom_windows_sh_exec",
    toolchain_type = ":windows_only_toolchain_type",
)

sh_exec_toolchain(
    name = "short_sh_exec",
    max_command_length = 10,
    path = "/bin/bash",
)

toolchain(
    name = "short_sh_exec_toolchain",
    toolchain = ":short_sh_exec",
    toolchain_type = "//shell:exec_toolchain_type",
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

# ...and the same command spilled into a helper script behaves identically:
# run_shell forwards `arguments` into the helper script, fixing
# https://github.com/bazelbuild/bazel/issues/29365.
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
    name = "no_default_shell_env",
    command = "echo \"[$FROM_ACTION_ENV]\" > $1",
    use_default_shell_env = False,
)

diff_test(
    name = "no_default_shell_env_test",
    size = "small",
    file1 = ":no_default_shell_env",
    file2 = "no_default_shell_env.golden",
)

# Variables in `env` override the default shell environment, other variables
# from the default shell environment are kept.
run_shell_output_with_action_env(
    name = "fixed_env_overrides_action_env",
    command = "echo \"$FROM_ACTION_ENV $OTHER_ACTION_ENV\" > $1",
    env = {"FROM_ACTION_ENV": "fixed_env_value"},
    use_default_shell_env = True,
)

diff_test(
    name = "fixed_env_overrides_action_env_test",
    size = "small",
    file1 = ":fixed_env_overrides_action_env",
    file2 = "fixed_env_overrides_action_env.golden",
)

# An Args object with its own param file is passed to the command, also when
# the command itself is spilled into a helper script.
[
    run_shell_param_file_args(
        name = "param_file_args_" + variant,
        long = variant == "spilled",
    )
    for variant in [
        "inline",
        "spilled",
    ]
]

[
    diff_test(
        name = "param_file_args_%s_test" % variant,
        size = "small",
        file1 = ":param_file_args_" + variant,
        file2 = golden,
    )
    for variant, golden in [
        ("inline", "param_file_args.golden"),
        ("spilled", "param_file_args_spilled.golden"),
    ]
]

# Commands that run their arguments as a command, with and without trailing
# whitespace (https://github.com/bazelbuild/bazel/issues/7122) and when spilled
# into a helper script.
[
    run_shell_arguments_as_command(
        name = "arguments_as_command_" + name,
        command = command,
        long = long,
    )
    for name, command, long in [
        ("inline", "${1+\"$@\"}", False),
        ("inline_trailing_space", "${1+\"$@\"} ", False),
        ("spilled", "${1+\"$@\"}", True),
    ]
]

[
    diff_test(
        name = "arguments_as_command_%s_test" % name,
        size = "small",
        file1 = ":arguments_as_command_" + name,
        file2 = golden,
    )
    for name, golden in [
        ("inline", "arguments_as_command.golden"),
        ("inline_trailing_space", "arguments_as_command.golden"),
        ("spilled", "arguments_as_command_spilled.golden"),
    ]
]

# Non-ASCII characters in commands and arguments are preserved, also when the
# command is spilled into a helper script.
[
    run_shell_output(
        name = "unicode_" + variant,
        command = "echo \"äöüÄÖÜß🌱 $2\" > \"$OUT\"",
        extra_arguments = ["äöüÄÖÜß🌱"],
        long = variant == "spilled",
    )
    for variant in [
        "inline",
        "spilled",
    ]
]

[
    diff_test(
        name = "unicode_%s_test" % variant,
        size = "small",
        file1 = ":unicode_" + variant,
        file2 = golden,
    )
    for variant, golden in [
        ("inline", "unicode.golden"),
        ("spilled", "unicode_spilled.golden"),
    ]
]

# Executable tools passed in any form have their runfiles available.
sh_binary(
    name = "tool",
    srcs = ["tool.sh"],
    data = ["tool_data.txt"],
    deps = ["//shell/runfiles"],
)

[
    run_shell_tool_output(
        name = "tool_output_" + name,
        tool = ":tool",
        tool_in_inputs = tool_in_inputs,
        tools_type = tools_type,
    )
    for name, tools_type, tool_in_inputs in [
        ("depset", "depset", False),
        ("file", "file", False),
        ("file_in_inputs", "file", True),
        ("files_to_run", "files_to_run", False),
    ]
]

[
    diff_test(
        name = "tool_output_%s_test" % name,
        size = "small",
        file1 = ":tool_output_" + name,
        file2 = "tool_data.txt",
    )
    for name in [
        "depset",
        "file",
        "file_in_inputs",
        "files_to_run",
    ]
]

run_shell_three_commands(
    name = "three_commands",
)

diff_test(
    name = "three_commands_test",
    size = "small",
    file1 = ":three_commands",
    file2 = "three_commands.golden",
)

# run_shell can be used in aspects, including with a shadowed action.
exports_files(["aspect_input.txt"])

run_shell_with_env_and_input(
    name = "with_env_and_input",
    src = "a.txt",
)

[
    run_shell_aspect_output(
        name = "aspect_output_" + output,
        dep = ":with_env_and_input",
        output = output,
    )
    for output in [
        "plain",
        "shadowed",
    ]
]

[
    diff_test(
        name = "aspect_output_%s_test" % output,
        size = "small",
        file1 = ":aspect_output_" + output,
        file2 = "aspect_output_%s.golden" % output,
    )
    for output in [
        "plain",
        "shadowed",
    ]
]

run_shell_tree_artifact_args(
    name = "tree_artifact_args",
)

diff_test(
    name = "tree_artifact_args_test",
    size = "small",
    file1 = ":tree_artifact_args",
    file2 = "tree_artifact_args.golden",
)

# A shell exec toolchain can provide an interpreter built by Bazel.
sh_binary(
    name = "interpreter",
    srcs = ["interpreter.sh"],
    data = ["interpreter_data.txt"],
    deps = ["//shell/runfiles"],
)

files_to_run_sh_exec_toolchain(
    name = "files_to_run_sh_exec",
    interpreter = ":interpreter",
    max_command_length = 64000,
)

toolchain(
    name = "files_to_run_sh_exec_toolchain",
    toolchain = ":files_to_run_sh_exec",
    toolchain_type = "//shell:exec_toolchain_type",
)

[
    run_shell_output_with_files_to_run_interpreter(
        name = "files_to_run_interpreter_" + variant,
        command = "echo \"$INTERPRETER $2\" > $1",
        extra_arguments = ["the_argument"],
        long = variant == "spilled",
        # UNDESIRED: Before Bazel 10, the sh_binary launcher on Windows splices
        # arguments into a command string for bash, which expands the variables
        # in the inline command
        # (https://github.com/bazelbuild/bazel/commit/aa3eebd).
        target_compatible_with = select({
            "@platforms//os:windows": ["@platforms//:incompatible"],
            "//conditions:default": [],
        }) if variant == "inline" else [],
    )
    for variant in [
        "inline",
        "spilled",
    ]
]

[
    diff_test(
        name = "files_to_run_interpreter_%s_test" % variant,
        size = "small",
        file1 = ":files_to_run_interpreter_" + variant,
        file2 = "files_to_run_interpreter.golden",
    )
    for variant in [
        "inline",
        "spilled",
    ]
]
