load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@rules_shellcheck//:def.bzl", "shellcheck_test")
load("//shell:sh_binary.bzl", "sh_binary")
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

exports_files(
    ["main_data.txt"],
    visibility = ["@rules_shell_test_other_module//:__pkg__"],
)

# runfiles_current_repository and rlocation work in binaries executed as tools
# in actions, both for source and generated scripts in the main repository and
# in another module. Paths are resolved with the repository mapping of the
# respective repository.
genrule(
    name = "gen_current_repository_sh",
    srcs = ["current_repository.sh"],
    outs = ["gen_current_repository.sh"],
    cmd = "cp $< $@",
)

[
    sh_binary(
        name = name,
        srcs = [src],
        data = [
            "main_data.txt",
            "@rules_shell_test_other_module//:data.txt",
        ],
        deps = ["//shell/runfiles"],
    )
    for name, src in [
        ("current_repository", "current_repository.sh"),
        ("gen_current_repository", ":gen_current_repository_sh"),
    ]
]

_MAIN_REPO_PATHS = "rules_shell/tests/runfiles/main_data.txt rules_shell_test_other_module/data.txt"

_OTHER_MODULE_PATHS = "shell_rules/tests/runfiles/main_data.txt rules_shell_test_other_module/data.txt"

[
    genrule(
        name = name + "_in_action",
        outs = [name + "_in_action.txt"],
        cmd = "$(execpath %s) %s > $@" % (tool, paths),
        tools = [tool],
    )
    for name, tool, paths in [
        ("current_repository", ":current_repository", _MAIN_REPO_PATHS),
        ("gen_current_repository", ":gen_current_repository", _MAIN_REPO_PATHS),
        ("other_module_current_repository", "@rules_shell_test_other_module//:current_repository", _OTHER_MODULE_PATHS),
        ("other_module_gen_current_repository", "@rules_shell_test_other_module//:gen_current_repository", _OTHER_MODULE_PATHS),
    ]
]

[
    diff_test(
        name = name + "_in_action_test",
        size = "small",
        file1 = name + "_in_action.txt",
        file2 = golden,
    )
    for name, golden in [
        ("current_repository", "current_repository.golden"),
        ("gen_current_repository", "current_repository.golden"),
        ("other_module_current_repository", "other_module_current_repository.golden"),
        ("other_module_gen_current_repository", "other_module_current_repository.golden"),
    ]
]
