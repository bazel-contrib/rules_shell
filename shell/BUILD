load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

# A runtime toolchain for shell scripts.
#
# Used at runtime by sh_binary and sh_test targets.
#
# Register `sh_toolchain` targets for this type.
#
# Every toolchain registered for this type has the following attributes:
# - `path`: The path to the shell interpreter for the target platform.
#
# Other attributes may be present but are considered implementation details of
# Bazel's sh_* rules.
#
# Toolchains registered for this type should have target constraints.
toolchain_type(
    name = "toolchain_type",
    visibility = ["//visibility:public"],
)

# An exec toolchain for shell commands.
#
# Used in rule implementations that use `run_shell` to run shell commands at build time.
#
# Register `sh_exec_toolchain` targets for this type.
#
# Every toolchain registered for this type has a `sh_exec_toolchain` attribute
# holding a `ShExecToolchainInfo` (see `sh_exec_toolchain.bzl`) with the
# following fields:
# - `interpreter`: The shell interpreter for the execution platform, either as
#   an absolute path or as a `FilesToRunProvider`.
# - `max_command_length`: The maximum command length before spilling to a helper script.
#
# Other attributes may be present but are considered implementation details of
# the `run_shell` implementation.
#
# Toolchains registered for this type should have exec constraints.
toolchain_type(
    name = "exec_toolchain_type",
    visibility = ["//visibility:public"],
)

exports_files(
    [
        "repositories.bzl",
        "run_shell.bzl",
        "sh_binary.bzl",
        "sh_binary_info.bzl",
        "sh_info.bzl",
        "sh_library.bzl",
        "sh_test.bzl",
    ],
    visibility = ["//visibility:public"],
)

bzl_library(
    name = "rules_bzl",
    srcs = [
        "repositories.bzl",
        "run_shell.bzl",
        "sh_binary.bzl",
        "sh_binary_info.bzl",
        "sh_info.bzl",
        "sh_library.bzl",
        "sh_test.bzl",
    ],
    visibility = ["//visibility:public"],
    deps = [
        "//shell/private:private_bzl",
        "//shell/private/repositories:bazel_tools_bzl",
        "//shell/private/repositories:repositories_bzl",
        "//shell/toolchains:toolchains_bzl",
    ],
)
