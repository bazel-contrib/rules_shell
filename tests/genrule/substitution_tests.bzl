"""Analysis tests for the substitutions applied to the command of `genrule`."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//shell:genrule.bzl", "genrule")
load(":fixtures.bzl", "executable_with_multiple_files", "template_variables")

def _substitution_test(name, *, expected, outs = None, config_settings = {}, **kwargs):
    """Tests that the command expands to `expected`.

    `expected` may refer to `{package}`, the output root `{bindir}`, the root
    of inputs built in the exec configuration `{exec_bindir}`, the test `{name}`
    and the runfiles `{workspace}` name.
    """
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = outs if outs != None else [name + ".out"],
        **kwargs
    )
    analysis_test(
        name = name,
        impl = _substitution_test_impl,
        target = name + "_subject",
        config_settings = config_settings,
        attrs = {
            "expected": attr.string(),
        },
        attr_values = {
            "expected": expected,
        },
    )

def _substitution_test_impl(env, target):
    action = env.expect.that_target(target).action_named("Genrule")
    command, setup, user_command = action.actual.argv[-1].partition("/genrule-setup.sh; ")
    if setup:
        command = user_command
    expected = env.ctx.attr.expected
    exec_bindirs = [
        f.root.path
        for f in action.actual.inputs.to_list()
        if "-exec" in f.root.path
    ]
    for key, value in {
        "bindir": target[DefaultInfo].files.to_list()[0].root.path,
        "exec_bindir": exec_bindirs[0] if exec_bindirs else "<no exec inputs>",
        "name": target.label.name.removesuffix("_subject"),
        "package": target.label.package,
        "workspace": env.ctx.workspace_name,
    }.items():
        expected = expected.replace("{%s}" % key, value)
    env.expect.that_str(command).equals(expected)

def _substitution_failure_test(name, *, error, outs = None, **kwargs):
    """Tests that substitutions in the command fail with `error`."""
    util.helper_target(
        genrule,
        name = name + "_subject",
        outs = outs if outs != None else [name + ".out"],
        **kwargs
    )
    analysis_test(
        name = name,
        impl = _substitution_failure_test_impl,
        target = name + "_subject",
        expect_failure = True,
        attrs = {
            "error": attr.string(),
        },
        attr_values = {
            "error": error,
        },
    )

def _substitution_failure_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*" + env.ctx.attr.error + "*"),
    )

def _test_location_without_label(name):
    _substitution_failure_test(
        name,
        cmd = "$(location )",
        error = "invalid label in $(location) expression: invalid target name '': empty target name",
    )

def _test_location_unterminated_with_labels(name):
    _substitution_failure_test(
        name,
        cmd = "$(location foo bar",
        error = "unterminated variable reference",
    )

def _test_location_unterminated(name):
    _substitution_failure_test(
        name,
        cmd = "$(location",
        error = "unterminated variable reference",
    )

def _test_locationz_unterminated(name):
    _substitution_failure_test(
        name,
        cmd = "$(locationz",
        error = "unterminated variable reference",
    )

def _test_locationz(name):
    _substitution_failure_test(
        name,
        cmd = "$(locationz)",
        error = "$(locationz) not defined",
    )

def _test_locationz_with_space(name):
    _substitution_failure_test(
        name,
        cmd = "$(locationz )",
        error = "$(locationz) not defined",
    )

def _test_locationz_with_label(name):
    _substitution_failure_test(
        name,
        cmd = "$(locationz foo )",
        error = "$(locationz) not defined",
    )

def _test_locations_without_label(name):
    _substitution_failure_test(
        name,
        cmd = "$(locations )",
        error = "invalid label in $(locations) expression: invalid target name '': empty target name",
    )

def _test_locations_unterminated_with_labels(name):
    _substitution_failure_test(
        name,
        cmd = "$(locations foo bar",
        error = "unterminated variable reference",
    )

def _test_locations_unterminated(name):
    _substitution_failure_test(
        name,
        cmd = "$(locations",
        error = "unterminated variable reference",
    )

def _test_locationsz_unterminated(name):
    _substitution_failure_test(
        name,
        cmd = "$(locationsz",
        error = "unterminated variable reference",
    )

def _test_locationsz(name):
    _substitution_failure_test(
        name,
        cmd = "$(locationsz)",
        error = "$(locationsz) not defined",
    )

def _test_locationsz_with_space(name):
    _substitution_failure_test(
        name,
        cmd = "$(locationsz )",
        error = "$(locationsz) not defined",
    )

def _test_locationsz_with_label(name):
    _substitution_failure_test(
        name,
        cmd = "$(locationsz foo )",
        error = "$(locationsz) not defined",
    )

def _test_location_of_existing_non_prerequisite(name):
    _substitution_failure_test(
        name,
        cmd = "$(location :src.txt)",
        error = "label '//tests/genrule:src.txt' in $(location) expression is " +
                "not a declared prerequisite of this rule",
    )

def _test_location_of_missing_non_prerequisite(name):
    _substitution_failure_test(
        name,
        cmd = "$(location :doesnt_exist)",
        error = "label '//tests/genrule:doesnt_exist' in $(location) expression is " +
                "not a declared prerequisite of this rule",
    )

def _test_locations_of_existing_non_prerequisite(name):
    _substitution_failure_test(
        name,
        cmd = "$(locations :src.txt)",
        error = "label '//tests/genrule:src.txt' in $(locations) expression is " +
                "not a declared prerequisite of this rule",
    )

def _test_locations_of_missing_non_prerequisite(name):
    _substitution_failure_test(
        name,
        cmd = "$(locations :doesnt_exist)",
        error = "label '//tests/genrule:doesnt_exist' in $(locations) expression is " +
                "not a declared prerequisite of this rule",
    )

def _multiple_files_failure_test(name, *, function):
    util.helper_target(
        genrule,
        name = name + "_deuce",
        outs = [
            name + "_out.1",
            name + "_out.2",
        ],
        cmd = ":",
    )
    _substitution_failure_test(
        name,
        cmd = "$(%s :%s_deuce)" % (function, name),
        tools = [name + "_deuce"],
        # UNDESIRED: Before Bazel 10, the error refers to $(location) and
        # $(locations) for all functions
        # (https://github.com/bazelbuild/bazel/commit/2bf3e59d7a0).
        error = (
            "label '//tests/genrule:{name}_deuce' in $(*) expression expands to " +
            "more than one file, please use $(*s //tests/genrule:{name}_deuce) instead"
        ).format(name = name),
    )

def _test_location_of_multiple_files(name):
    _multiple_files_failure_test(name, function = "location")

def _test_execpath_of_multiple_files(name):
    _multiple_files_failure_test(name, function = "execpath")

def _test_rootpath_of_multiple_files(name):
    _multiple_files_failure_test(name, function = "rootpath")

def _test_rlocationpath_of_multiple_files(name):
    _multiple_files_failure_test(name, function = "rlocationpath")

def _test_unknown_variable(name):
    _substitution_failure_test(
        name,
        cmd = "$(UNKNOWN)",
        error = "$(UNKNOWN) not defined",
    )

def _test_location_of_source_label(name):
    _substitution_test(
        name,
        srcs = ["src.txt"],
        cmd = "$(location //tests/genrule:src.txt)",
        expected = "{package}/src.txt",
    )

def _test_location_of_relative_source_label(name):
    _substitution_test(
        name,
        srcs = ["src.txt"],
        cmd = "$(location src.txt)",
        expected = "{package}/src.txt",
    )

def _test_location_of_package_relative_source_label(name):
    _substitution_test(
        name,
        srcs = ["src.txt"],
        cmd = "$(location :src.txt)",
        expected = "{package}/src.txt",
    )

def _test_location_of_output_label(name):
    _substitution_test(
        name,
        cmd = "$(location //tests/genrule:%s.out)" % name,
        expected = "{bindir}/{package}/{name}.out",
    )

def _test_location_of_relative_output_label(name):
    _substitution_test(
        name,
        cmd = "$(location %s.out)" % name,
        expected = "{bindir}/{package}/{name}.out",
    )

def _test_locations_of_source_label(name):
    _substitution_test(
        name,
        srcs = ["src.txt"],
        cmd = "$(locations //tests/genrule:src.txt)",
        expected = "{package}/src.txt",
    )

def _test_locations_of_relative_source_label(name):
    _substitution_test(
        name,
        srcs = ["src.txt"],
        cmd = "$(locations src.txt)",
        expected = "{package}/src.txt",
    )

def _test_locations_of_output_label(name):
    _substitution_test(
        name,
        cmd = "$(locations //tests/genrule:%s.out)" % name,
        expected = "{bindir}/{package}/{name}.out",
    )

def _test_locations_of_relative_output_label(name):
    _substitution_test(
        name,
        cmd = "$(locations %s.out)" % name,
        expected = "{bindir}/{package}/{name}.out",
    )

def _test_locations_of_multiple_files(name):
    util.helper_target(
        genrule,
        name = name + "_x",
        srcs = ["src.txt"],
        outs = [
            name + "_out1",
            name + "_out2",
        ],
        cmd = ":",
    )
    _substitution_test(
        name,
        srcs = [name + "_x"],
        cmd = "$(locations %s_x)" % name,
        expected = "{bindir}/{package}/{name}_out1 {bindir}/{package}/{name}_out2",
    )

def _test_location_locations_and_label(name):
    util.helper_target(
        genrule,
        name = name + "_x",
        srcs = ["src.txt"],
        outs = [name + "_x.out"],
        cmd = ":",
    )
    util.helper_target(
        genrule,
        name = name + "_y",
        srcs = ["src.txt"],
        outs = [
            name + "_y.out1",
            name + "_y.out2",
        ],
        cmd = ":",
    )
    _substitution_test(
        name,
        srcs = [
            name + "_x",
            name + "_y",
            "src2.txt",
        ],
        cmd = " _ $(location {name}_x) _ $(locations {name}_y) _ ".format(name = name),
        expected = " _ {bindir}/{package}/{name}_x.out _ " +
                   "{bindir}/{package}/{name}_y.out1 {bindir}/{package}/{name}_y.out2 _ ",
    )

def _test_location_with_surrounding_spaces(name):
    _substitution_test(
        name,
        srcs = ["src.txt"],
        cmd = "echo $(location  :src.txt ) > \"$@\"",
        expected = "echo {package}/src.txt > \"{bindir}/{package}/{name}.out\"",
    )

def _test_execpath_rootpath_and_rlocationpath(name):
    _substitution_test(
        name,
        cmd = "$(execpath {name}.out) $(rootpath {name}.out) $(rlocationpath {name}.out)".format(
            name = name,
        ),
        expected = "{bindir}/{package}/{name}.out {package}/{name}.out {workspace}/{package}/{name}.out",
    )

def _test_execpaths_rootpaths_and_rlocationpaths(name):
    _substitution_test(
        name,
        outs = [
            name + "_a.out",
            name + "_b.out",
        ],
        cmd = "$(execpaths {name}_a.out) $(rootpaths {name}_b.out) $(rlocationpaths {name}_a.out)".format(
            name = name,
        ),
        expected = "{bindir}/{package}/{name}_a.out {package}/{name}_b.out {workspace}/{package}/{name}_a.out",
    )

def _test_outs(name):
    _substitution_test(
        name,
        cmd = "$(OUTS) # $@",
        expected = "{bindir}/{package}/{name}.out # {bindir}/{package}/{name}.out",
    )

def _test_srcs(name):
    _substitution_test(
        name,
        srcs = ["src.txt"],
        cmd = "$(SRCS) # $<",
        expected = "{package}/src.txt # {package}/src.txt",
    )

def _test_make_variables(name):
    _substitution_test(
        name,
        cmd = "$(COMPILATION_MODE) $(BINDIR) $(GENDIR)",
        config_settings = {
            "//command_line_option:compilation_mode": "dbg",
            "//command_line_option:incompatible_merge_genfiles_directory": True,
        },
        expected = "dbg {bindir} {bindir}",
    )

def _test_dollar_dollar(name):
    _substitution_test(
        name,
        cmd = "$$DOLLAR",
        expected = "$DOLLAR",
    )

def _test_dollar_less_than_without_srcs(name):
    _substitution_failure_test(
        name,
        cmd = "$<",
        error = "variable '$<' : no input file",
    )

def _test_dollar_less_than_with_multiple_srcs(name):
    _substitution_failure_test(
        name,
        srcs = [
            "src.txt",
            "src2.txt",
        ],
        cmd = "$<",
        error = "variable '$<' : more than one input file",
    )

def _test_dollar_at_with_multiple_outs(name):
    _substitution_failure_test(
        name,
        outs = [
            name + ".1",
            name + ".2",
        ],
        cmd = "$@",
        error = "variable '$@' : more than one output file",
    )

def _test_dollar_at_without_outs(name):
    _substitution_failure_test(
        name,
        srcs = [
            "src.txt",
            "src2.txt",
        ],
        outs = [],
        cmd = "$@",
        error = "Genrules without outputs don't make sense",
    )

def _test_escaped_shell_variable(name):
    _substitution_test(
        name,
        cmd = "for file in a b c;do echo $$file;done",
        expected = "for file in a b c;do echo $file;done",
    )

def _test_escaped_shell_parameter_expansion(name):
    _substitution_test(
        name,
        cmd = "$${file%:.*8}",
        expected = "${file%:.*8}",
    )

def _test_escaped_shell_command_substitution(name):
    _substitution_test(
        name,
        cmd = "$$(basename file)",
        expected = "$(basename file)",
    )

def _test_unescaped_shell_command_substitution(name):
    _substitution_failure_test(
        name,
        cmd = "$(basename file)",
        error = "$(basename) not defined",
    )

def _test_unescaped_shell_variable(name):
    _substitution_failure_test(
        name,
        cmd = "for file in a b c;do echo $file;done",
        error = "'$file' syntax is not supported; use '$(file)' ",
    )

def _test_unescaped_shell_parameter_expansion(name):
    _substitution_failure_test(
        name,
        cmd = "${file%:.*8}",
        error = "'${file%:.*8}' syntax is not supported; use '$(file%:.*8)' ",
    )

def _test_heuristic_label_expansion_of_single_file(name):
    native.filegroup(
        name = name + "_fg",
        srcs = ["src.txt"],
        tags = ["manual"],
    )
    _substitution_test(
        name,
        cmd = "cp :%s_fg $@" % name,
        heuristic_label_expansion = True,
        tools = [name + "_fg"],
        expected = "cp {package}/src.txt {bindir}/{package}/{name}.out",
    )

def _test_heuristic_label_expansion_of_no_files(name):
    native.filegroup(
        name = name + "_fg",
        srcs = [],
        tags = ["manual"],
    )
    _substitution_failure_test(
        name,
        cmd = "cp :%s_fg $@" % name,
        heuristic_label_expansion = True,
        tools = [name + "_fg"],
        error = "expands to 0 files",
    )

def _test_heuristic_label_expansion_of_multiple_files(name):
    native.filegroup(
        name = name + "_fg",
        srcs = [
            "src.txt",
            "src2.txt",
        ],
        tags = ["manual"],
    )
    _substitution_failure_test(
        name,
        cmd = "cp :%s_fg $@" % name,
        heuristic_label_expansion = True,
        tools = [name + "_fg"],
        error = "expands to 2 files",
    )

def _test_srcs_deduplicated(name):
    native.filegroup(
        name = name + "_fg",
        srcs = [
            "src.txt",
            "src2.txt",
        ],
        tags = ["manual"],
    )
    _substitution_test(
        name,
        srcs = [
            name + "_fg",
            "src.txt",
        ],
        cmd = "$(SRCS)",
        expected = "{package}/src.txt {package}/src2.txt",
    )

def _test_dollar_less_than_with_single_file_filegroup(name):
    native.filegroup(
        name = name + "_fg",
        srcs = ["src.txt"],
        tags = ["manual"],
    )
    _substitution_test(
        name,
        srcs = [name + "_fg"],
        cmd = "$< $(location %s_fg)" % name,
        expected = "{package}/src.txt {package}/src.txt",
    )

def _test_empty_filegroup_in_srcs(name):
    native.filegroup(
        name = name + "_fg",
        tags = ["manual"],
    )
    _substitution_test(
        name,
        srcs = [name + "_fg"],
        cmd = "[$(SRCS)]",
        expected = "[]",
    )

def _test_location_of_empty_filegroup_in_srcs(name):
    native.filegroup(
        name = name + "_fg",
        tags = ["manual"],
    )
    _substitution_failure_test(
        name,
        srcs = [name + "_fg"],
        cmd = "$(location %s_fg)" % name,
        error = "label '//tests/genrule:%s_fg' in $(location) expression expands to no files" % name,
    )

def _test_location_of_executable_with_multiple_files_in_tools(name):
    util.helper_target(
        executable_with_multiple_files,
        name = name + "_executable",
    )
    _substitution_test(
        name,
        cmd = "$(location %s_executable)" % name,
        tools = [name + "_executable"],
        expected = "{exec_bindir}/{package}/{name}_executable.sh",
    )

def _test_location_of_executable_with_multiple_files_in_srcs(name):
    util.helper_target(
        executable_with_multiple_files,
        name = name + "_executable",
    )
    _substitution_failure_test(
        name,
        srcs = [name + "_executable"],
        cmd = "$(location %s_executable)" % name,
        error = "label '//tests/genrule:%s_executable' in $(location) expression expands to more than one file" % name,
    )

def _test_location_of_label_in_srcs_and_tools(name):
    util.helper_target(
        genrule,
        name = name + "_both",
        outs = [name + "_both.out"],
        cmd = "touch $@",
    )
    _substitution_test(
        name,
        srcs = [name + "_both"],
        cmd = "$(locations %s_both)" % name,
        tools = [name + "_both"],
        # Expands to the output in both the target and the exec configuration,
        # sorted by path.
        config_settings = {
            "//command_line_option:compilation_mode": "fastbuild",
        },
        expected = "{bindir}/{package}/{name}_both.out {exec_bindir}/{package}/{name}_both.out",
    )

def _test_locations_sorted(name):
    util.helper_target(
        genrule,
        name = name + "_x",
        outs = [
            name + "_b.out",
            name + "_a.out",
        ],
        cmd = "touch $(OUTS)",
    )
    _substitution_test(
        name,
        srcs = [name + "_x"],
        cmd = "$(locations %s_x) # $(SRCS)" % name,
        # Unlike $(SRCS) and $(OUTS), $(locations) sorts paths.
        expected = "{bindir}/{package}/{name}_a.out {bindir}/{package}/{name}_b.out # " +
                   "{bindir}/{package}/{name}_b.out {bindir}/{package}/{name}_a.out",
    )

def _alias_test(name, *, attr, label, error = None):
    util.helper_target(
        genrule,
        name = name + "_actual",
        outs = [name + "_actual.out"],
        cmd = "touch $@",
    )
    native.alias(
        name = name + "_alias",
        actual = name + "_actual",
        tags = ["manual"],
    )
    kwargs = {
        attr: [name + "_alias"],
        "cmd": "$(location :%s_%s)" % (name, label),
    }
    if error:
        _substitution_failure_test(name, error = error % name, **kwargs)
    else:
        _substitution_test(
            name,
            expected = "{%s}/{package}/{name}_actual.out" % ("bindir" if attr == "srcs" else "exec_bindir"),
            **kwargs
        )

def _test_location_of_alias_in_srcs(name):
    _alias_test(name, attr = "srcs", label = "alias")

def _test_location_of_alias_in_tools(name):
    _alias_test(name, attr = "tools", label = "alias")

def _test_location_of_alias_actual_with_alias_in_srcs(name):
    _alias_test(
        name,
        attr = "srcs",
        label = "actual",
        error = "label '//tests/genrule:%s_actual' in $(location) expression is not a declared prerequisite of this rule",
    )

def _test_location_of_alias_actual_with_alias_in_tools(name):
    # Unlike srcs, tools are also available under the label of the actual
    # target of an alias.
    _alias_test(name, attr = "tools", label = "actual")

def _test_location_quotes_paths_with_spaces(name):
    native.filegroup(
        name = name + "_fg",
        srcs = ["hello source.txt"],
        tags = ["manual"],
    )
    _substitution_test(
        name,
        srcs = [name + "_fg"],
        cmd = "$(location {name}_fg) $(execpath {name}_fg) $(rootpath {name}_fg) $(rlocationpath {name}_fg) # $< $(SRCS)".format(
            name = name,
        ),
        # Unlike the location functions, $< and $(SRCS) don't quote paths.
        expected = "'{package}/hello source.txt' '{package}/hello source.txt' " +
                   "'{package}/hello source.txt' '{workspace}/{package}/hello source.txt' # " +
                   "{package}/hello source.txt {package}/hello source.txt",
    )

def _test_location_in_variable(name):
    util.helper_target(
        template_variables,
        name = name + "_variables",
        variables = {
            "ESCAPED": "$$(location :src.txt)",
            "LOCATION": "$(location :src.txt)",
        },
    )
    _substitution_test(
        name,
        srcs = ["src.txt"],
        cmd = "$$(location :src.txt) $(LOCATION) $(ESCAPED)",
        toolchains = [name + "_variables"],
        # Location functions in the values of variables are expanded.
        expected = "$(location :src.txt) {package}/src.txt $(location :src.txt)",
    )

def _conflicting_variables_test(name, *, reversed):
    for value in ["first", "second"]:
        util.helper_target(
            template_variables,
            name = "%s_%s" % (name, value),
            variables = {"VALUE": value},
        )
    toolchains = [name + "_first", name + "_second"]
    _substitution_test(
        name,
        cmd = "$(VALUE)",
        toolchains = toolchains[::-1] if reversed else toolchains,
        # The first target in toolchains that provides a variable wins.
        expected = "second" if reversed else "first",
    )

def _test_conflicting_variables(name):
    _conflicting_variables_test(name, reversed = False)

def _test_conflicting_variables_reversed(name):
    _conflicting_variables_test(name, reversed = True)

def substitution_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_location_without_label,
            _test_location_unterminated_with_labels,
            _test_location_unterminated,
            _test_locationz_unterminated,
            _test_locationz,
            _test_locationz_with_space,
            _test_locationz_with_label,
            _test_locations_without_label,
            _test_locations_unterminated_with_labels,
            _test_locations_unterminated,
            _test_locationsz_unterminated,
            _test_locationsz,
            _test_locationsz_with_space,
            _test_locationsz_with_label,
            _test_location_of_existing_non_prerequisite,
            _test_location_of_missing_non_prerequisite,
            _test_locations_of_existing_non_prerequisite,
            _test_locations_of_missing_non_prerequisite,
            _test_location_of_multiple_files,
            _test_execpath_of_multiple_files,
            _test_rootpath_of_multiple_files,
            _test_rlocationpath_of_multiple_files,
            _test_unknown_variable,
            _test_location_of_source_label,
            _test_location_of_relative_source_label,
            _test_location_of_package_relative_source_label,
            _test_location_of_output_label,
            _test_location_of_relative_output_label,
            _test_locations_of_source_label,
            _test_locations_of_relative_source_label,
            _test_locations_of_output_label,
            _test_locations_of_relative_output_label,
            _test_locations_of_multiple_files,
            _test_location_locations_and_label,
            _test_location_with_surrounding_spaces,
            _test_execpath_rootpath_and_rlocationpath,
            _test_execpaths_rootpaths_and_rlocationpaths,
            _test_outs,
            _test_srcs,
            _test_make_variables,
            _test_dollar_dollar,
            _test_dollar_less_than_without_srcs,
            _test_dollar_less_than_with_multiple_srcs,
            _test_dollar_at_with_multiple_outs,
            _test_dollar_at_without_outs,
            _test_escaped_shell_variable,
            _test_escaped_shell_parameter_expansion,
            _test_escaped_shell_command_substitution,
            _test_unescaped_shell_command_substitution,
            _test_unescaped_shell_variable,
            _test_unescaped_shell_parameter_expansion,
            _test_heuristic_label_expansion_of_single_file,
            _test_heuristic_label_expansion_of_no_files,
            _test_heuristic_label_expansion_of_multiple_files,
            _test_srcs_deduplicated,
            _test_dollar_less_than_with_single_file_filegroup,
            _test_empty_filegroup_in_srcs,
            _test_location_of_empty_filegroup_in_srcs,
            _test_location_of_executable_with_multiple_files_in_tools,
            _test_location_of_executable_with_multiple_files_in_srcs,
            _test_location_of_label_in_srcs_and_tools,
            _test_locations_sorted,
            _test_location_of_alias_in_srcs,
            _test_location_of_alias_in_tools,
            _test_location_of_alias_actual_with_alias_in_srcs,
            _test_location_of_alias_actual_with_alias_in_tools,
            _test_location_quotes_paths_with_spaces,
            _test_location_in_variable,
            _test_conflicting_variables,
            _test_conflicting_variables_reversed,
        ],
    )
