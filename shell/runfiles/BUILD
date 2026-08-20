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
    data = [
        ":runfiles_sh_at_documented_location",
        ":runfiles_sh_at_legacy_location",
    ],
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

# Place runfiles.sh at the root path used by the documented init snippet
# (`f=shell/runfiles/runfiles.sh`). Without this, the file would only appear
# under its repo-prefixed location (e.g. `_main/shell/runfiles/runfiles.sh`
# or `rules_shell+/shell/runfiles/runfiles.sh`) and copy-pasting the snippet
# would fail with `ERROR: cannot find shell/runfiles/runfiles.sh`.
root_symlinks(
    name = "runfiles_sh_at_documented_location",
    root_symlinks = {
        "runfiles.sh": "shell/runfiles/runfiles.sh",
    },
    tags = ["manual"],
)

# Native `sh_test` (used when Bazel exposes it — legacy 7/8 modes and some
# launcher paths) hardcodes `f=bazel_tools/tools/bash/runfiles/runfiles.bash`
# in its generated launcher and cannot be redirected from Starlark. When the
# `experimental_use_shell_runfiles` flag swaps the `:runfiles` alias to this
# target, that path must still resolve to something sourceable — otherwise
# every native sh_test in the build dies with
# `ERROR: cannot find bazel_tools/tools/bash/runfiles/runfiles.bash`.
# Bash and sh impls never appear in the same runfiles tree (the alias uses a
# mutually-exclusive select), so the shared path is safe.
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
