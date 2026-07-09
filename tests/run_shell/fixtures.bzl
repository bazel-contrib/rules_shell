"""Rules under test that exercise the `run_shell` function."""

load("//shell:run_shell.bzl", "run_shell")
load("//shell/toolchains:sh_exec_toolchain.bzl", "SH_EXEC_TOOLCHAIN_TYPE")

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
    toolchains = [SH_EXEC_TOOLCHAIN_TYPE],
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
    toolchains = [SH_EXEC_TOOLCHAIN_TYPE],
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
    toolchains = [SH_EXEC_TOOLCHAIN_TYPE],
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
    toolchains = [SH_EXEC_TOOLCHAIN_TYPE],
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
    toolchains = [SH_EXEC_TOOLCHAIN_TYPE],
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
    toolchains = [SH_EXEC_TOOLCHAIN_TYPE],
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
    toolchains = [SH_EXEC_TOOLCHAIN_TYPE],
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
    toolchains = [SH_EXEC_TOOLCHAIN_TYPE],
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
    toolchains = [SH_EXEC_TOOLCHAIN_TYPE],
)
