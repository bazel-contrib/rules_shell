"""A rule that writes a greeting with `run_shell`."""

load("@rules_shell//shell:run_shell.bzl", "run_shell")

def _greeting_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    command = "echo \"$1\" > \"$OUT\""
    if ctx.attr.spill:
        # Exceeds the maximum command length on all platforms, which makes
        # run_shell spill the command into a helper script.
        command += " #" + "x" * 70000
    run_shell(
        ctx,
        outputs = [out],
        command = command,
        arguments = ["hello from run_shell"],
        env = {"OUT": out.path},
        mnemonic = "Greeting",
    )
    return [DefaultInfo(files = depset([out]))]

greeting = rule(
    implementation = _greeting_impl,
    attrs = {
        "spill": attr.bool(),
    },
)
