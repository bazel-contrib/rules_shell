"""Rules under test that exercise the `run_shell` function."""

load("//shell:run_shell.bzl", "run_shell")

def _command_string_impl(ctx):
    out_a = ctx.actions.declare_file(ctx.label.name + "_a.txt")
    out_b = ctx.actions.declare_file(ctx.label.name + "_b.img")
    run_shell(
        ctx,
        inputs = ctx.files.srcs,
        outputs = [out_a, out_b],
        arguments = ["--a", "--b"],
        mnemonic = "DummyMnemonic",
        command = "dummy_command",
        progress_message = "dummy_message",
        env = {"a": "b"},
    )
    return [DefaultInfo(files = depset([out_a, out_b]))]

command_string = rule(
    implementation = _command_string_impl,
    attrs = {"srcs": attr.label_list(allow_files = True)},
)

def _command_no_arguments_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        outputs = [out],
        command = "echo foo123 > " + out.path,
    )
    return [DefaultInfo(files = depset([out]))]

command_no_arguments = rule(
    implementation = _command_no_arguments_impl,
    attrs = {},
)

def _command_with_tools_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        inputs = ctx.files.tool if ctx.attr.tool_in_inputs else [],
        tools = ctx.files.tool,
        outputs = [out],
        command = "boo bar baz",
    )
    return [DefaultInfo(files = depset([out]))]

command_with_tools = rule(
    implementation = _command_with_tools_impl,
    attrs = {
        "tool": attr.label(allow_files = True, cfg = "exec"),
        "tool_in_inputs": attr.bool(default = False),
    },
)

def _command_list_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        outputs = [out],
        mnemonic = "DummyMnemonic",
        command = ["dummy_command", "--arg1", "--arg2"],
    )
    return [DefaultInfo(files = depset([out]))]

command_list = rule(
    implementation = _command_list_impl,
    attrs = {},
)

def _invalid_mnemonic_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        outputs = [out],
        command = "false",
        mnemonic = "@@@",
    )
    return [DefaultInfo(files = depset([out]))]

invalid_mnemonic = rule(
    implementation = _invalid_mnemonic_impl,
    attrs = {},
)

def _lazy_args_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    args = ctx.actions.args()
    args.add("--foo")
    run_shell(
        ctx,
        outputs = [out],
        arguments = [args],
        mnemonic = "DummyMnemonic",
        command = "dummy_command",
    )
    return [DefaultInfo(files = depset([out]))]

lazy_args = rule(
    implementation = _lazy_args_impl,
    attrs = {},
)

def _long_command_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    long_command = "( %s ; ) > $1" % " ; ".join(
        ["echo xxx%d" % i for i in range(0, 7000)],
    )
    run_shell(
        ctx,
        outputs = [out],
        command = long_command,
        mnemonic = "LongMnemonic",
        arguments = [out.path],
    )
    return [DefaultInfo(files = depset([out]))]

long_command = rule(
    implementation = _long_command_impl,
    attrs = {},
)

def _medium_command_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")

    # A command between the Windows (8000) and non-Windows (64000) command
    # length limits. It is spilled into a helper script only on Windows.
    medium_command = "( %s ; ) > $1" % " ; ".join(
        ["echo zzz%d" % i for i in range(0, 1000)],
    )
    run_shell(
        ctx,
        outputs = [out],
        command = medium_command,
        mnemonic = "MediumMnemonic",
        arguments = [out.path],
    )
    return [DefaultInfo(files = depset([out]))]

medium_command = rule(
    implementation = _medium_command_impl,
    attrs = {},
)

