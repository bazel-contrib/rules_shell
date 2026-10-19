load("//shell:sh_binary.bzl", "sh_binary")
load("//shell:sh_library.bzl", "sh_library")
load("//shell:sh_test.bzl", "sh_test")
load(":sh_test_tests.bzl", "sh_test_test_suite")

sh_test_test_suite(name = "sh_test_tests")

sh_test(
    name = "args_and_env_test",
    srcs = ["args_and_env_test.sh"],
    args = [
        "'expected value'",
        "$(rlocationpath data.txt)",
    ],
    data = ["data.txt"],
    env = {
        "FIXED": "fixed value",
        "LOCATION": "$(location data.txt)",
        "RLOCATIONPATH": "$(rlocationpath data.txt)",
    },
    deps = ["//shell/runfiles"],
)

sh_binary(
    name = "fake_lcov_merger",
    srcs = ["pass.sh"],
)

sh_library(
    name = "lib",
    srcs = ["lib.sh"],
)
