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
    env = {
        "RUNFILES_LIBRARY_FILE": "$(rlocationpath //shell/runfiles:runfiles_sh)",
    },
    deps = ["//shell/runfiles:runfiles_sh"],
)

sh_test(
    name = "runfiles_sh_test",
    srcs = ["runfiles_test.sh"],
    deps = ["//shell/runfiles:runfiles_sh"],
)

shellcheck_test(
    name = "runfiles_shellcheck_test",
    data = ["//shell/runfiles:runfiles.bash"],
    format = "gcc",
    severity = "warning",
)

shellcheck_test(
    name = "runfiles_sh_shellcheck_test",
    data = ["//shell/runfiles:runfiles.sh"],
    format = "gcc",
    severity = "warning",
)
