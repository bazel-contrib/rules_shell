load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load(":default_sh_exec_toolchain.bzl", "shell_executable_setting")

bzl_library(
    name = "private_bzl",
    srcs = [
        "default_sh_exec_toolchain.bzl",
        "providers.bzl",
        "run_shell.bzl",
        "sh_binary.bzl",
        "sh_executable.bzl",
        "sh_library.bzl",
        "sh_test.bzl",
    ],
    visibility = ["//shell:__pkg__"],
    deps = ["//shell/toolchains:toolchains_bzl"],
)

# Carries the value of the native `--shell_executable` flag into the default
# shell exec toolchains.
shell_executable_setting(
    name = "shell_executable",
    build_setting_default = "",
    visibility = ["//visibility:public"],
)
