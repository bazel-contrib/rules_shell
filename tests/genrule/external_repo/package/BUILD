load("@rules_shell//shell:genrule.bzl", "genrule")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//visibility:public"])

genrule(
    name = "abs_dep",
    srcs = ["//package:in"],
    outs = ["abs_dep.out"],
    cmd = "echo '$(locations //package:in)' > $@",
)

sh_binary(
    name = "in",
    srcs = ["in.sh"],
)

genrule(
    name = "hi",
    outs = [
        "a/b",
        "c/d",
    ],
    cmd = "echo 'hi' | tee $(@D)/a/b $(@D)/c/d",
)

genrule(
    name = "echo_d",
    outs = ["d"],
    cmd = "echo $(@D) > $@",
)

genrule(
    name = "hello",
    outs = ["hello.txt"],
    cmd = "echo 'hello' > \"$@\"",
)

genrule(
    name = "hello_tool",
    outs = ["hello_tool.sh"],
    cmd = "printf '#!/bin/sh\\necho hello\\n' > \"$@\"",
    executable = True,
)
