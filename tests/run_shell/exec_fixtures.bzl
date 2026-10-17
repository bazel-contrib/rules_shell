"""Rules that execute the `run_shell` function and expose the produced output.

The single output file of each target is compared against a golden file with
`diff_test`, which exercises the runtime behavior of `run_shell` (command
execution, positional argument substitution, environment, helper scripts for
long commands) without a Bazel-in-Bazel integration test.
"""

load("@with_cfg.bzl", "with_cfg")
load("//shell:run_shell.bzl", "run_shell")

def _run_shell_output_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        outputs = [out],
        command = ctx.attr.command + (" #" + "x" * 70000 if ctx.attr.long else ""),
        arguments = [out.path] + ctx.attr.extra_arguments,
        env = (ctx.attr.env or {}) | {"OUT": out.path},
        use_default_shell_env = ctx.attr.use_default_shell_env,
        mnemonic = "RunShellOutput",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_output = rule(
    implementation = _run_shell_output_impl,
    attrs = {
        # The shell command. `$1` and `$OUT` are the output path; `$2`, `$3`,
        # ... are `extra_arguments`.
        "command": attr.string(mandatory = True),
        "extra_arguments": attr.string_list(),
        "env": attr.string_dict(),
        # Whether to pad the command with a trailing comment so that it
        # exceeds the maximum command length on all platforms and is spilled
        # into a helper script.
        "long": attr.bool(),
        "use_default_shell_env": attr.bool(),
    },
)

# Same as run_shell_output, but transitions --action_env so that targets can
# observe an action env entry when use_default_shell_env = True.
_ACTION_ENV = [
    "FROM_ACTION_ENV=action_env_value",
    "OTHER_ACTION_ENV=other_action_env_value",
]

