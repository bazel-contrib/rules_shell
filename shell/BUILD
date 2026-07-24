# A runtime toolchain for shell scripts.
#
# Use `sh_toolchain` to register a toolchain for this type.
#
# Every toolchain registered for this type has the following attributes:
# - `path`: The path to the shell interpreter for the target platform.
#
# Other attribute may be present but are considered implementation details of
# Bazel's sh_* rules.
#
# Toolchains registered for this type should have target constraints.

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

toolchain_type(
    name = "toolchain_type",
    visibility = ["//visibility:public"],
)

exports_files(
    [
        "repositories.bzl",
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
    ],
)
