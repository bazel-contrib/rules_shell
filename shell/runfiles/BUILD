load("//shell:sh_library.bzl", "sh_library")
load("//shell/private:root_symlinks.bzl", "ROOT_SYMLINKS_SUPPORTED", "root_symlinks")

# The runfiles library. There is one implementation, runfiles.sh, reachable
# under two names in the runfiles tree:
#
# - bazel_tools/tools/bash/runfiles/runfiles.bash, the path the bash
#   initialization snippet (v3) and the launcher under bash source. It is a
#   thin wrapper that sources runfiles.sh with awk enabled by default, so that
#   scripts written against the historical grep-based library keep lookups
#   whose cost does not grow with the manifest, and it exports everything that
#   library exported.
# - rules_shell/shell/runfiles/runfiles.sh, the path the POSIX initialization
#   snippet (v1) and the launcher under any other shell source, which gets the
#   pure POSIX behavior: shell builtins only.
#
# Both are root symlinks, which need the `skip_conflict_checking` parameter
# added in Bazel 7.4.0. Where the native shell rules still exist (Bazel 7) the
# alias keeps resolving to the library bundled with Bazel, as it always has,
# and runfiles.sh is not installed: a launcher there has to run under bash.
alias(
    name = "runfiles",
    actual = ":runfiles_impl" if ROOT_SYMLINKS_SUPPORTED else "@bazel_tools//tools/bash/runfiles",
    visibility = ["//visibility:public"],
)

sh_library(
    name = "runfiles_impl",
    data = [
        ":runfiles_at_legacy_location",
        ":runfiles_sh_at_documented_location",
    ],
    tags = ["manual"],
)

# runfiles.bash locates runfiles.sh next to itself, so the two are installed
# side by side at the legacy location, as they are in the source tree.
root_symlinks(
    name = "runfiles_at_legacy_location",
    root_symlinks = {
        "runfiles.bash": "bazel_tools/tools/bash/runfiles/runfiles.bash",
        "runfiles.sh": "bazel_tools/tools/bash/runfiles/runfiles.sh",
    },
    tags = ["manual"],
)

# Place runfiles.sh at the path used by the documented POSIX init snippet
# (`f=rules_shell/shell/runfiles/runfiles.sh`). Its natural location depends on
# the canonical name of this repository (`rules_shell+/...` under Bzlmod,
# `rules_shell/...` under WORKSPACE, `_main/...` when it is the main
# repository), which a copy-pasted snippet cannot know; the symlink makes the
# WORKSPACE spelling hold everywhere. Under Bzlmod it is also the rlocation path
# consumers use for the file, through the repository mapping.
root_symlinks(
    name = "runfiles_sh_at_documented_location",
    root_symlinks = {
        "runfiles.sh": "rules_shell/shell/runfiles/runfiles.sh",
    },
    tags = ["manual"],
)

# runfiles.sh on its own, under its natural path, for the test suites to source
# the POSIX library directly.
sh_library(
    name = "runfiles_sh",
    srcs = ["runfiles.sh"],
    tags = ["manual"],
    visibility = ["//tests/runfiles:__pkg__"],
)

exports_files(
    [
        "runfiles.bash",
        "runfiles.sh",
    ],
    visibility = ["//tests/runfiles:__pkg__"],
)
