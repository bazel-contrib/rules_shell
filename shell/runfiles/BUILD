load("//shell:sh_library.bzl", "sh_library")
load("//shell/private:root_symlinks.bzl", "ROOT_SYMLINKS_SUPPORTED", "root_symlinks")

config_setting(
    name = "use_shell_runfiles",
    flag_values = {"//shell/settings:experimental_use_shell_runfiles": "true"},
)

alias(
    name = "runfiles",
    actual = select({
        ":use_shell_runfiles": ":runfiles_sh",
        "//conditions:default": ":runfiles_bash" if ROOT_SYMLINKS_SUPPORTED else "@bazel_tools//tools/bash/runfiles",
    }),
    visibility = ["//visibility:public"],
)

sh_library(
    name = "runfiles_bash",
    srcs = ["runfiles.bash"],
    data = [":runfiles_at_legacy_location"],
    visibility = ["//visibility:public"],
)

root_symlinks(
    name = "runfiles_at_legacy_location",
    root_symlinks = {
        "runfiles.bash": "bazel_tools/tools/bash/runfiles/runfiles.bash",
    },
    tags = ["manual"],
)

sh_library(
    name = "runfiles_sh",
    srcs = ["runfiles.sh"],
    visibility = ["//visibility:public"],
)

exports_files(
    [
        "runfiles.bash",
        "runfiles.sh",
    ],
    visibility = ["//tests/runfiles:__pkg__"],
)
