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

Unlike the native function, `run_shell` doesn't accept the `toolchain` and
`input_manifests` parameters. The action always uses the execution platform
selected for the shell exec toolchain. With `--incompatible_auto_exec_groups`,
a command that also uses tools from other toolchains should run in an exec group
that requires all of these toolchain types, passed as `exec_group`. These tools
then also have to be obtained from `ctx.exec_groups[<exec_group>].toolchains`.
"""

load("//shell/private:run_shell.bzl", _run_shell = "run_shell")

visibility("public")

run_shell = _run_shell
