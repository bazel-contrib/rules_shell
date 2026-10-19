"""Analysis tests for sh_binary (and the shared sh_test implementation)."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//shell:sh_binary.bzl", "sh_binary")
load("//shell:sh_binary_info.bzl", "ShBinaryInfo")

_LINUX = {
    "//command_line_option:platforms": [Label(":linux")],
}

_WINDOWS = {
    "//command_line_option:extra_toolchains": [
        str(Label(":fake_launcher_windows_toolchain")),
    ],
    "//command_line_option:platforms": [Label(":windows")],
}

def _test_no_srcs(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = [],
    )
    analysis_test(
        name = name,
        impl = _test_srcs_not_single_file_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_two_srcs(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh", "lib.sh"],
    )
    analysis_test(
        name = name,
        impl = _test_srcs_not_single_file_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_srcs_label_with_two_files(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = [":two_scripts"],
    )
    analysis_test(
        name = name,
        impl = _test_srcs_not_single_file_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_srcs_not_single_file_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*you must specify exactly one file in 'srcs'*"),
    )

def _test_symlink(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
        data = ["data.txt"],
        deps = [":lib"],
    )
    analysis_test(
        name = name,
        impl = _test_symlink_impl,
        target = name + "_subject",
        config_settings = _LINUX,
    )

def _test_symlink_impl(env, target):
    subject = env.expect.that_target(target)

    # Without the bash launcher, the executable is a symlink to the script.
    subject.executable().short_path_equals("{package}/{name}")
    symlink = subject.action_generating("{package}/{name}")
    symlink.mnemonic().equals("ExecutableSymlink")
    symlink.inputs().contains_exactly(["{package}/bin.sh"])
    subject.default_outputs().contains_exactly([
        "{package}/{name}",
        "{package}/bin.sh",
    ])
    subject.runfiles().contains_at_least([
        "{workspace}/{package}/{name}",
        "{workspace}/{package}/bin.sh",
        "{workspace}/{package}/data.txt",
        "{workspace}/{package}/lib.sh",
    ])
    subject.has_provider(ShBinaryInfo)

def _test_bash_launcher(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
        use_bash_launcher = True,
    )
    analysis_test(
        name = name,
        impl = _test_bash_launcher_impl,
        target = name + "_subject",
        config_settings = _LINUX | {
            "//command_line_option:extra_toolchains": [
                str(Label(":custom_path_linux_toolchain")),
            ],
        },
    )

def _test_bash_launcher_impl(env, target):
    subject = env.expect.that_target(target)

    # The bash launcher uses the shell from the toolchain and runs the script
    # via its runfiles path.
    subject.executable().short_path_equals("{package}/{name}")
    content = subject.action_generating("{package}/{name}").content()
    content.split("\n").contains_at_least([
        "#!/custom/bash",
        "runfiles_export_envvars",
        "exec \"$(rlocation \"_main/tests/sh_binary/bin.sh\")\" \"$@\"",
    ]).in_order()
    subject.runfiles().contains_at_least([
        "{workspace}/{package}/{name}",
        "{workspace}/{package}/bin.sh",
        "bazel_tools/tools/bash/runfiles/runfiles.bash",
    ])

def _test_windows_launcher(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
    )
    analysis_test(
        name = name,
        impl = _test_windows_launcher_impl,
        target = name + "_subject",
        config_settings = _WINDOWS,
    )

def _test_windows_launcher_impl(env, target):
    subject = env.expect.that_target(target)

    # On Windows, the executable is a native launcher that runs the script.
    subject.executable().short_path_equals("{package}/{name}.exe")
    subject.default_outputs().contains_exactly([
        "{package}/{name}",
        "{package}/{name}.exe",
        "{package}/bin.sh",
    ])

    # The launcher finds the script at the runfiles path of the symlink.
    action = subject.action_generating("{package}/{name}.exe")
    action.inputs().contains("{package}/fake_launcher.exe")
    action.argv().contains_at_least_predicates([
        matching.str_endswith("fake_launcher_maker.sh"),
        matching.str_endswith("fake_launcher.exe"),
        matching.equals_wrapper("binary_type=Bash"),
        matching.equals_wrapper("workspace_name=_main"),
        matching.str_startswith("symlink_runfiles_enabled="),
        matching.equals_wrapper("bash_bin_path=C:/fake/bash.exe"),
        matching.equals_wrapper("bash_file_rlocationpath=_main/tests/sh_binary/" + target.label.name),
        matching.str_endswith("/{package}/{name}.exe".format(
            package = target.label.package,
            name = target.label.name,
        )),
    ]).in_order()

def _test_windows_bash_launcher(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
        use_bash_launcher = True,
    )
    analysis_test(
        name = name,
        impl = _test_windows_bash_launcher_impl,
        target = name + "_subject",
        config_settings = _WINDOWS,
    )

def _test_windows_bash_launcher_impl(env, target):
    subject = env.expect.that_target(target)

    # The native launcher invokes the shell, so the bash launcher must not
    # have a shebang.
    subject.executable().short_path_equals("{package}/{name}.exe")
    action = subject.action_generating("{package}/{name}")
    action.content().split("\n").contains_at_least([
        "",
        "# --- begin runfiles.bash initialization v3 ---",
    ]).in_order()
    env.expect.that_bool(action.actual.content.startswith("#!")).equals(False)

def _windows_executable_src_test(name, *, extension):
    util.helper_target(
        sh_binary,
        name = name + "_subject." + extension,
        srcs = ["bin." + extension],
    )
    analysis_test(
        name = name,
        impl = lambda env, target: _windows_executable_src_test_impl(env, target, extension = extension),
        target = name + "_subject." + extension,
        config_settings = _WINDOWS,
    )

def _windows_executable_src_test_impl(env, target, *, extension):
    subject = env.expect.that_target(target)

    # A Windows executable is used directly instead of through a launcher.
    subject.executable().short_path_equals("{package}/{name}")
    subject.default_outputs().contains_exactly([
        "{package}/{name}",
        "{package}/bin." + extension,
    ])

def _test_windows_executable_src_bat(name):
    _windows_executable_src_test(name, extension = "bat")

def _test_windows_executable_src_cmd(name):
    _windows_executable_src_test(name, extension = "cmd")

def _test_windows_executable_src_exe(name):
    _windows_executable_src_test(name, extension = "exe")

def _test_windows_executable_src_extension_mismatch(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject.bat",
        srcs = ["bin.cmd"],
    )
    analysis_test(
        name = name,
        impl = _test_windows_executable_src_extension_mismatch_impl,
        target = name + "_subject.bat",
        config_settings = _WINDOWS,
        expect_failure = True,
    )

def _test_windows_executable_src_extension_mismatch_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*target name extension should match source file extension*"),
    )

def _test_windows_no_launcher_maker(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
    )
    analysis_test(
        name = name,
        impl = _test_windows_no_launcher_maker_impl,
        target = name + "_subject",
        config_settings = _WINDOWS | {
            "//command_line_option:extra_toolchains": [
                str(Label(":no_launcher_maker_windows_toolchain")),
            ],
        },
        expect_failure = True,
    )

def _test_windows_no_launcher_maker_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*requires both 'launcher' and 'launcher_maker' to be set*"),
    )

def _test_windows_empty_shell_path(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
    )
    analysis_test(
        name = name,
        impl = _test_windows_empty_shell_path_impl,
        target = name + "_subject",
        config_settings = _WINDOWS | {
            "//command_line_option:extra_toolchains": [
                str(Label(":empty_path_windows_toolchain")),
            ],
        },
        expect_failure = True,
    )

def _test_windows_empty_shell_path_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*No suitable shell toolchain found*"),
    )

def _test_run_environment(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
        data = ["data.txt"],
        env = {
            "LOCATION": "$(location data.txt)",
            "MODE": "$(COMPILATION_MODE)",
            "PLAIN": "plain",
            "RLOCATIONPATH": "$(rlocationpath data.txt)",
        },
        env_inherit = ["INHERITED"],
    )
    analysis_test(
        name = name,
        impl = _test_run_environment_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:compilation_mode": "opt",
        },
    )

def _test_run_environment_impl(env, target):
    info = env.expect.that_target(target).provider(RunEnvironmentInfo)

    # $(location) expands to short paths.
    info.environment().contains_exactly({
        "LOCATION": "tests/sh_binary/data.txt",
        "MODE": "opt",
        "PLAIN": "plain",
        "RLOCATIONPATH": "_main/tests/sh_binary/data.txt",
    })
    info.inherited_environment().contains_exactly(["INHERITED"])

def _test_instrumented_files(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
        data = [
            "data.txt",
            ":data_lib",
        ],
        deps = [":lib"],
    )
    analysis_test(
        name = name,
        impl = _test_instrumented_files_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:collect_code_coverage": True,
            "//command_line_option:instrumentation_filter": "^//tests/sh_binary[/:]",
        },
    )

def _test_instrumented_files_impl(env, target):
    info = env.expect.that_target(target).provider(InstrumentedFilesInfo)

    # The script and the instrumented files of deps and data are instrumented,
    # plain data files are not.
    info.instrumented_files().contains_exactly([
        "{package}/bin.sh",
        "{package}/data_lib.sh",
        "{package}/lib.sh",
    ])

def _test_bash_launcher_default_shell(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
        use_bash_launcher = True,
    )
    analysis_test(
        name = name,
        impl = _test_bash_launcher_default_shell_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:platforms": [Label(":freebsd")],
        },
    )

def _test_bash_launcher_default_shell_impl(env, target):
    # FreeBSD is not the host OS of any CI platform, so the default shell path
    # of the generated toolchain is used.
    content = env.expect.that_target(target).action_generating("{package}/{name}").content()
    content.split("\n").contains_at_least(["#!/usr/local/bin/bash"])

def _test_bash_launcher_external_src(name):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["@bazel_skylib//:LICENSE"],
        use_bash_launcher = True,
    )
    analysis_test(
        name = name,
        impl = _test_bash_launcher_external_src_impl,
        target = name + "_subject",
        config_settings = _LINUX,
    )

def _test_bash_launcher_external_src_impl(env, target):
    # The runfiles path of a script in another repository starts with the
    # canonical name of that repository.
    content = env.expect.that_target(target).action_generating("{package}/{name}").content()
    content.split("\n").contains_at_least([
        "exec \"$(rlocation \"{}/LICENSE\")\" \"$@\"".format(Label("@bazel_skylib//:LICENSE").repo_name),
    ])

def _test_windows_launcher_runfiles_enabled(name):
    _windows_launcher_runfiles_test(name, enable_runfiles = True)

def _test_windows_launcher_runfiles_disabled(name):
    _windows_launcher_runfiles_test(name, enable_runfiles = False)

def _windows_launcher_runfiles_test(name, *, enable_runfiles):
    util.helper_target(
        sh_binary,
        name = name + "_subject",
        srcs = ["bin.sh"],
    )
    analysis_test(
        name = name,
        impl = lambda env, target: _windows_launcher_runfiles_test_impl(env, target, enable_runfiles = enable_runfiles),
        target = name + "_subject",
        config_settings = _WINDOWS | {
            "//command_line_option:enable_runfiles": "yes" if enable_runfiles else "no",
        },
    )

def _windows_launcher_runfiles_test_impl(env, target, *, enable_runfiles):
    # The launcher is told whether it can rely on a runfiles directory.
    action = env.expect.that_target(target).action_generating("{package}/{name}.exe")
    action.argv().contains("symlink_runfiles_enabled=" + ("1" if enable_runfiles else "0"))

def sh_binary_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_no_srcs,
            _test_two_srcs,
            _test_srcs_label_with_two_files,
            _test_symlink,
            _test_bash_launcher,
            _test_bash_launcher_default_shell,
            _test_bash_launcher_external_src,
            _test_windows_launcher,
            _test_windows_launcher_runfiles_enabled,
            _test_windows_launcher_runfiles_disabled,
            _test_windows_bash_launcher,
            _test_windows_executable_src_bat,
            _test_windows_executable_src_cmd,
            _test_windows_executable_src_exe,
            _test_windows_executable_src_extension_mismatch,
            _test_windows_empty_shell_path,
            _test_windows_no_launcher_maker,
            _test_run_environment,
            _test_instrumented_files,
        ],
    )
