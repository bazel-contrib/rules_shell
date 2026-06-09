# Copyright 2018 The Bazel Authors. All rights reserved.
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
"""Defines a toolchain rule for shell build actions."""

visibility("public")

SH_EXEC_TOOLCHAIN_TYPE = Label("//shell:exec_toolchain_type")

ShExecToolchainInfo = provider(
    doc = "A toolchain used to execute shell commands in a build action.",
    fields = {
        "interpreter": "(str|FilesToRunProvider) The shell interpreter to use, either non-hermetic (absolute path) or hermetic (FilesToRunProvider).",
        "max_command_length": "(int) The maximum command length before spilling to a helper script.",
    },
)

def _sh_exec_toolchain_impl(ctx):
    """sh_exec_toolchain rule implementation."""
    return [
        platform_common.ToolchainInfo(
            sh_exec_toolchain = ShExecToolchainInfo(
                interpreter = ctx.attr.path,
                max_command_length = ctx.attr.max_command_length,
            ),
        ),
    ]

sh_exec_toolchain = rule(
    doc = "A toolchain used to execute shell commands in a build action.",
    attrs = {
        "path": attr.string(
            doc = "Absolute path to the non-hermetic shell interpreter.",
            mandatory = True,
        ),
        "max_command_length": attr.int(
            doc = "The maximum command length before spilling to a helper script.",
            mandatory = True,
        ),
    },
    implementation = _sh_exec_toolchain_impl,
)
