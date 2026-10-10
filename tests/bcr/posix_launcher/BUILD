# Coverage for `use_bash_launcher` under a non-bash sh_toolchain: the launcher
# must work under a plain POSIX shell, and the wrapped scripts must be able to
# initialize the runfiles library themselves, since a POSIX shell cannot
# inherit the launcher's functions across exec.
#
# Use private rule implementations directly if all required features are available to provide test
# coverage for Bazel 8.
load("@bazel_features//:features.bzl", "bazel_features")
load("@rules_shell//shell/private:root_symlinks.bzl", "ROOT_SYMLINKS_SUPPORTED")  # buildifier: disable=bzl-visibility
load("@rules_shell//shell/private:sh_binary.bzl", "sh_binary")  # buildifier: disable=bzl-visibility
load("@rules_shell//shell/private:sh_library.bzl", "sh_library")  # buildifier: disable=bzl-visibility
load("@rules_shell//shell/private:sh_test.bzl", "sh_test")  # buildifier: disable=bzl-visibility

# These scripts source `rules_shell/shell/runfiles/runfiles.sh`, which
# `@rules_shell//shell/runfiles` only installs where it provides the library
# itself rather than deferring to the one bundled with Bazel (see
# ROOT_SYMLINKS_SUPPORTED), i.e. on Bazel 8 and newer.
_HAS_POSIX_RUNFILES = ROOT_SYMLINKS_SUPPORTED and bazel_features.rules._has_launcher_maker_toolchain

sh_library(
    name = "lib",
    srcs = ["lib.sh"],
    data = ["greeting.txt"],
)

_HAS_POSIX_RUNFILES and sh_binary(
    name = "bin",
    srcs = ["bin.sh"],
    use_bash_launcher = True,
    deps = [":lib"],
)  # buildifier: disable=no-effect

_HAS_POSIX_RUNFILES and sh_test(
    name = "test",
    srcs = ["test.sh"],
    data = [":bin"],
    use_bash_launcher = True,
)  # buildifier: disable=no-effect
