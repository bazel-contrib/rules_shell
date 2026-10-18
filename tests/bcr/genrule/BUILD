load("@rules_shell//shell:genrule.bzl", "genrule")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

genrule(
    name = "inline",
    outs = ["inline.txt"],
    cmd = "echo 'hello from genrule' > $@",
)

genrule(
    name = "spilled",
    outs = ["spilled.txt"],
    # Exceeds the maximum command length on all platforms, which makes genrule
    # write the command to a script.
    cmd = "echo 'hello from genrule' > $@ #" + "x" * 70000,
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
