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

def _run_shell_script_args_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")

    # A script that records its own positional arguments.
    script = ctx.actions.declare_file(ctx.label.name + "_echo_args.sh")
    ctx.actions.write(
        output = script,
        content = """#!/bin/bash
set -euo pipefail
echo "args=($*)" > "$OUT"
""",
        is_executable = True,
    )

    # `arguments` are passed as the positional parameters ($1, $2, ...) of the
    # command string (with an empty $0), not to a script named within it.
    command = script.path
    if ctx.attr.forward_arguments:
        command += " \"$@\""

    ctx.actions.run_shell(
        outputs = [out],
        tools = [script],
        command = command,
        arguments = ["a", "b", "c"],
        env = {"OUT": out.path},
        mnemonic = "RunShellScriptArgs",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_script_args = rule(
    implementation = _run_shell_script_args_impl,
    attrs = {
        "forward_arguments": attr.bool(),
    },
)

def _run_shell_helper_script_args_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")

    command = 'echo "arg=$1" > "$OUT"'
    if ctx.attr.long:
        # Pad past the spill threshold with a trailing comment so the command is
        # written to a helper script without otherwise changing its behavior.
        command += " #" + ("x" * 70000)

    ctx.actions.run_shell(
        outputs = [out],
        command = command,
        arguments = ["the_argument"],
        env = {"OUT": out.path},
        mnemonic = "RunShellHelperScriptArgs",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_helper_script_args = rule(
    implementation = _run_shell_helper_script_args_impl,
    attrs = {
        "long": attr.bool(),
    },
)

def _run_shell_long_output_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")

    # A command well above the 64,000 char (8,000 on Windows) threshold at which
    # run_shell spills the command into a helper script. The length comes from a
    # trailing comment rather than many statements: a deeply nested command list
    # (e.g. tens of thousands of `;`-separated commands) overflows the stack of
    # the smaller-stacked bash on Windows. The output path is embedded directly
    # because positional arguments are not forwarded into the helper script.
    command = "echo done > %s #%s" % (out.path, "x" * 70000)
    ctx.actions.run_shell(
        outputs = [out],
        command = command,
        mnemonic = "RunShellLongOutput",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_long_output = rule(
    implementation = _run_shell_long_output_impl,
)
