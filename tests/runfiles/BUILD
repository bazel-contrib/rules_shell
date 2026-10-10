load("@rules_shellcheck//:def.bzl", "shellcheck_test")
load("//shell:sh_test.bzl", "sh_test")

# The bash suite against the library as every bash script sees it: through
# `//shell/runfiles` and the legacy `bazel_tools/tools/bash/runfiles/runfiles.bash`
# path, where runfiles.bash wraps runfiles.sh with awk enabled.
sh_test(
    name = "runfiles_bash_test",
    srcs = ["runfiles_test.bash"],
    deps = ["//shell/runfiles"],
)

# The same, with the wrapper's awk default switched off, so that the shell loops
# are what the bash suite exercises through the legacy path.
sh_test(
    name = "runfiles_bash_no_awk_test",
    srcs = ["runfiles_test.bash"],
    env = {"RULES_SHELL_RUNFILES_USE_AWK": "0"},
    deps = ["//shell/runfiles"],
)

sh_test(
    name = "runfiles_sh_from_bash_test",
    srcs = ["runfiles_test.bash"],
    # RUNFILES_LIBRARY_FILE is read by runfiles_test.bash's find_runfiles_lib
    # helper to locate the library under test. Adding the target to `data` so
    # $(rlocationpath ...) resolves (only `data` is passed to
    # ctx.expand_location in sh_executable.bzl).
    data = ["//shell/runfiles:runfiles_sh"],
    env = {
        "RUNFILES_LIBRARY_FILE": "$(rlocationpath //shell/runfiles:runfiles_sh)",
    },
    deps = ["//shell/runfiles:runfiles_sh"],
)

sh_test(
    name = "runfiles_sh_test",
    srcs = ["runfiles_test.sh"],
    # Pass the rlocation path of runfiles.sh so the test can find it without
    # hardcoding the main-repo prefix (which differs between Bzlmod `_main/`
    # and WORKSPACE `rules_shell/`).
    data = ["//shell/runfiles:runfiles_sh"],
    # The suite runs under whatever `#!/bin/sh` resolves to: dash on Debian and
    # Ubuntu, bash elsewhere. The `test_posix_shell_runfiles` presubmit task
    # guarantees dash coverage by setting RUNFILES_TEST_REQUIRE_POSIX_SH.
    #
    # Running under bash selects the bash-specific key mangling and case
    # folding, which `runfiles_sh_under_bash_test` covers on Linux. macOS
    # forces the portable variants so that they are exercised somewhere.
    # Windows must not: it is the one case-insensitive platform, where the
    # library only indexes if the shell can fold case cheaply, so forcing the
    # portable variants there would disable indexing rather than cover it.
    env = select({
        "@platforms//os:macos": {
            "RUNFILES_LIBRARY_FILE": "$(rlocationpath //shell/runfiles:runfiles_sh)",
            "RULES_SHELL_RUNFILES_PORTABLE_INDEX": "1",
        },
        "//conditions:default": {
            "RUNFILES_LIBRARY_FILE": "$(rlocationpath //shell/runfiles:runfiles_sh)",
        },
    }),
    deps = ["//shell/runfiles:runfiles_sh"],
)

sh_test(
    name = "runfiles_sh_awk_test",
    srcs = ["runfiles_test.sh"],
    data = ["//shell/runfiles:runfiles_sh"],
    # The same suite with manifests searched by awk instead of shell loops.
    env = {
        "RUNFILES_LIBRARY_FILE": "$(rlocationpath //shell/runfiles:runfiles_sh)",
        "RULES_SHELL_RUNFILES_USE_AWK": "1",
    },
    deps = ["//shell/runfiles:runfiles_sh"],
)

sh_test(
    name = "runfiles_sh_under_bash_test",
    srcs = ["runfiles_test_under_bash.sh"],
    data = [
        "runfiles_test.sh",
        "//shell/runfiles:runfiles_sh",
    ],
    env = {
        "RUNFILES_LIBRARY_FILE": "$(rlocationpath //shell/runfiles:runfiles_sh)",
    },
    # bash is what the default sh_toolchain resolves to, so this is the
    # configuration most users run; see runfiles_test_under_bash.sh.
    target_compatible_with = select({
        "@platforms//os:linux": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = ["//shell/runfiles:runfiles_sh"],
)

shellcheck_test(
    name = "runfiles_shellcheck_test",
    data = ["//shell/runfiles:runfiles.bash"],
    format = "gcc",
    severity = "warning",
    # Fails on Windows with:
    # '..' is not recognized as an internal or external command, operable program or batch file.
    target_compatible_with = select({
        "@platforms//os:windows": ["@platforms//:incompatible"],
        "//conditions:default": [],
    }),
)

shellcheck_test(
    name = "runfiles_sh_shellcheck_test",
    data = ["//shell/runfiles:runfiles.sh"],
    format = "gcc",
    severity = "warning",
    # Fails on Windows with:
    # '..' is not recognized as an internal or external command, operable program or batch file.
    target_compatible_with = select({
        "@platforms//os:windows": ["@platforms//:incompatible"],
        "//conditions:default": [],
    }),
)
