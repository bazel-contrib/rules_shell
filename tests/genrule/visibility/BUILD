load("//shell:genrule.bzl", "genrule")

genrule(
    name = "private",
    outs = ["private.txt"],
    cmd = "touch $@",
)

genrule(
    name = "public",
    outs = ["public.txt"],
    cmd = "touch $@",
    visibility = ["//visibility:public"],
)
