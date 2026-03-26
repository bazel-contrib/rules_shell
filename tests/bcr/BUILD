load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_library.bzl", "sh_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load(":is_exec_configuration.bzl", "is_exec_configuration")

is_exec_configuration(
    name = "_is_exec_configuration",
    visibility = ["//visibility:private"],
)

config_setting(
    name = "config_exec",
    flag_values = {":_is_exec_configuration": "yes"},
    visibility = ["//visibility:private"],
)

alias(
    name = "greetings",
    actual = select({
        ":config_exec": "greeting_tool.txt",
        "//conditions:default": "greeting.txt",
    }),
)

sh_library(
    name = "lib",
    srcs = ["lib.sh"],
    data = ["greeting.txt"],
    tools = ["greetings"],
    deps = ["@rules_shell//shell/runfiles"],
)

sh_binary(
    name = "bin",
    srcs = ["bin.sh"],
    deps = [
        ":lib",
        "@rules_shell//shell/runfiles",
    ],
)

sh_test(
    name = "test",
    srcs = ["test.sh"],
    data = [":bin"],
    deps = ["@rules_shell//shell/runfiles"],
)
