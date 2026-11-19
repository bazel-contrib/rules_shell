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

"""Implementation of `run_shell`, see `//shell:run_shell.bzl` for docs."""

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
        ctx: The rule context.
        command: Shell command to execute, as a string. The command is
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
        arguments: Command line arguments of the action. Must be a sequence of
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
            respectively. Prefer to use patterns instead of concatenating or
            formatting these values into the message, because the former are
            more efficient.
        use_default_shell_env: Whether the action should use the default shell
            environment, which consists of a few OS-dependent variables as well
            as variables set via `--action_env`. If both `use_default_shell_env`
            and `env` are set, values set in `env` will overwrite the default
            shell environment.
        env: Sets the dictionary of environment variables.
        execution_requirements: Information for scheduling the action.
        exec_group: The execution group for the action.
        shadowed_action: An action whose inputs and environment are made
            available to this action in addition to its own.
        resource_set: A callback returning a dictionary of resource estimates
            (e.g. memory, CPU) for scheduling the action locally.
    """
    if type(command) != type(""):
        fail("'command' must be of type string, got %s" % type(command))

    # Only forward optional arguments that are set so that the native function
    # behaves as if it was called directly. In particular, it doesn't allow an
    # explicit None value for shadowed_action.
    optional_args = {
        "mnemonic": mnemonic,
        "progress_message": progress_message,
        "env": env,
        "execution_requirements": execution_requirements,
        "exec_group": exec_group,
        "shadowed_action": shadowed_action,
        "resource_set": resource_set,
    }
    kwargs = {name: value for name, value in optional_args.items() if value != None}

    ctx.actions.run_shell(
        command = command,
        outputs = outputs,
        inputs = inputs,
        tools = tools,
        arguments = arguments,
        use_default_shell_env = use_default_shell_env,
        **kwargs
    )
