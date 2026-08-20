load("@rules_shellcheck//:def.bzl", "shellcheck_test")
load("//shell:sh_test.bzl", "sh_test")

sh_test(
    name = "runfiles_bash_test",
    srcs = ["runfiles_test.bash"],
    deps = ["//shell/runfiles:runfiles_impl"],
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
    # On Linux, /bin/sh is dash by default, so the test genuinely exercises
    # the POSIX code paths. On macOS /bin/sh is bash-in-POSIX-mode and on
    # Windows the sh_test goes through the bash launcher — in both cases the
    # in-file guard would trip, so opt out. The dedicated
    # `test_posix_shell_runfiles` presubmit task verifies dash coverage on
    # Linux by refusing to opt out.
    env = select({
        "@platforms//os:linux": {
            "RUNFILES_LIBRARY_FILE": "$(rlocationpath //shell/runfiles:runfiles_sh)",
        },
        "//conditions:default": {
            "RUNFILES_LIBRARY_FILE": "$(rlocationpath //shell/runfiles:runfiles_sh)",
            "RUNFILES_TEST_ALLOW_BASH": "1",
        },
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
