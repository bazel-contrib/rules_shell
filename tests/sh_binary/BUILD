load("//shell:sh_binary.bzl", "sh_binary")
load("//shell:sh_library.bzl", "sh_library")
load("//shell:sh_test.bzl", "sh_test")
load("//shell/toolchains:sh_toolchain.bzl", "sh_toolchain")
load(":sh_binary_tests.bzl", "sh_binary_test_suite")

sh_binary_test_suite(name = "sh_binary_tests")

platform(
    name = "linux",
    constraint_values = ["@platforms//os:linux"],
)

platform(
    name = "windows",
    constraint_values = ["@platforms//os:windows"],
)

platform(
    name = "freebsd",
    constraint_values = ["@platforms//os:freebsd"],
)

sh_library(
    name = "lib",
    srcs = ["lib.sh"],
)

sh_library(
    name = "data_lib",
    srcs = ["data_lib.sh"],
)

filegroup(
    name = "two_scripts",
    srcs = [
        "bin.sh",
        "lib.sh",
    ],
)

sh_toolchain(
    name = "custom_path_sh",
    path = "/custom/bash",
)

toolchain(
    name = "custom_path_linux_toolchain",
    target_compatible_with = ["@platforms//os:linux"],
    toolchain = ":custom_path_sh",
    toolchain_type = "//shell:toolchain_type",
)

sh_toolchain(
    name = "empty_path_sh",
    path = "",
)

toolchain(
    name = "empty_path_windows_toolchain",
    target_compatible_with = ["@platforms//os:windows"],
    toolchain = ":empty_path_sh",
    toolchain_type = "//shell:toolchain_type",
)

# The real launcher can't be analyzed for Windows on other hosts without a C++
# toolchain for Windows.
sh_toolchain(
    name = "fake_launcher_sh",
    launcher = "fake_launcher.exe",
    launcher_maker = "fake_launcher_maker.sh",
    path = "C:/fake/bash.exe",
)

# A Windows toolchain without a launcher maker.
sh_toolchain(
    name = "no_launcher_maker_sh",
    launcher = "fake_launcher.exe",
    path = "C:/fake/bash.exe",
)

toolchain(
    name = "no_launcher_maker_windows_toolchain",
    target_compatible_with = ["@platforms//os:windows"],
    toolchain = ":no_launcher_maker_sh",
    toolchain_type = "//shell:toolchain_type",
)

toolchain(
    name = "fake_launcher_windows_toolchain",
    target_compatible_with = ["@platforms//os:windows"],
    toolchain = ":fake_launcher_sh",
    toolchain_type = "//shell:toolchain_type",
)

# Arguments are passed through to the script unchanged, also through the
# launcher on Windows.
sh_binary(
    name = "echo_args",
    srcs = ["echo_args.sh"],
)

sh_binary(
    name = "echo_args_bash_launcher",
    srcs = ["echo_args.sh"],
    use_bash_launcher = True,
)

sh_test(
    name = "argument_passing_test",
    srcs = ["argument_passing_test.sh"],
    args = [
        "$(rlocationpath :echo_args)",
        "$(rlocationpath :echo_args_bash_launcher)",
    ],
    data = [
        ":echo_args",
        ":echo_args_bash_launcher",
    ],
    deps = ["//shell/runfiles"],
)

# An executable can be wrapped by another rule that forwards its runfiles.
[
    sh_binary(
        name = name,
        srcs = ["hello.sh"],
        data = ["hello_data.txt"],
        use_bash_launcher = use_bash_launcher,
        visibility = ["//tests/sh_binary/wrapped:__pkg__"],
        deps = ["//shell/runfiles"],
    )
    for name, use_bash_launcher in [
        ("hello", False),
        ("hello_bash_launcher", True),
    ]
]

sh_test(
    name = "wrapped_test",
    srcs = ["wrapped_test.sh"],
    args = [
        "$(rlocationpath //tests/sh_binary/wrapped:wrapped_hello)",
        "$(rlocationpath //tests/sh_binary/wrapped:wrapped_hello_bash_launcher)",
    ],
    data = [
        "//tests/sh_binary/wrapped:wrapped_hello",
        "//tests/sh_binary/wrapped:wrapped_hello_bash_launcher",
    ],
    deps = ["//shell/runfiles"],
)
