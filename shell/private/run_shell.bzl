# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""A wrapper around `ctx.actions.run` that runs a shell command.

This mirrors the behavior of the native `ctx.actions.run_shell` function.

Rules calling `run_shell` must depend on the shell exec toolchain via
`toolchains = [SH_EXEC_TOOLCHAIN_TYPE]` (loaded from
`@rules_shell//shell/toolchains:sh_exec_toolchain.bzl`).
"""

load("@rules_shell//shell/toolchains:sh_exec_toolchain.bzl", "SH_EXEC_TOOLCHAIN_TYPE")

visibility("public")

def run_shell(
        ctx,
        *,
        command,
        outputs,
        inputs = [],
        tools = [],
        arguments = [],
        mnemonic = None,
        progress_message = None,
        use_default_shell_env = False,
        env = None,
        execution_requirements = None,
        exec_group = None,
        shadowed_action = None,
        resource_set = None):
    """Creates an action that runs a shell command.

    Args:
        ctx: The rule context. The calling rule must depend on the shell
            toolchain type, e.g. via `toolchains = ["//shell:toolchain_type"]`.
        command: Shell command to execute. Unlike the native
            `ctx.actions.run_shell`, only a string is accepted; passing a
            sequence of strings is deprecated and rejected. The command is
            executed as `sh -c <command> "" <arguments>`, which makes the
            `arguments` available as `$1`, `$2`, etc. If an `Args` object of
            unknown size is passed as part of `arguments`, then the strings
            will be at unknown indices; in this case the `$@` shell
            substitution (retrieve all arguments) may be useful.
        outputs: List of the output files of the action.
        inputs: List or depset of the input files of the action.
        tools: List or depset of any tools needed by the action. Tools are
            executable inputs that may have their own runfiles which are
            automatically made available to the action.
        arguments: Command line arguments of the action. Must be a list of
            strings or `actions.args()` objects. Bazel passes the elements in
            this attribute as arguments to the command. The command can access
            these arguments using shell variable substitutions such as `$1`,
            `$2`, etc. Note that since `Args` objects are flattened before
            indexing, if there is an `Args` object of unknown size then all
            subsequent strings will be at unpredictable indices.
        mnemonic: A one-word description of the action, for example,
            CppCompile or GoLink.
        progress_message: Progress message to show to the user during the
            build, for example, "Compiling foo.cc to create foo.o". The message
            may contain `%{label}`, `%{input}`, or `%{output}` patterns, which
            are substituted with label string, first input, or output's path,
            respectively. Prefer to use patterns instead of static strings,
            because the former are more efficient.
        use_default_shell_env: Whether the action should use the default shell
            environment, which consists of a few OS-dependent variables as well
            as variables set via `--action_env`. If both `use_default_shell_env`
            and `env` are set, values set in `env` will overwrite the default
            shell environment.
        env: Sets the dictionary of environment variables.
        execution_requirements: Information for scheduling the action.
        exec_group: The execution group for the action. The shell exec toolchain
            will be obtained from this group.
    """
    if type(command) != type(""):
        fail("'command' must be of type string, got %s" % type(command))

    toolchains = ctx.exec_groups[exec_group] if exec_group else ctx.toolchains
    sh_exec_toolchain = toolchains[SH_EXEC_TOOLCHAIN_TYPE].sh_exec_toolchain

    interpreter_args = ctx.actions.args()
    if len(command) <= sh_exec_toolchain.max_command_length:
        interpreter_args.add("-c")
        interpreter_args.add(command)

        # Preserve the long-standing behavior of `ctx.actions.run_shell` passing
        # an empty string as $0 (if any args are passed).
        if arguments:
            interpreter_args.add("")
    else:
        # Spill the command into a helper script and reference it instead. The
        # script is executed directly rather than via `<interpeter> -c` so that
        # the given interpreter is used without the need to synthesize a
        # shebang.
        interpreter_args.use_param_file("%s", use_always = True)
        interpreter_args.set_param_file_format("multiline")
        interpreter_args.add(command)

    # shadowed_action doesn't allow an explicit None value.
    run_kwargs = {"shadowed_action": shadowed_action} if shadowed_action else {}

    ctx.actions.run(
        executable = sh_exec_toolchain.interpreter,
        arguments = [interpreter_args] + arguments,
        outputs = outputs,
        inputs = inputs,
        tools = tools,
        mnemonic = mnemonic,
        progress_message = progress_message,
        use_default_shell_env = use_default_shell_env,
        env = env,
        execution_requirements = execution_requirements,
        toolchain = SH_EXEC_TOOLCHAIN_TYPE,
        exec_group = exec_group,
        resource_set = resource_set,
        **run_kwargs
    )
