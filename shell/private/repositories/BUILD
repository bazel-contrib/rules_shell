load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

bzl_library(
    name = "repositories_bzl",
    srcs = ["sh_config.bzl"],
    visibility = ["//shell:__pkg__"],
)

bzl_library(
    name = "bazel_tools_bzl",
    srcs = [
        "@bazel_tools//tools/build_defs/repo:cache.bzl",
        "@bazel_tools//tools/build_defs/repo:http.bzl",
        "@bazel_tools//tools/build_defs/repo:utils.bzl",
    ],
    visibility = ["//shell:__pkg__"],
)