def _two_long_commands_impl(ctx):
    out1 = ctx.actions.declare_file(ctx.label.name + "1.out")
    out2 = ctx.actions.declare_file(ctx.label.name + "2.out")
    command1 = "( %s ; ) > $1" % " ; ".join(
        ["echo xxx%d" % i for i in range(0, 7000)],
    )
    command2 = "( %s ; ) > $1" % " ; ".join(
        ["echo yyy%d" % i for i in range(0, 7000)],
    )
    run_shell(
        ctx,
        outputs = [out1],
        command = command1,
        mnemonic = "Mnemonic1",
        arguments = [out1.path],
    )
    run_shell(
        ctx,
        outputs = [out2],
        command = command2,
        mnemonic = "Mnemonic2",
        arguments = [out2.path],
    )
    return [DefaultInfo(files = depset([out1, out2]))]

two_long_commands = rule(
    implementation = _two_long_commands_impl,
    attrs = {},
)

def _command_in_exec_group_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")

    # Like medium_command: long enough to be spilled on Windows, but not on
    # other platforms.
    command = "( %s ; ) > $1" % " ; ".join(
        ["echo zzz%d" % i for i in range(0, 1000)],
    )
    run_shell(
        ctx,
        outputs = [out],
        command = command,
        mnemonic = "ExecGroupMnemonic",
        arguments = [out.path],
        exec_group = ctx.attr.use_exec_group or None,
    )
    return [DefaultInfo(files = depset([out]))]

command_in_exec_group = rule(
    implementation = _command_in_exec_group_impl,
    attrs = {"use_exec_group": attr.string()},
    exec_groups = {
        "windows": exec_group(
            exec_compatible_with = ["@platforms//os:windows"],
        ),
    },
)

def _env_and_execution_requirements_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        outputs = [out],
        env = {"a": "b"},
        execution_requirements = {"timeout": "10", "block-network": "foo"},
        mnemonic = "DummyMnemonic",
        command = "dummy_command",
        progress_message = "dummy_message",
    )
    return [DefaultInfo(files = depset([out]))]

env_and_execution_requirements = rule(
    implementation = _env_and_execution_requirements_impl,
)

def _lazy_args_with_param_file_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    args = ctx.actions.args()
    args.add("--foo")
    args.use_param_file("--file=%s", use_always = True)
    run_shell(
        ctx,
        outputs = [out],
        arguments = [args],
        mnemonic = "DummyMnemonic",
        command = "touch " + out.path,
    )
    return [DefaultInfo(files = depset([out]))]

lazy_args_with_param_file = rule(
    implementation = _lazy_args_with_param_file_impl,
)

def _tuple_arguments_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    args = ctx.actions.args()
    args.add("--bar")
    run_shell(
        ctx,
        outputs = [out],
        arguments = ("--foo", args, "--baz"),
        mnemonic = "DummyMnemonic",
        command = "dummy_command",
    )
    return [DefaultInfo(files = depset([out]))]

tuple_arguments = rule(
    implementation = _tuple_arguments_impl,
)

def _string_arguments_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        outputs = [out],
        arguments = out.path,
        mnemonic = "DummyMnemonic",
        command = "touch $1",
    )
    return [DefaultInfo(files = depset([out]))]

string_arguments = rule(
    implementation = _string_arguments_impl,
)

def _no_outputs_impl(ctx):
    run_shell(
        ctx,
        outputs = [],
        mnemonic = "DummyMnemonic",
        command = "dummy_command",
    )
    return []

no_outputs = rule(
    implementation = _no_outputs_impl,
)

def _string_outputs_impl(ctx):
    run_shell(
        ctx,
        outputs = ["a", "b"],
        mnemonic = "DummyMnemonic",
        command = "dummy_command",
    )
    return []

string_outputs = rule(
    implementation = _string_outputs_impl,
)

def _resource_set(_os, _inputs_size):
    return {"cpu": 2, "memory": 64}

def _command_with_resource_set_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        outputs = [out],
        command = "echo foo > " + out.path,
        mnemonic = "ResourceSetMnemonic",
        # A value of the wrong type verifies that resource_set is forwarded.
        resource_set = _resource_set if ctx.attr.valid else "not_a_function",
    )
    return [DefaultInfo(files = depset([out]))]

command_with_resource_set = rule(
    implementation = _command_with_resource_set_impl,
    attrs = {"valid": attr.bool(default = True)},
)