run_shell_output_with_action_env, _run_shell_output_with_action_env = (
    with_cfg(run_shell_output)
        .extend("action_env", _ACTION_ENV)
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

    run_shell(
        ctx,
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

    run_shell(
        ctx,
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
    # the smaller-stacked bash on Windows.
    command = "echo done > \"$OUT\" #%s" % ("x" * 70000)
    run_shell(
        ctx,
        outputs = [out],
        command = command,
        env = {"OUT": out.path},
        mnemonic = "RunShellLongOutput",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_long_output = rule(
    implementation = _run_shell_long_output_impl,
)

def _run_shell_param_file_args_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    args = ctx.actions.args()
    args.add("--foo")
    args.use_param_file("--file=%s", use_always = True)

    # Writes an empty output if no arguments are passed.
    command = "if [ $# -gt 0 ]; then cat \"${1#--file=}\"; fi > \"$OUT\""
    if ctx.attr.long:
        command += " #" + ("x" * 70000)
    run_shell(
        ctx,
        outputs = [out],
        command = command,
        arguments = [args],
        env = {"OUT": out.path},
        mnemonic = "RunShellParamFileArgs",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_param_file_args = rule(
    implementation = _run_shell_param_file_args_impl,
    attrs = {
        "long": attr.bool(),
    },
)

# Arguments that are easily mangled on their way to the shell, in particular
# on Windows.
_TRICKY_ARGUMENTS = [
    "a b",
    "\"b\"",
    "",
    "$x",
    "`b`",
    ";",
    "C:\\a\\b\\",
    "\"C:\\a b\\c\\\"",
]

def _run_shell_arguments_as_command_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")

    # Records the number of arguments and each argument (but the first, which
    # is the output path) in brackets.
    recorder = ctx.actions.declare_file(ctx.label.name + "_record_args.sh")
    ctx.actions.write(
        output = recorder,
        content = """#!/bin/bash
out="$1"
shift
{ printf '%s\\n' "$#"; printf '[%s]\\n' "$@"; } > "$out"
""",
        is_executable = True,
    )
    command = ctx.attr.command
    if ctx.attr.long:
        # Writes an empty output if no arguments are passed.
        command += "\n[ -e \"$OUT\" ] || : > \"$OUT\" #" + ("x" * 70000)
    run_shell(
        ctx,
        outputs = [out],
        tools = [recorder],
        command = command,
        arguments = [recorder.path, out.path] + _TRICKY_ARGUMENTS,
        env = {"OUT": out.path},
        mnemonic = "RunShellArgumentsAsCommand",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_arguments_as_command = rule(
    implementation = _run_shell_arguments_as_command_impl,
    attrs = {
        # A command that executes its positional arguments as a command.
        "command": attr.string(mandatory = True),
        "long": attr.bool(),
    },
)

def _run_shell_tool_output_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    files_to_run = ctx.attr.tool[DefaultInfo].files_to_run
    tools = {
        "depset": depset([ctx.executable.tool]),
        "file": [ctx.executable.tool],
        "files_to_run": [files_to_run],
    }[ctx.attr.tools_type]
    run_shell(
        ctx,
        outputs = [out],
        inputs = [ctx.executable.tool] if ctx.attr.tool_in_inputs else [],
        tools = tools,
        command = "\"$1\" \"$2\"",
        arguments = [ctx.executable.tool.path, out.path],
        mnemonic = "RunShellToolOutput",
    )
    return [DefaultInfo(files = depset([out]))]

run_shell_tool_output = rule(
    implementation = _run_shell_tool_output_impl,
    attrs = {
        # An executable that writes the contents of a data file to the path
        # given as its first argument.
        "tool": attr.label(cfg = "exec", executable = True, mandatory = True),
        # Whether to also pass the tool as an input.
        "tool_in_inputs": attr.bool(),
        "tools_type": attr.string(
            mandatory = True,
            values = ["depset", "file", "files_to_run"],
        ),
    },
)

def _run_shell_three_commands_impl(ctx):
    outs = []
    for i, long in enumerate([True, False, True]):
        out = ctx.actions.declare_file("%s_%d.txt" % (ctx.label.name, i))
        command = "echo command%d > %s" % (i, out.path)
        if long:
            command += " #" + ("x" * 70000)
        run_shell(
            ctx,
            outputs = [out],
            command = command,
            mnemonic = "RunShellCommand%d" % i,
        )
        outs.append(out)

    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        outputs = [out],
        inputs = outs,
        command = "cat %s > %s" % (" ".join([f.path for f in outs]), out.path),
        mnemonic = "RunShellConcat",
    )
    return [DefaultInfo(files = depset([out]))]

# Runs a long, a short, and another long command in a single rule
# implementation, then concatenates their outputs.
run_shell_three_commands = rule(
    implementation = _run_shell_three_commands_impl,
)

def _run_shell_with_env_and_input_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    run_shell(
        ctx,
        outputs = [out],
        inputs = [ctx.file.src],
        command = "cp %s %s" % (ctx.file.src.path, out.path),
        env = {
            "OVERRIDDEN": "from_shadowed_action",
            "SHADOWED": "from_shadowed_action",
        },
        mnemonic = "RunShellWithEnvAndInput",
    )
    return [DefaultInfo(files = depset([out]))]

# The target of run_shell_aspect_output, whose action is shadowed by the
# action of the aspect.
run_shell_with_env_and_input = rule(
    implementation = _run_shell_with_env_and_input_impl,
    attrs = {
        "src": attr.label(allow_single_file = True, mandatory = True),
    },
)

RunShellAspectInfo = provider(
    doc = "The outputs of the run_shell aspects.",
    fields = ["plain", "shadowed"],
)

def _run_shell_aspect_impl(target, ctx):
    plain = ctx.actions.declare_file(ctx.label.name + "_plain_aspect.out")
    run_shell(
        ctx,
        outputs = [plain],
        command = "echo from_aspect > " + plain.path,
        mnemonic = "RunShellAspectPlain",
    )

    # The aspect's action reads the input and sees the environment of the
    # target's action without declaring them itself, in addition to its own.
    shadowed = ctx.actions.declare_file(ctx.label.name + "_shadowed_aspect.out")
    run_shell(
        ctx,
        outputs = [shadowed],
        inputs = [ctx.file._aspect_input],
        command = "{{ cat {src} {aspect_input}; echo \"$SHADOWED $OVERRIDDEN\"; }} > {out}".format(
            src = ctx.rule.file.src.path,
            aspect_input = ctx.file._aspect_input.path,
            out = shadowed.path,
        ),
        env = {"OVERRIDDEN": "from_aspect"},
        shadowed_action = target.actions[0],
        mnemonic = "RunShellAspectShadowed",
    )
    return [RunShellAspectInfo(plain = plain, shadowed = shadowed)]

_run_shell_aspect = aspect(
    implementation = _run_shell_aspect_impl,
    attrs = {
        "_aspect_input": attr.label(
            allow_single_file = True,
            default = ":aspect_input.txt",
        ),
    },
)

def _run_shell_aspect_output_impl(ctx):
    info = ctx.attr.dep[RunShellAspectInfo]
    return [DefaultInfo(files = depset([getattr(info, ctx.attr.output)]))]

run_shell_aspect_output = rule(
    implementation = _run_shell_aspect_output_impl,
    attrs = {
        "dep": attr.label(aspects = [_run_shell_aspect], mandatory = True),
        "output": attr.string(mandatory = True, values = ["plain", "shadowed"]),
    },
)

def _run_shell_tree_artifact_args_impl(ctx):
    directory = ctx.actions.declare_directory(ctx.label.name + "_dir")
    run_shell(
        ctx,
        outputs = [directory],
        command = "echo a > $1/a.txt && echo b > $1/b.txt",
        arguments = [directory.path],
        mnemonic = "RunShellTreeArtifact",
    )

    out = ctx.actions.declare_file(ctx.label.name + ".out")
    args = ctx.actions.args()
    args.add("--first")
    args.add_all([directory])
    args.add("--last")
    run_shell(
        ctx,
        outputs = [out],
        inputs = [directory],
        command = """out="$1"
shift
{
  printf '%s\\n' "$#"
  for arg in "$@"; do
    case "$arg" in
      --*) echo "$arg" ;;
      *) echo "${arg##*/}: $(cat "$arg")" ;;
    esac
  done
} > "$out"
""",
        arguments = [out.path, args],
        mnemonic = "RunShellTreeArtifactArgs",
    )
    return [DefaultInfo(files = depset([out]))]

# Expands a tree artifact in an Args object passed to the command.
run_shell_tree_artifact_args = rule(
    implementation = _run_shell_tree_artifact_args_impl,
)
