load("@rules_shell//shell:sh_test.bzl", "sh_test")
load(":defs.bzl", "greeting")

greeting(
    name = "inline",
)

greeting(
    name = "spilled",
    spill = True,
)

sh_test(
    name = "test",
    srcs = ["test.sh"],
    data = [
        ":inline",
        ":spilled",
    ],
    deps = ["@rules_shell//shell/runfiles"],
)
