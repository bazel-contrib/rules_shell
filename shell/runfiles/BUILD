load("//shell:sh_library.bzl", "sh_library")
load("//shell/private:root_symlinks.bzl", "ROOT_SYMLINKS_SUPPORTED", "root_symlinks")

config_setting(
    name = "use_shell_runfiles",
    flag_values = {"//shell/settings:experimental_use_shell_runfiles": "true"},
)

alias(
    name = "runfiles",
    actual = select({
        ":use_shell_runfiles": ":runfiles_sh_impl",
        "//conditions:default": ":runfiles_impl" if ROOT_SYMLINKS_SUPPORTED else "@bazel_tools//tools/bash/runfiles",
    }),
    visibility = ["//visibility:public"],
)

sh_library(
    name = "runfiles_impl",
    data = [":runfiles_at_legacy_location"],
    tags = ["manual"],
    visibility = ["//visibility:public"],
    deps = [":runfiles_bash"],
)

sh_library(
    name = "runfiles_bash",
    srcs = ["runfiles.bash"],
    tags = ["manual"],
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
    name = "runfiles_sh_impl",
    data = [":runfiles_sh_at_legacy_location"],
    tags = ["manual"],
    visibility = ["//visibility:public"],
    deps = [":runfiles_sh"],
)

sh_library(
    name = "runfiles_sh",
    srcs = ["runfiles.sh"],
    tags = ["manual"],
    visibility = ["//visibility:public"],
)

root_symlinks(
    name = "runfiles_sh_at_legacy_location",
    root_symlinks = {
        "runfiles.sh": "bazel_tools/tools/bash/runfiles/runfiles.bash",
    },
    tags = ["manual"],
)

exports_files(
    [
        "runfiles.bash",
        "runfiles.sh",
    ],
    visibility = ["//tests/runfiles:__pkg__"],
)
