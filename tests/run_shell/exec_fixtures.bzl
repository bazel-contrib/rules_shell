"""Rules that execute `ctx.actions.run_shell` and expose the produced output.

The single output file of each target is compared against a golden file with
`diff_test`, which exercises the runtime behavior of `run_shell` (command
execution, positional argument substitution, environment, helper scripts for
long commands) without a Bazel-in-Bazel integration test.
"""

load("@with_cfg.bzl", "with_cfg")

def _run_shell_output_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    ctx.actions.run_shell(
        outputs = [out],
        command = ctx.attr.command,
        arguments = [out.path] + ctx.attr.extra_arguments,
        env = ctx.attr.env,
        use_default_shell_env = ctx.attr.use_default_shell_env,
        mnemonic = "RunShellOutput",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_output = rule(
    implementation = _run_shell_output_impl,
    attrs = {
        # The shell command. `$1` is the output path; `$2`, `$3`, ... are
        # `extra_arguments`.
        "command": attr.string(mandatory = True),
        "extra_arguments": attr.string_list(),
        "env": attr.string_dict(),
        "use_default_shell_env": attr.bool(),
    },
)

# Same as run_shell_output, but transitions --action_env so that targets can
# observe an action env entry when use_default_shell_env = True.
run_shell_output_with_action_env, _run_shell_output_with_action_env = (
    with_cfg(run_shell_output)
        .extend("action_env", ["FROM_ACTION_ENV=action_env_value"])
        .build()
)

def _run_shell_long_output_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")

    # A command well above the 64,000 char (8,000 on Windows) threshold at which
    # run_shell spills the command into a helper script. All but the last
    # statement are no-ops, so the output is deterministic. The output path is
    # embedded directly because positional arguments are not forwarded into the
    # helper script.
    command = "( %s ; echo done ) > %s" % (" ; ".join(["true"] * 20000), out.path)
    ctx.actions.run_shell(
        outputs = [out],
        command = command,
        mnemonic = "RunShellLongOutput",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_long_output = rule(
    implementation = _run_shell_long_output_impl,
)
