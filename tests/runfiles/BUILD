load("@rules_shellcheck//:def.bzl", "shellcheck_test")
load("//shell:sh_test.bzl", "sh_test")

sh_test(
    name = "runfiles_test",
    srcs = ["runfiles_test.bash"],
    deps = ["//shell/runfiles"],
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
