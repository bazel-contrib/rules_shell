load("//shell:sh_library.bzl", "sh_library")
load("//shell/private:root_symlinks.bzl", "ROOT_SYMLINKS_SUPPORTED", "root_symlinks")

# The runfiles library. There is one implementation, runfiles.sh, reachable
# under two names in the runfiles tree:
#
# - bazel_tools/tools/bash/runfiles/runfiles.bash, the path the bash
#   initialization snippets and the launcher source. It is a thin wrapper
#   that sources runfiles.sh.
# - rules_shell/shell/runfiles/runfiles.sh, the path the POSIX initialization
#   snippet sources, for scripts that run under any POSIX shell.
#
# Both are root symlinks, which need the `skip_conflict_checking` parameter
# added in Bazel 7.4.0. Where the native shell rules still exist (Bazel 7) the
# alias keeps resolving to the library bundled with Bazel, as it always has,
# and runfiles.sh is not installed.
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

# runfiles.sh at the path the POSIX init snippet uses
# (`f=rules_shell/shell/runfiles/runfiles.sh`). Its natural path starts with
# this repository's canonical name (`rules_shell+/...`, or `_main/...` when it
# is the main repository), which a copy-pasted snippet cannot know, so the
# symlink gives it one fixed path. It is also the rlocation path consumers see
# for the file through the repository mapping.
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
