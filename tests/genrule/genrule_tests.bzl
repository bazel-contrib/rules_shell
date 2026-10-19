"""Analysis tests for the `genrule` rule."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//shell:genrule.bzl", "genrule")
load(
    ":fixtures.bzl",
    "GenruleInputsInfo",
    "exec_genrule_inputs",
    "executable_dependency",
    "template_variables",
)

_LINUX_EXEC = {
    "//command_line_option:extra_execution_platforms": [
        "//tests/genrule:linux_exec",
    ],
}

_WINDOWS_EXEC = {
    "//command_line_option:extra_execution_platforms": [
        "//tests/genrule:windows_exec",
    ],
}

_DBG = {
    "//command_line_option:compilation_mode": "dbg",
}

# Ensures that selects on :dbg resolve to their default condition.
_FASTBUILD = {
    "//command_line_option:compilation_mode": "fastbuild",
}

# The setup that genrule prepends to Powershell commands.
_POWERSHELL_SETUP = (
    "Set-ExecutionPolicy -Scope CurrentUser RemoteSigned; " +
    "$errorActionPreference='Stop'; " +
    "$PSDefaultParameterValues['*:Encoding'] = 'utf8'; "
)

# Pads a command with a trailing comment so that it exceeds the maximum command
# length on all platforms and is written to a script.
_LONG_COMMAND_PADDING = " #" + "x" * 70000

def _command(action):
    """Returns the command of a genrule action without the genrule setup."""
    command = action.actual.argv[-1]
    _, setup, user_command = command.partition("/genrule-setup.sh; ")
    return user_command if setup else command

def _output(target):
    return target[DefaultInfo].files.to_list()[0]

def _input(action, basename):
    return [f for f in action.actual.inputs.to_list() if f.basename == basename][0]

def _rule_dir(target):
    return _output(target).root.path + "/" + target.label.package

def _test_name(target):
    return target.label.name.removesuffix("_subject")

def _test_toolchain_overrides_javabase(name):
    util.helper_target(
        template_variables,
        name = name + "_variables",
        variables = {"JAVABASE": "REPLACED"},
    )
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "JAVABASE=$(JAVABASE)",
        toolchains = [name + "_variables"],
    )
    analysis_test(
        name = name,
        impl = _test_toolchain_overrides_javabase_impl,
        target = name + "_subject",
    )

def _test_toolchain_overrides_javabase_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("JAVABASE=REPLACED")

def _test_output_in_subdirectory(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + "/x/y"],
        cmd = "echo hi > $(@D)/y",
    )
    analysis_test(
        name = name,
        impl = _test_output_in_subdirectory_impl,
        target = name + "_subject",
    )

def _test_output_in_subdirectory_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_exactly([
        "{package}/%s/x/y" % _test_name(target),
    ])
    action = env.expect.that_target(target).action_named("Genrule")
    out = _output(target)
    env.expect.that_str(_command(action)).equals("echo hi > %s/y" % out.dirname)

def _test_outputs_in_subdirectories(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [
            name + "/a/b",
            name + "/c/d",
        ],
        cmd = "echo hi | tee $(@D)/{name}/a/b $(@D)/{name}/c/d".format(name = name),
    )
    analysis_test(
        name = name,
        impl = _test_outputs_in_subdirectories_impl,
        target = name + "_subject",
    )

def _test_outputs_in_subdirectories_impl(env, target):
    test_name = _test_name(target)
    env.expect.that_collection(
        [f.short_path for f in target[DefaultInfo].files.to_list()],
    ).contains_exactly([
        "%s/%s/a/b" % (target.label.package, test_name),
        "%s/%s/c/d" % (target.label.package, test_name),
    ]).in_order()

    # With multiple outputs, $(@D) is the package directory.
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals(
        "echo hi | tee {rule_dir}/{name}/a/b {rule_dir}/{name}/c/d".format(
            rule_dir = _rule_dir(target),
            name = test_name,
        ),
    )

def _test_output_named_like_rule(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [
            name + ".txt",
            name + "_subject",
        ],
        cmd = "touch $(OUTS)",
    )
    analysis_test(
        name = name,
        impl = _test_output_named_like_rule_impl,
        target = name + "_subject",
    )

def _test_output_named_like_rule_impl(env, target):
    # Bazel only warns about the output having the same name as the rule.
    env.expect.that_target(target).default_outputs().contains_exactly([
        "{package}/%s.txt" % _test_name(target),
        "{package}/{name}",
    ])

def _test_files_to_build_are_outs(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [name + ".txt"],
        cmd = "echo \"Hello, world.\" >$(location %s.txt)" % name,
    )
    analysis_test(
        name = name,
        impl = _test_files_to_build_are_outs_impl,
        target = name + "_subject",
    )

def _test_files_to_build_are_outs_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_exactly([
        "{package}/%s.txt" % _test_name(target),
    ])

def _test_action_is_shell_command(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [name + ".txt"],
        cmd = "echo \"Hello, world.\" >$(location %s.txt)" % name,
    )
    analysis_test(
        name = name,
        impl = _test_action_is_shell_command_impl,
        target = name + "_subject",
    )

def _test_action_is_shell_command_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_collection(
        [f.basename for f in action.actual.inputs.to_list()],
    ).contains_exactly([
        "src.txt",
        "genrule-setup.sh",
    ])
    env.expect.that_collection(action.actual.outputs.to_list()).contains_exactly([
        _output(target),
    ])
    action.argv().has_size(3)
    env.expect.that_str(action.actual.argv[0]).contains("bash")
    env.expect.that_str(action.actual.argv[1]).equals("-c")
    env.expect.that_str(_command(action)).equals(
        "echo \"Hello, world.\" >" + _output(target).path,
    )

def _test_dependent_genrule(name):
    util.helper_target(
        genrule,
        name = name + "_hello",
        srcs = ["src.txt"],
        outs = [name + "_message.txt"],
        cmd = "echo \"Hello, world.\" >$(location %s_message.txt)" % name,
    )
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = [
            "src2.txt",
            name + "_hello",
        ],
        outs = [name + "_farewell.txt"],
        cmd = "echo $(SRCS) >$(location %s_farewell.txt)" % name,
    )
    analysis_test(
        name = name,
        impl = _test_dependent_genrule_impl,
        target = name + "_subject",
    )

def _test_dependent_genrule_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    message = _test_name(target) + "_message.txt"
    env.expect.that_collection(
        [f.basename for f in action.actual.inputs.to_list()],
    ).contains_exactly([
        "src2.txt",
        message,
        "genrule-setup.sh",
    ])
    env.expect.that_collection(action.actual.outputs.to_list()).contains_exactly([
        _output(target),
    ])
    env.expect.that_str(_command(action)).equals("echo %s %s >%s" % (
        _input(action, "src2.txt").path,
        _input(action, message).path,
        _output(target).path,
    ))

def _test_dependencies_via_files(name):
    util.helper_target(
        genrule,
        name = name + "_bar",
        srcs = ["src.txt"],
        outs = [name + "_bar_out.txt"],
        cmd = "touch $(OUTS)",
    )
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = [name + "_bar_out.txt"],
        outs = [name + "_baz_out.txt"],
        cmd = "touch $(OUTS)",
    )
    analysis_test(
        name = name,
        impl = _test_dependencies_via_files_impl,
        target = name + "_subject",
    )

def _test_dependencies_via_files_impl(env, target):
    # The output of another genrule in `srcs` is generated by that genrule.
    action = env.expect.that_target(target).action_named("Genrule")
    test_name = _test_name(target)
    bar_out = _input(action, test_name + "_bar_out.txt")
    env.expect.that_str(str(bar_out.owner)).equals(
        str(target.label.same_package_label(test_name + "_bar")),
    )

def _test_output_dir_of_single_output(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [name + "/bar/bar_out.txt"],
        cmd = "touch $(@D)",
    )
    analysis_test(
        name = name,
        impl = _test_output_dir_of_single_output_impl,
        target = name + "_subject",
    )

def _test_output_dir_of_single_output_impl(env, target):
    # With a single output, $(@D) is the directory of that output.
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("touch " + _output(target).dirname)

def _test_output_dir_of_multiple_outputs(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [
            name + "/logs/baz_out.txt",
            name + "/logs/baz.log",
        ],
        cmd = "touch $(@D)",
    )
    analysis_test(
        name = name,
        impl = _test_output_dir_of_multiple_outputs_impl,
        target = name + "_subject",
    )

def _test_output_dir_of_multiple_outputs_impl(env, target):
    # With multiple outputs, $(@D) is the package directory, not the common
    # parent directory of the outputs.
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("touch " + _rule_dir(target))
    env.expect.that_str(_command(action)).contains("/tests/genrule")

def _test_rule_dir_of_single_output(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [name + "/bar/bar_out.txt"],
        cmd = "touch $(RULEDIR)",
    )
    analysis_test(
        name = name,
        impl = _test_rule_dir_impl,
        target = name + "_subject",
    )

def _test_rule_dir_of_multiple_outputs(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [
            name + "/baz/baz_out.txt",
            name + "/logs/baz.log",
        ],
        cmd = "touch $(RULEDIR)",
    )
    analysis_test(
        name = name,
        impl = _test_rule_dir_impl,
        target = name + "_subject",
    )

def _test_rule_dir_impl(env, target):
    # $(RULEDIR) is the package directory.
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("touch " + _rule_dir(target))

def _test_binary_targets_expand_to_executable(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [name + ".txt"],
        cmd = "$(location :tool) \"Hello, world.\" >message.txt",
        tools = [":tool"],
    )
    analysis_test(
        name = name,
        impl = _test_binary_targets_expand_to_executable_impl,
        target = name + "_subject",
    )

def _test_binary_targets_expand_to_executable_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")

    # The executable of an sh_binary is a launcher with an .exe extension on
    # Windows, where the script is also among the inputs.
    tools = {
        f.basename: f
        for f in action.actual.inputs.to_list()
        if f.basename in ("tool", "tool.exe")
    }
    tool = tools.get("tool.exe", tools.get("tool"))
    env.expect.that_str(tool.root.path).contains("-exec")
    env.expect.that_str(_command(action)).equals(
        tool.path + " \"Hello, world.\" >message.txt",
    )

def _test_output_to_bindir(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [
            name + "_a.out",
            name + "_b.out",
        ],
        cmd = ":",
        output_to_bindir = True,
    )
    analysis_test(
        name = name,
        impl = _test_output_to_bindir_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:incompatible_merge_genfiles_directory": False,
        },
    )

def _test_output_to_bindir_impl(env, target):
    env.expect.that_collection(
        [f.root.path.split("/")[-1] for f in target[DefaultInfo].files.to_list()],
    ).contains_exactly(["bin", "bin"])

def _test_output_to_genfiles(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [
            name + "_a.out",
            name + "_b.out",
        ],
        cmd = ":",
        output_to_bindir = False,
    )
    analysis_test(
        name = name,
        impl = _test_output_to_genfiles_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:incompatible_merge_genfiles_directory": False,
        },
    )

def _test_output_to_genfiles_impl(env, target):
    env.expect.that_collection(
        [f.root.path.split("/")[-1] for f in target[DefaultInfo].files.to_list()],
    ).contains_exactly(["genfiles", "genfiles"])

def _test_multiple_outs_preserve_order(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [
            name + "/file1.out",
            name + "/file2.out",
        ],
        cmd = "touch $(OUTS)",
    )
    analysis_test(
        name = name,
        impl = _test_multiple_outs_preserve_order_impl,
        target = name + "_subject",
    )

def _test_multiple_outs_preserve_order_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    outs = target[DefaultInfo].files.to_list()
    env.expect.that_collection([f.basename for f in outs]).contains_exactly([
        "file1.out",
        "file2.out",
    ]).in_order()
    env.expect.that_str(_command(action)).equals(
        "touch %s %s" % (outs[0].path, outs[1].path),
    )

def _test_tools_are_exec_configuration(name):
    util.helper_target(
        genrule,
        name = name + "_src",
        outs = [name + "_src.out"],
        cmd = ":",
    )
    util.helper_target(
        genrule,
        name = name + "_tool",
        outs = [name + "_tool.out"],
        cmd = ":",
    )
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = [name + "_src"],
        outs = [name + ".out"],
        cmd = "$(location :%s_tool)" % name,
        tools = [name + "_tool"],
    )
    analysis_test(
        name = name,
        impl = _test_tools_are_exec_configuration_impl,
        target = name + "_subject",
    )

def _test_tools_are_exec_configuration_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    test_name = _test_name(target)

    # srcs are built in the configuration of the genrule...
    src = _input(action, test_name + "_src.out")
    env.expect.that_str(src.root.path).equals(_output(target).root.path)

    # ...tools in the exec configuration...
    tool = _input(action, test_name + "_tool.out")
    env.expect.that_str(tool.root.path).contains("-exec")
    env.expect.that_str(_command(action)).equals(tool.path)

    # ...and the genrule setup is a source file.
    env.expect.that_bool(_input(action, "genrule-setup.sh").is_source).equals(True)

def _test_labels_containing_at_d_are_expanded(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo $(@D)",
        tools = ["tool.sh"],
    )
    analysis_test(
        name = name,
        impl = _test_labels_containing_at_d_are_expanded_impl,
        target = name + "_subject",
    )

def _test_labels_containing_at_d_are_expanded_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("echo " + _rule_dir(target))

def _test_executable(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [name + "_turtle"],
        cmd = "touch $(OUTS)",
        executable = True,
    )
    analysis_test(
        name = name,
        impl = _test_executable_impl,
        target = name + "_subject",
    )

def _test_executable_impl(env, target):
    env.expect.that_target(target).executable().short_path_equals(
        "{package}/%s_turtle" % _test_name(target),
    )

def _test_not_executable_by_default(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [name + "_debugdata.txt"],
        cmd = "touch $(OUTS)",
    )
    analysis_test(
        name = name,
        impl = _test_not_executable_impl,
        target = name + "_subject",
    )

def _test_multiple_outputs_not_executable_by_default(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [
            name + "_turtle",
            name + "_debugdata.txt",
        ],
        cmd = "touch $(OUTS)",
    )
    analysis_test(
        name = name,
        impl = _test_not_executable_impl,
        target = name + "_subject",
    )

def _test_not_executable_impl(env, target):
    env.expect.that_bool(target[DefaultInfo].files_to_run.executable == None).equals(True)

def _test_executable_with_multiple_outputs_rejected(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [
            name + "_out1",
            name + "_out2",
        ],
        cmd = "touch $(OUTS)",
        executable = True,
    )
    analysis_test(
        name = name,
        impl = _test_executable_with_multiple_outputs_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_executable_with_multiple_outputs_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches(
            "*if genrules produce executables, they are allowed only one output. " +
            "If you need the executable=1 argument, then you should split this " +
            "genrule into genrules producing single outputs*",
        ),
    )

def _test_empty_outs_rejected(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [],
        cmd = "echo",
    )
    analysis_test(
        name = name,
        impl = _test_empty_outs_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_empty_outs_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*Genrules without outputs don't make sense*"),
    )

def _test_genrule_setup(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + "_out.sh"],
        cmd = "touch $@",
    )
    analysis_test(
        name = name,
        impl = _test_genrule_setup_impl,
        target = name + "_subject",
    )

def _test_genrule_setup_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    setup = _input(action, "genrule-setup.sh")
    env.expect.that_str(action.actual.argv[-1]).equals(
        "source %s; touch %s" % (setup.path, _output(target).path),
    )

_STAMP_VALUES = {
    "always": 1,
    "auto": -1,
    "default": None,
    "never": 0,
}

def _stamping_test(name, *, stamp, exec_configuration, stamped):
    targets = {}
    for variant, value in _STAMP_VALUES.items():
        subject = "%s_%s_subject" % (name, variant)
        util.helper_target(
            genrule,
            name = subject,
            outs = ["%s_%s.out" % (name, variant)],
            cmd = "",
            stamp = value,
        )
        if exec_configuration:
            util.helper_target(
                exec_genrule_inputs,
                name = subject + "_exec",
                genrule = subject,
            )
            subject += "_exec"
        targets[variant] = subject
    analysis_test(
        name = name,
        impl = _stamping_test_impl,
        targets = targets,
        attrs = {
            "stamped": attr.string_list(),
        },
        attr_values = {
            "stamped": stamped,
        },
        config_settings = {
            "//command_line_option:stamp": stamp,
        },
    )

def _stamping_test_impl(env, targets):
    for variant in _STAMP_VALUES:
        target = getattr(targets, variant)
        if GenruleInputsInfo in target:
            inputs = target[GenruleInputsInfo].inputs
        else:
            inputs = env.expect.that_target(target).action_named("Genrule").actual.inputs
        basenames = [f.basename for f in inputs.to_list()]
        for status_file in ["stable-status.txt", "volatile-status.txt"]:
            env.expect.where(variant = variant).that_bool(
                status_file in basenames,
                expr = status_file + " in inputs",
            ).equals(variant in env.ctx.attr.stamped)

def _test_stamping_with_nostamp(name):
    _stamping_test(name, stamp = False, exec_configuration = False, stamped = ["always"])

def _test_stamping_with_nostamp_in_exec_configuration(name):
    _stamping_test(name, stamp = False, exec_configuration = True, stamped = ["always"])

def _test_stamping_with_stamp(name):
    _stamping_test(name, stamp = True, exec_configuration = False, stamped = ["always", "auto"])

def _test_stamping_with_stamp_in_exec_configuration(name):
    # Unlike for binaries, stamp = 1 stamps genrules in the exec configuration.
    _stamping_test(name, stamp = True, exec_configuration = True, stamped = ["always"])

def _test_requires_darwin(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "",
        tags = ["requires-darwin"],
    )
    analysis_test(
        name = name,
        impl = _test_requires_darwin_impl,
        target = name + "_subject",
    )

def _test_requires_darwin_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")

    # requires-darwin hard-codes /bin/bash as the shell.
    env.expect.that_str(action.actual.argv[0]).equals("/bin/bash")

    env.expect.that_dict(action.actual.execution_info).contains_at_least({
        "requires-darwin": "",
    })

def _test_jar_not_defined(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "$(JAR) foo bar",
    )
    analysis_test(
        name = name,
        impl = _test_jar_not_defined_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_jar_not_defined_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*$(JAR) not defined*"),
    )

def _test_local(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo g",
        local = True,
    )
    analysis_test(
        name = name,
        impl = _test_local_impl,
        target = name + "_subject",
    )

def _test_local_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_dict(action.actual.execution_info).contains_exactly({
        "local": "",
    })

def _test_local_and_local_tag(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo g",
        local = True,
        tags = ["local"],
    )
    analysis_test(
        name = name,
        impl = _test_local_and_local_tag_impl,
        target = name + "_subject",
    )

def _test_local_and_local_tag_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_dict(action.actual.execution_info).contains_exactly({
        "local": "",
    })

def _test_tags_propagated(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo hello > $@",
        tags = [
            "local",
            "no-cache",
            "no-remote",
        ],
    )
    analysis_test(
        name = name,
        impl = _test_tags_propagated_impl,
        target = name + "_subject",
    )

def _test_tags_propagated_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_dict(action.actual.execution_info).contains_exactly({
        "local": "",
        "no-cache": "",
        "no-remote": "",
    })

def _test_modify_execution_info(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo hello > $@",
    )
    analysis_test(
        name = name,
        impl = _test_modify_execution_info_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:modify_execution_info": ["Genrule=+requires-foo"],
        },
    )

def _test_modify_execution_info_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_dict(action.actual.execution_info).contains_exactly({
        "requires-foo": "",
    })

def _test_default_shell_env(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "env > $@",
    )
    analysis_test(
        name = name,
        impl = _test_default_shell_env_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:action_env": ["FROM_ACTION_ENV=action_env_value"],
        },
    )

def _test_default_shell_env_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    action.env().contains_at_least({"FROM_ACTION_ENV": "action_env_value"})

def _test_shell_executable(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo hello > $@",
    )
    analysis_test(
        name = name,
        impl = _test_shell_executable_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:shell_executable": "fake_executable_should_fail",
        },
    )

def _test_shell_executable_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(action.actual.argv[0]).equals("fake_executable_should_fail")

def _test_long_command_uses_script_file(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo Larger than 40 characters > $@" + _LONG_COMMAND_PADDING,
    )
    analysis_test(
        name = name,
        impl = _test_long_command_uses_script_file_impl,
        target = name + "_subject",
    )

def _test_long_command_uses_script_file_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    script = env.expect.that_target(target).action_generating(
        "{package}/{name}.genrule_script.sh",
    )
    script_file = script.actual.outputs.to_list()[0]
    action.argv().has_size(2)
    env.expect.that_str(action.actual.argv[1]).equals(script_file.path)
    action.inputs().contains_predicate(
        matching.file_basename_equals(script_file.basename),
    )
    env.expect.that_str(script.actual.content).equals(
        "#!/bin/bash\nsource %s; echo Larger than 40 characters > %s%s" % (
            _input(action, "genrule-setup.sh").path,
            _output(target).path,
            _LONG_COMMAND_PADDING,
        ),
    )

def _test_long_expanded_command_uses_script_file(name):
    util.helper_target(
        template_variables,
        name = name + "_padding",
        variables = {"PADDING": _LONG_COMMAND_PADDING},
    )
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = native.glob(["input*.txt"]),
        outs = [name + ".out"],
        cmd = "cat $(SRCS) > $@$(PADDING)",
        toolchains = [name + "_padding"],
    )
    analysis_test(
        name = name,
        impl = _test_long_expanded_command_uses_script_file_impl,
        target = name + "_subject",
    )

def _test_long_expanded_command_uses_script_file_impl(env, target):
    # The command only exceeds the maximum command length after "Make"
    # variable substitution, which happens before it is written to the script.
    action = env.expect.that_target(target).action_named("Genrule")
    script = env.expect.that_target(target).action_generating(
        "{package}/{name}.genrule_script.sh",
    )
    env.expect.that_str(script.actual.content).equals(
        "#!/bin/bash\nsource {setup}; cat {inputs} > {out}{padding}".format(
            setup = _input(action, "genrule-setup.sh").path,
            inputs = " ".join([
                "%s/input%d.txt" % (target.label.package, i)
                for i in range(3)
            ]),
            out = _output(target).path,
            padding = _LONG_COMMAND_PADDING,
        ),
    )

def _test_toolchains_from_toolchain_type(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo foo: $(foo) > $@",
        toolchains = [":template_toolchain_type"],
    )
    analysis_test(
        name = name,
        impl = _test_toolchains_from_toolchain_type_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:extra_toolchains": [
                "//tests/genrule:template_toolchain",
            ],
        },
    )

def _test_toolchains_from_toolchain_type_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals(
        "echo foo: bar > " + _output(target).path,
    )

def _test_toolchains_from_toolchain_type_without_toolchain(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo foo: $(foo) > $@",
        toolchains = [":template_toolchain_type"],
    )
    analysis_test(
        name = name,
        impl = _test_toolchains_from_toolchain_type_without_toolchain_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_toolchains_from_toolchain_type_without_toolchain_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*$(foo) not defined*"),
    )

def _test_toolchain_files_are_inputs(name):
    util.helper_target(
        template_variables,
        name = name + "_variables",
        file = "tool_data.txt",
        file_variable = "DATA_PATH",
    )
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "cat $(DATA_PATH) > $@",
        toolchains = [name + "_variables"],
    )
    analysis_test(
        name = name,
        impl = _test_toolchain_files_are_inputs_impl,
        target = name + "_subject",
    )

def _test_toolchain_files_are_inputs_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    action.inputs().contains_predicate(matching.file_basename_equals("tool_data.txt"))
    env.expect.that_str(_command(action)).equals("cat %s > %s" % (
        _input(action, "tool_data.txt").path,
        _output(target).path,
    ))

def _test_toolchain_files_are_in_target_configuration(name):
    util.helper_target(
        template_variables,
        name = name + "_variables",
        generated_file_variable = "GENERATED_PATH",
    )
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "cat $(GENERATED_PATH) > $@",
        # Writes to the same output directory as the fixture regardless of
        # whether the genfiles directory is merged into the bin directory.
        output_to_bindir = True,
        toolchains = [name + "_variables"],
    )
    analysis_test(
        name = name,
        impl = _test_toolchain_files_are_in_target_configuration_impl,
        target = name + "_subject",
    )

def _test_toolchain_files_are_in_target_configuration_impl(env, target):
    # Unlike tools, targets in toolchains are in the configuration of the
    # genrule.
    action = env.expect.that_target(target).action_named("Genrule")
    generated = _input(action, _test_name(target) + "_variables.txt")
    env.expect.that_str(generated.root.path).equals(_output(target).root.path)
    env.expect.that_str(_command(action)).equals("cat %s > %s" % (
        generated.path,
        _output(target).path,
    ))

def _test_runfiles(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [
            name + "_a.out",
            name + "_b.out",
        ],
        cmd = "touch $(OUTS)",
        tools = [":tool"],
    )
    analysis_test(
        name = name,
        impl = _test_runfiles_impl,
        target = name + "_subject",
    )

def _test_runfiles_impl(env, target):
    # Only the outputs are runfiles, and only as data dependencies.
    test_name = _test_name(target)
    env.expect.that_target(target).runfiles().contains_exactly([])
    env.expect.that_target(target).data_runfiles().contains_exactly([
        "{workspace}/{package}/%s_a.out" % test_name,
        "{workspace}/{package}/%s_b.out" % test_name,
    ])

def _test_external_repo_labels(name):
    analysis_test(
        name = name,
        impl = _test_external_repo_labels_impl,
        target = "@genrule_test_repo//package:abs_dep",
    )

def _test_external_repo_labels_impl(env, target):
    # Labels are resolved relative to the repository of the genrule.
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).contains(
        "/%s/package/in" % target.label.workspace_root,
    )

def _test_external_repo_output_dir(name):
    analysis_test(
        name = name,
        impl = _test_external_repo_output_dir_impl,
        target = "@genrule_test_repo//package:echo_d",
    )

def _test_external_repo_output_dir_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    out = _output(target)
    env.expect.that_str(out.dirname).equals(
        "%s/%s/package" % (out.root.path, target.label.workspace_root),
    )
    env.expect.that_str(_command(action)).equals("echo %s > %s" % (out.dirname, out.path))

def _test_cmd_bat_preferred_on_windows(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".txt"],
        cmd = "echo \"Hello, default cmd.\" >$(location %s.txt)" % name,
        cmd_bash = "echo \"Hello, Bash cmd.\" >$(location %s.txt)" % name,
        cmd_bat = "echo \"Hello, Batch cmd.\" >$(location %s.txt)" % name,
        exec_compatible_with = ["@platforms//os:windows"],
    )
    analysis_test(
        name = name,
        impl = _test_cmd_bat_preferred_on_windows_impl,
        target = name + "_subject",
        config_settings = _WINDOWS_EXEC,
    )

def _test_cmd_bat_preferred_on_windows_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    action.argv().contains_exactly([
        "cmd.exe",
        "/S",
        "/E:ON",
        "/V:ON",
        "/D",
        "/c",
        "echo \"Hello, Batch cmd.\" >" + _output(target).path.replace("/", "\\"),
    ]).in_order()

def _test_cmd_ps_preferred_on_windows(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".txt"],
        cmd = "echo \"Hello, default cmd.\" >$(location %s.txt)" % name,
        cmd_bash = "echo \"Hello, Bash cmd.\" >$(location %s.txt)" % name,
        cmd_bat = "echo \"Hello, Batch cmd.\" >$(location %s.txt)" % name,
        cmd_ps = "echo \"Hello, Powershell cmd.\" >$(location %s.txt)" % name,
        exec_compatible_with = ["@platforms//os:windows"],
    )
    analysis_test(
        name = name,
        impl = _test_cmd_ps_preferred_on_windows_impl,
        target = name + "_subject",
        config_settings = _WINDOWS_EXEC,
    )

def _test_cmd_ps_preferred_on_windows_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    action.argv().has_size(3)
    env.expect.that_str(action.actual.argv[0]).equals("powershell.exe")
    env.expect.that_str(action.actual.argv[1]).equals("/c")

    # Unlike for cmd_bat, paths are not converted to Windows paths.
    env.expect.that_str(action.actual.argv[2]).equals(
        _POWERSHELL_SETUP + "echo \"Hello, Powershell cmd.\" >" + _output(target).path,
    )

def _test_cmd_bat_uses_script_file(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".txt"],
        cmd_bat = " && ".join([
            "echo \"Hello, Batch cmd, %s.\" >$(location %s.txt)" % (i, name)
            for i in range(1, 1000)
        ]),
        exec_compatible_with = ["@platforms//os:windows"],
    )
    analysis_test(
        name = name,
        impl = _test_cmd_bat_uses_script_file_impl,
        target = name + "_subject",
        config_settings = _WINDOWS_EXEC,
    )

def _test_cmd_bat_uses_script_file_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    script = env.expect.that_target(target).action_generating(
        "{package}/{name}.genrule_script.bat",
    )
    script_file = script.actual.outputs.to_list()[0]
    env.expect.that_str(action.actual.argv[0]).equals("cmd.exe")
    env.expect.that_str(action.actual.argv[-2]).equals("/c")
    env.expect.that_str(action.actual.argv[-1]).equals(script_file.path.replace("/", "\\"))
    env.expect.that_str(script.actual.content).contains(
        "@echo off\necho \"Hello, Batch cmd, 1.\" >",
    )

def _test_cmd_ps_uses_script_file(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".txt"],
        cmd_ps = "; ".join([
            "echo \"Hello, Powershell cmd, %s.\" >$(location %s.txt)" % (i, name)
            for i in range(1, 1000)
        ]),
        exec_compatible_with = ["@platforms//os:windows"],
    )
    analysis_test(
        name = name,
        impl = _test_cmd_ps_uses_script_file_impl,
        target = name + "_subject",
        config_settings = _WINDOWS_EXEC,
    )

def _test_cmd_ps_uses_script_file_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    script = env.expect.that_target(target).action_generating(
        "{package}/{name}.genrule_script.ps1",
    )
    script_file = script.actual.outputs.to_list()[0]
    env.expect.that_str(action.actual.argv[0]).equals("powershell.exe")
    env.expect.that_str(action.actual.argv[1]).equals("/c")
    env.expect.that_str(action.actual.argv[2]).equals(
        _POWERSHELL_SETUP + ".\\" + script_file.path.replace("/", "\\"),
    )
    env.expect.that_str(script.actual.content).contains(
        "echo \"Hello, Powershell cmd, 1.\" >",
    )

def _test_cmd_bat_quotes_paths_with_spaces(name):
    native.filegroup(
        name = name + "_fg",
        srcs = ["hello source.txt"],
        tags = ["manual"],
    )
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = [name + "_fg"],
        outs = [name + ".txt"],
        cmd_bat = "$(location %s_fg) # $<" % name,
        exec_compatible_with = ["@platforms//os:windows"],
    )
    analysis_test(
        name = name,
        impl = _test_cmd_bat_quotes_paths_with_spaces_impl,
        target = name + "_subject",
        config_settings = _WINDOWS_EXEC,
    )

def _test_cmd_bat_quotes_paths_with_spaces_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")

    # UNDESIRED: Paths with spaces are quoted with single quotes, which cmd.exe
    # doesn't recognize.
    path = target.label.package.replace("/", "\\") + "\\hello source.txt"
    env.expect.that_str(action.actual.argv[-1]).equals("'%s' # %s" % (path, path))

def _test_cmd_bash_preferred_on_windows(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".txt"],
        cmd = "echo \"Hello, default cmd.\" >$(location %s.txt)" % name,
        cmd_bash = "echo \"Hello, Bash cmd.\" >$(location %s.txt)" % name,
        exec_compatible_with = ["@platforms//os:windows"],
    )
    analysis_test(
        name = name,
        impl = _test_cmd_bash_preferred_on_windows_impl,
        target = name + "_subject",
        config_settings = _WINDOWS_EXEC,
    )

def _test_cmd_bash_preferred_on_windows_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    action.argv().has_size(3)
    env.expect.that_str(action.actual.argv[0].lower()).contains("bash.exe")
    env.expect.that_str(action.actual.argv[1]).equals("-c")
    env.expect.that_str(_command(action)).equals(
        "echo \"Hello, Bash cmd.\" >" + _output(target).path,
    )

def _test_cmd_bash_preferred_on_linux(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".txt"],
        cmd = "echo \"Hello, default cmd.\" >$(location %s.txt)" % name,
        cmd_bash = "echo \"Hello, Bash cmd.\" >$(location %s.txt)" % name,
        cmd_bat = "echo \"Hello, Batch cmd.\" >$(location %s.txt)" % name,
        cmd_ps = "echo \"Hello, Powershell cmd.\" >$(location %s.txt)" % name,
        exec_compatible_with = ["@platforms//os:linux"],
    )
    analysis_test(
        name = name,
        impl = _test_cmd_bash_preferred_on_linux_impl,
        target = name + "_subject",
        config_settings = _LINUX_EXEC,
    )

def _test_cmd_bash_preferred_on_linux_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(action.actual.argv[1]).equals("-c")
    env.expect.that_str(_command(action)).equals(
        "echo \"Hello, Bash cmd.\" >" + _output(target).path,
    )

def _test_missing_cmd_rejected(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        exec_compatible_with = ["@platforms//os:windows"],
    )
    analysis_test(
        name = name,
        impl = _missing_cmd_rejected_impl,
        target = name + "_subject",
        config_settings = _WINDOWS_EXEC,
        expect_failure = True,
    )

def _test_cmd_bat_rejected_on_linux(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd_bat = "echo hello > $@",
        exec_compatible_with = ["@platforms//os:linux"],
    )
    analysis_test(
        name = name,
        impl = _missing_cmd_rejected_impl,
        target = name + "_subject",
        config_settings = _LINUX_EXEC,
        expect_failure = True,
    )

def _missing_cmd_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches(
            "*missing value for `cmd` attribute, you can also set `cmd_ps` or " +
            "`cmd_bat` on Windows and `cmd_bash` on other platforms.*",
        ),
    )

def _test_selected_cmd(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = select({
            ":dbg": "echo dbg > $@",
            "//conditions:default": "echo default > $@",
        }),
    )
    analysis_test(
        name = name,
        impl = _test_selected_cmd_impl,
        target = name + "_subject",
        config_settings = _DBG,
    )

def _test_selected_cmd_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("echo dbg > " + _output(target).path)

def _test_selected_srcs_and_tools(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = select({
            ":dbg": ["src.txt"],
            "//conditions:default": ["src2.txt"],
        }),
        outs = [name + ".out"],
        cmd = "$(location :tool) $< $@",
        tools = select({
            ":dbg": [":tool"],
            "//conditions:default": [],
        }),
    )
    analysis_test(
        name = name,
        impl = _test_selected_srcs_and_tools_impl,
        target = name + "_subject",
        config_settings = _DBG,
    )

def _test_selected_srcs_and_tools_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    inputs = {f.basename: f for f in action.actual.inputs.to_list()}
    env.expect.that_collection(inputs.keys()).contains("src.txt")
    env.expect.that_collection(inputs.keys()).not_contains("src2.txt")
    tool = inputs.get("tool.exe", inputs.get("tool"))
    env.expect.that_str(_command(action)).equals("%s %s/src.txt %s" % (
        tool.path,
        target.label.package,
        _output(target).path,
    ))

def _test_selected_local_and_stamp(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo hello > $@",
        local = select({
            ":dbg": True,
            "//conditions:default": False,
        }),
        stamp = select({
            ":dbg": 1,
            "//conditions:default": 0,
        }),
    )
    analysis_test(
        name = name,
        impl = _test_selected_local_and_stamp_impl,
        target = name + "_subject",
        config_settings = _DBG,
    )

def _test_selected_local_and_stamp_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_dict(action.actual.execution_info).contains_exactly({
        "local": "",
    })
    action.inputs().contains_predicate(matching.file_basename_equals("stable-status.txt"))

def _test_cmd_bash_none_is_unset(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo cmd > $@",
        cmd_bash = None,
    )
    analysis_test(
        name = name,
        impl = _test_cmd_bash_none_is_unset_impl,
        target = name + "_subject",
    )

def _test_cmd_bash_none_is_unset_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("echo cmd > " + _output(target).path)

def _test_cmd_bash_selecting_none_is_unset(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo cmd > $@",
        cmd_bash = select({
            ":dbg": "echo dbg > $@",
            "//conditions:default": None,
        }),
    )
    analysis_test(
        name = name,
        impl = _test_cmd_bash_selecting_none_is_unset_impl,
        target = name + "_subject",
        config_settings = _FASTBUILD,
    )

def _test_cmd_bash_selecting_none_is_unset_impl(env, target):
    # A select() that resolves to None doesn't count as setting cmd_bash.
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("echo cmd > " + _output(target).path)

def _test_cmd_bash_selecting_empty_string_is_set(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo cmd > $@",
        cmd_bash = select({
            ":dbg": "echo dbg > $@",
            "//conditions:default": "",
        }),
    )
    analysis_test(
        name = name,
        impl = _test_empty_cmd_bash_is_set_impl,
        target = name + "_subject",
        config_settings = _FASTBUILD,
    )

def _test_cmd_bash_selecting_none_without_conditions(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo cmd > $@",
        cmd_bash = select({
            "//conditions:default": None,
        }),
    )
    analysis_test(
        name = name,
        impl = _test_cmd_bash_selecting_none_without_conditions_impl,
        target = name + "_subject",
    )

def _test_cmd_bash_selecting_none_without_conditions_impl(env, target):
    # UNDESIRED: Unlike a select() with conditions, a select() with only a
    # default condition counts as setting cmd_bash even if it resolves to None,
    # which results in an empty command.
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("")

def _test_empty_cmd_bash_is_set(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "echo cmd > $@",
        cmd_bash = "",
    )
    analysis_test(
        name = name,
        impl = _test_empty_cmd_bash_is_set_impl,
        target = name + "_subject",
    )

def _test_empty_cmd_bash_is_set_impl(env, target):
    # An empty cmd_bash takes precedence over cmd, which results in an empty
    # command.
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(_command(action)).equals("")

def _test_cmd_ps_selecting_none_is_unset_on_windows(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd_bat = "echo bat > $@",
        cmd_ps = select({
            ":dbg": "echo ps > $@",
            "//conditions:default": None,
        }),
        exec_compatible_with = ["@platforms//os:windows"],
    )
    analysis_test(
        name = name,
        impl = _test_cmd_ps_selecting_none_is_unset_on_windows_impl,
        target = name + "_subject",
        config_settings = _WINDOWS_EXEC | _FASTBUILD,
    )

def _test_cmd_ps_selecting_none_is_unset_on_windows_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    env.expect.that_str(action.actual.argv[0]).equals("cmd.exe")
    env.expect.that_str(action.actual.argv[-1]).equals(
        "echo bat > " + _output(target).path.replace("/", "\\"),
    )

def _test_outputs_inherit_rule_visibility(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["//tests/genrule/visibility:private.txt"],
        outs = [name + ".out"],
        cmd = "cp $< $@",
    )
    analysis_test(
        name = name,
        impl = _test_outputs_inherit_rule_visibility_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_outputs_inherit_rule_visibility_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*target '//tests/genrule/visibility:private.txt' is not visible*"),
    )

def _test_outputs_of_public_rule_are_visible(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["//tests/genrule/visibility:public.txt"],
        outs = [name + ".out"],
        cmd = "cp $< $@",
    )
    analysis_test(
        name = name,
        impl = _test_outputs_of_public_rule_are_visible_impl,
        target = name + "_subject",
    )

def _test_outputs_of_public_rule_are_visible_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    action.inputs().contains_predicate(matching.file_basename_equals("public.txt"))

_EXPANDED_DIRECTORIES = "$(@D) $(RULEDIR) $(BINDIR) $(GENDIR) $(location {name}_a.out)"

def _unmerged_genfiles_test(name, *, output_to_bindir, impl):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + "_a.out"],
        cmd = _EXPANDED_DIRECTORIES.format(name = name),
        output_to_bindir = output_to_bindir,
    )
    analysis_test(
        name = name,
        impl = impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:incompatible_merge_genfiles_directory": False,
        },
    )

def _test_directories_with_unmerged_genfiles(name):
    _unmerged_genfiles_test(
        name,
        output_to_bindir = False,
        impl = _test_directories_with_unmerged_genfiles_impl,
    )

def _test_directories_with_unmerged_genfiles_impl(env, target):
    # Outputs, $(@D) and $(RULEDIR) are in the genfiles directory.
    action = env.expect.that_target(target).action_named("Genrule")
    out = _output(target)
    genfiles = out.root.path
    bin = genfiles.removesuffix("/genfiles") + "/bin"
    env.expect.that_str(genfiles).contains("/genfiles")
    env.expect.that_str(_command(action)).equals(" ".join([
        out.dirname,
        genfiles + "/" + target.label.package,
        bin,
        genfiles,
        out.path,
    ]))

def _test_directories_with_unmerged_genfiles_and_output_to_bindir(name):
    _unmerged_genfiles_test(
        name,
        output_to_bindir = True,
        impl = _test_directories_with_unmerged_genfiles_and_output_to_bindir_impl,
    )

def _test_directories_with_unmerged_genfiles_and_output_to_bindir_impl(env, target):
    # Outputs, $(@D) and $(RULEDIR) are in the bin directory.
    action = env.expect.that_target(target).action_named("Genrule")
    out = _output(target)
    bin = out.root.path
    genfiles = bin.removesuffix("/bin") + "/genfiles"
    env.expect.that_str(bin).contains("/bin")
    env.expect.that_str(_command(action)).equals(" ".join([
        out.dirname,
        bin + "/" + target.label.package,
        bin,
        genfiles,
        out.path,
    ]))

def _test_rule_kind(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = [name + ".out"],
        cmd = "touch $@",
    )
    util.helper_target(
        genrule,
        name = name + "_executable",
        outs = [name + "_executable.out"],
        cmd = "touch $@",
        executable = True,
    )
    analysis_test(
        name = name,
        impl = _test_rule_kind_impl,
        target = name + "_subject",
        attrs = {
            "kinds": attr.string_list(),
        },
        # Tools such as `bazel query 'kind(genrule, ...)'` rely on the kind,
        # also of executable genrules.
        attr_values = {
            "kinds": [
                native.existing_rule(name + "_subject")["kind"],
                native.existing_rule(name + "_executable")["kind"],
            ],
        },
    )

def _test_rule_kind_impl(env, target):  # @unused
    env.expect.that_collection(env.ctx.attr.kinds).contains_exactly([
        "genrule",
        "genrule",
    ])

def _test_executable_dependency(name):
    util.helper_target(
        genrule,
        name = name + "_executable",
        outs = [name + "_out.sh"],
        cmd = "touch $@",
        executable = True,
    )
    util.helper_target(
        executable_dependency,
        name = name + "_subject",
        executable = name + "_executable",
    )
    analysis_test(
        name = name,
        impl = _test_executable_dependency_impl,
        target = name + "_subject",
    )

def _test_executable_dependency_impl(env, target):
    # An executable genrule can be used where an executable is required.
    env.expect.that_target(target).default_outputs().contains_exactly([
        "{package}/%s_out.sh" % _test_name(target),
    ])

def _test_non_executable_dependency_rejected(name):
    util.helper_target(
        genrule,
        name = name + "_genrule",
        outs = [name + "_out.sh"],
        cmd = "touch $@",
    )
    util.helper_target(
        executable_dependency,
        name = name + "_subject",
        executable = name + "_genrule",
    )
    analysis_test(
        name = name,
        impl = _test_non_executable_dependency_rejected_impl,
        target = name + "_subject",
        expect_failure = True,
    )

def _test_non_executable_dependency_rejected_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*_genrule does not refer to a valid executable target*"),
    )

def _test_executable_runfiles(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [name + "_out.sh"],
        cmd = "touch $@",
        executable = True,
        tools = [":tool"],
    )
    analysis_test(
        name = name,
        impl = _test_executable_runfiles_impl,
        target = name + "_subject",
    )

def _test_executable_runfiles_impl(env, target):
    # The executable isn't among its default runfiles, unlike for executable
    # Starlark rules.
    test_name = _test_name(target)
    env.expect.that_target(target).runfiles().contains_exactly([])
    env.expect.that_target(target).data_runfiles().contains_exactly([
        "{workspace}/{package}/%s_out.sh" % test_name,
    ])

def _test_instrumented_files(name):
    util.helper_target(
        genrule,
        name = name + "_subject",
        srcs = ["src.txt"],
        outs = [name + ".out"],
        cmd = "touch $@",
        tools = ["tool.sh"],
    )
    analysis_test(
        name = name,
        impl = _test_instrumented_files_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:collect_code_coverage": True,
            "//command_line_option:instrumentation_filter": "^//tests/genrule[/:]",
        },
    )

def _test_instrumented_files_impl(env, target):
    # Only srcs are instrumented.
    env.expect.that_target(target).provider(
        InstrumentedFilesInfo,
    ).instrumented_files().contains_exactly([
        "{package}/src.txt",
    ])

def genrule_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_toolchain_overrides_javabase,
            _test_output_in_subdirectory,
            _test_outputs_in_subdirectories,
            _test_output_named_like_rule,
            _test_files_to_build_are_outs,
            _test_action_is_shell_command,
            _test_dependent_genrule,
            _test_dependencies_via_files,
            _test_output_dir_of_single_output,
            _test_output_dir_of_multiple_outputs,
            _test_rule_dir_of_single_output,
            _test_rule_dir_of_multiple_outputs,
            _test_binary_targets_expand_to_executable,
            _test_output_to_bindir,
            _test_output_to_genfiles,
            _test_multiple_outs_preserve_order,
            _test_tools_are_exec_configuration,
            _test_labels_containing_at_d_are_expanded,
            _test_executable,
            _test_not_executable_by_default,
            _test_multiple_outputs_not_executable_by_default,
            _test_executable_with_multiple_outputs_rejected,
            _test_empty_outs_rejected,
            _test_genrule_setup,
            _test_stamping_with_nostamp,
            _test_stamping_with_nostamp_in_exec_configuration,
            _test_stamping_with_stamp,
            _test_stamping_with_stamp_in_exec_configuration,
            _test_requires_darwin,
            _test_jar_not_defined,
            _test_local,
            _test_local_and_local_tag,
            _test_tags_propagated,
            _test_modify_execution_info,
            _test_default_shell_env,
            _test_shell_executable,
            _test_long_command_uses_script_file,
            _test_long_expanded_command_uses_script_file,
            _test_toolchains_from_toolchain_type,
            _test_toolchains_from_toolchain_type_without_toolchain,
            _test_toolchain_files_are_inputs,
            _test_toolchain_files_are_in_target_configuration,
            _test_runfiles,
            _test_external_repo_labels,
            _test_external_repo_output_dir,
            _test_cmd_bat_preferred_on_windows,
            _test_cmd_ps_preferred_on_windows,
            _test_cmd_bat_uses_script_file,
            _test_cmd_ps_uses_script_file,
            _test_cmd_bat_quotes_paths_with_spaces,
            _test_cmd_bash_preferred_on_windows,
            _test_cmd_bash_preferred_on_linux,
            _test_missing_cmd_rejected,
            _test_cmd_bat_rejected_on_linux,
            _test_selected_cmd,
            _test_selected_srcs_and_tools,
            _test_selected_local_and_stamp,
            _test_cmd_bash_none_is_unset,
            _test_cmd_bash_selecting_none_is_unset,
            _test_cmd_bash_selecting_empty_string_is_set,
            _test_cmd_bash_selecting_none_without_conditions,
            _test_empty_cmd_bash_is_set,
            _test_cmd_ps_selecting_none_is_unset_on_windows,
            _test_outputs_inherit_rule_visibility,
            _test_outputs_of_public_rule_are_visible,
            _test_directories_with_unmerged_genfiles,
            _test_directories_with_unmerged_genfiles_and_output_to_bindir,
            _test_rule_kind,
            _test_executable_dependency,
            _test_non_executable_dependency_rejected,
            _test_executable_runfiles,
            _test_instrumented_files,
        ],
    )
