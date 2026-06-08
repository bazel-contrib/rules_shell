"""Rules under test that exercise `ctx.actions.run_shell`."""

def _command_string_impl(ctx):
    out_a = ctx.actions.declare_file(ctx.label.name + "_a.txt")
    out_b = ctx.actions.declare_file(ctx.label.name + "_b.img")
    ctx.actions.run_shell(
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
    ctx.actions.run_shell(
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
    ctx.actions.run_shell(
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
    ctx.actions.run_shell(
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
    ctx.actions.run_shell(
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
    ctx.actions.run_shell(
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
    ctx.actions.run_shell(
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
