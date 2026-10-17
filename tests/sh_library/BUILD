load("//shell:sh_library.bzl", "sh_library")
load(":sh_library_tests.bzl", "sh_library_test_suite")

sh_library_test_suite(name = "sh_library_tests")

sh_library(
    name = "dep",
    srcs = ["dep.sh"],
    deps = [":nested_dep"],
)

sh_library(
    name = "nested_dep",
    srcs = ["nested_dep.sh"],
    data = ["nested_data.txt"],
)

sh_library(
    name = "data_lib",
    srcs = ["data_lib.sh"],
)

filegroup(
    name = "not_a_library",
    srcs = ["dep.sh"],
)
