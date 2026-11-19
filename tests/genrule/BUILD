load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("//shell:genrule.bzl", "genrule")
load("//shell:sh_binary.bzl", "sh_binary")
load(
    ":fixtures.bzl",
    "genrule_with_action_env",
    "script_without_default_files",
    "template_toolchain",
    "template_variables",
)
load(":genrule_tests.bzl", "genrule_test_suite")
load(":substitution_tests.bzl", "substitution_test_suite")

genrule_test_suite(name = "genrule_tests")

substitution_test_suite(name = "substitution_tests")

platform(
    name = "linux_exec",
    constraint_values = ["@platforms//os:linux"],
)

platform(
    name = "windows_exec",
    constraint_values = ["@platforms//os:windows"],
)

toolchain_type(name = "template_toolchain_type")

template_toolchain(
    name = "template_toolchain_impl",
    variables = {"foo": "bar"},
)

toolchain(
    name = "template_toolchain",
    toolchain = ":template_toolchain_impl",
    toolchain_type = ":template_toolchain_type",
)

# Pads a command with a trailing comment so that it exceeds the maximum command
# length on all platforms and is written to a script without otherwise changing
# its behavior.
LONG_COMMAND_PADDING = " #" + "x" * 70000

genrule(
    name = "direct_execution",
    outs = ["direct_execution.txt"],
    cmd = "echo Smaller than 40 characters > $@",
)

diff_test(
    name = "direct_execution_test",
    size = "small",
    file1 = ":direct_execution",
    file2 = "direct_execution.golden",
)

genrule(
    name = "simple_indirect_execution",
    outs = ["simple_indirect_execution.txt"],
    cmd = "echo Larger than 40 characters............................ > $@" + LONG_COMMAND_PADDING,
)

diff_test(
    name = "simple_indirect_execution_test",
    size = "small",
    file1 = ":simple_indirect_execution",
    file2 = "simple_indirect_execution.golden",
)

# The command only exceeds the maximum command length after "Make" variable
# substitution, which happens before it is written to a script.
template_variables(
    name = "long_padding",
    variables = {"PADDING": "x" * 70000},
)

genrule(
    name = "complicated_indirect_execution",
    srcs = glob(["input*.txt"]),
    outs = ["complicated_indirect_execution.txt"],
    cmd = "cat $(SRCS) > $@ #$(PADDING)",
    toolchains = [":long_padding"],
)

diff_test(
    name = "complicated_indirect_execution_test",
    size = "small",
    file1 = ":complicated_indirect_execution",
    file2 = "all_inputs.golden",
)

genrule(
    name = "realistic_indirect_execution",
    srcs = glob(["input*.txt"]),
    outs = ["realistic_indirect_execution.txt"],
    cmd = """
> $@
{
cat <<EOF
$(SRCS)
EOF
} |
tr ' ' '\\n' |
while read file; do cat $$file >> $@; done
""" + LONG_COMMAND_PADDING,
)

diff_test(
    name = "realistic_indirect_execution_test",
    size = "small",
    file1 = ":realistic_indirect_execution",
    file2 = "all_inputs.golden",
)

# The genrule setup enables strict mode, also when the command is written to a
# script.
[
    genrule(
        name = "setup_options_" + variant,
        outs = ["setup_options_%s.txt" % variant],
        cmd = "for opt in errexit nounset pipefail; do if [[ -o $$opt ]]; then echo $$opt; fi; done > $@" +
              (LONG_COMMAND_PADDING if variant == "spilled" else ""),
    )
    for variant in [
        "inline",
        "spilled",
    ]
]

[
    diff_test(
        name = "setup_options_%s_test" % variant,
        size = "small",
        file1 = ":setup_options_" + variant,
        file2 = "setup_options.golden",
    )
    for variant in [
        "inline",
        "spilled",
    ]
]

# Non-ASCII characters in commands are preserved, also when the command is
# written to a script.
[
    genrule(
        name = "unicode_" + variant,
        outs = ["unicode_%s.txt" % variant],
        # In Russian and Bengali: "Down with mojibake! We want unicode!"
        cmd = "echo -n \"Долой кракозябры! আমরা ইউনিকোড চাই!\" > \"$@\"" +
              (LONG_COMMAND_PADDING if variant == "spilled" else ""),
    )
    for variant in [
        "inline",
        "spilled",
    ]
]

[
    diff_test(
        name = "unicode_%s_test" % variant,
        size = "small",
        file1 = ":unicode_" + variant,
        file2 = "unicode.golden",
    )
    for variant in [
        "inline",
        "spilled",
    ]
]

genrule(
    name = "output_in_subdirectory",
    outs = ["output_in_subdirectory/x/y"],
    cmd = "echo hi > $(@D)/y",
)

genrule(
    name = "outputs_in_subdirectories",
    outs = [
        "outputs_in_subdirectories/a/b",
        "outputs_in_subdirectories/c/d",
    ],
    cmd = "echo hi | tee $(@D)/outputs_in_subdirectories/a/b $(@D)/outputs_in_subdirectories/c/d",
)

[
    diff_test(
        name = "%s_test" % out.replace("/", "_"),
        size = "small",
        file1 = out,
        file2 = "hi.golden",
    )
    for out in [
        "output_in_subdirectory/x/y",
        "outputs_in_subdirectories/a/b",
        "outputs_in_subdirectories/c/d",
    ]
]

# Executable tools have their runfiles available, also when the command is
# written to a script.
sh_binary(
    name = "tool",
    srcs = ["tool.sh"],
    data = ["tool_data.txt"],
    deps = ["//shell/runfiles"],
)

[
    genrule(
        name = "tool_output_" + variant,
        outs = ["tool_output_%s.txt" % variant],
        cmd = "$(location :tool) $@" + (LONG_COMMAND_PADDING if variant == "spilled" else ""),
        tools = [":tool"],
    )
    for variant in [
        "inline",
        "spilled",
    ]
]

[
    diff_test(
        name = "tool_output_%s_test" % variant,
        size = "small",
        file1 = ":tool_output_" + variant,
        file2 = "tool_data.txt",
    )
    for variant in [
        "inline",
        "spilled",
    ]
]

# An executable that isn't among the default outputs of its target can be used
# as a tool.
script_without_default_files(
    name = "script_without_default_files",
)

genrule(
    name = "script_without_default_files_output",
    outs = ["script_without_default_files_output.txt"],
    cmd = "$(location :script_without_default_files) $@",
    tools = [":script_without_default_files"],
)

diff_test(
    name = "script_without_default_files_output_test",
    size = "small",
    file1 = ":script_without_default_files_output",
    file2 = "hello.txt",
)

# The command runs with the default shell environment, which includes
# --action_env entries.
genrule_with_action_env(
    name = "action_env",
    outs = ["action_env.txt"],
    cmd = "echo \"$$FROM_ACTION_ENV\" > $@",
)

diff_test(
    name = "action_env_test",
    size = "small",
    file1 = ":action_env",
    file2 = "action_env.golden",
)

# A generated executable can be used as a tool.
genrule(
    name = "generated_tool",
    outs = ["generated_tool.sh"],
    cmd = "printf '#!/bin/sh\\necho hello\\n' > $@",
    executable = True,
)

genrule(
    name = "generated_tool_output",
    outs = ["generated_tool_output.txt"],
    cmd = "$(location :generated_tool) > $@",
    tools = [":generated_tool"],
)

diff_test(
    name = "generated_tool_output_test",
    size = "small",
    file1 = ":generated_tool_output",
    file2 = "hello.golden",
)

template_variables(
    name = "template_variables",
    variables = {"foo": "bar"},
)

genrule(
    name = "template_variables_from_target",
    outs = ["template_variables_from_target.txt"],
    cmd = "echo foo: $(foo) > $@",
    toolchains = [":template_variables"],
)

diff_test(
    name = "template_variables_from_target_test",
    size = "small",
    file1 = ":template_variables_from_target",
    file2 = "template_variables.golden",
)

# A toolchain type without a registered toolchain is fine as long as its
# variables are not used.
genrule(
    name = "unused_toolchain_type_without_toolchain",
    outs = ["unused_toolchain_type_without_toolchain.txt"],
    cmd = "echo no template variables used > $@",
    toolchains = [":template_toolchain_type"],
)

diff_test(
    name = "unused_toolchain_type_without_toolchain_test",
    size = "small",
    file1 = ":unused_toolchain_type_without_toolchain",
    file2 = "unused_toolchain_type_without_toolchain.golden",
)

# The files of `toolchains` are available to the command.
template_variables(
    name = "template_variables_with_file",
    file = "tool_data.txt",
    file_variable = "DATA_PATH",
)

genrule(
    name = "toolchain_files",
    outs = ["toolchain_files.txt"],
    cmd = "cat $(DATA_PATH) > $@",
    toolchains = [":template_variables_with_file"],
)

diff_test(
    name = "toolchain_files_test",
    size = "small",
    file1 = ":toolchain_files",
    file2 = "tool_data.txt",
)

# The Bash command is used on all platforms other than Windows, which uses
# the Batch or Powershell command.
genrule(
    name = "copy_with_bash_and_batch",
    srcs = ["hello.txt"],
    outs = ["copy_with_bash_and_batch.txt"],
    cmd_bash = "cp $< $@",
    cmd_bat = "copy $< $@",
)

genrule(
    name = "copy_with_bash_and_powershell",
    srcs = ["hello.txt"],
    outs = ["copy_with_bash_and_powershell.txt"],
    cmd_bash = "cp $< $@",
    cmd_ps = "Copy-Item $< -Destination $@",
)

genrule(
    name = "copy_with_spaces_with_bash_and_batch",
    srcs = ["hello source.txt"],
    outs = ["hello copied with bash and batch.txt"],
    cmd_bash = "cp \"$<\" \"$@\"",
    cmd_bat = "copy \"$<\" \"$@\"",
)

genrule(
    name = "copy_with_spaces_with_bash_and_powershell",
    srcs = ["hello source.txt"],
    outs = ["hello copied with bash and powershell.txt"],
    cmd_bash = "cp \"$<\" \"$@\"",
    cmd_ps = "cp \"$<\" \"$@\"",
)

# Copies the outputs with spaces in their names to files without spaces, which
# diff_test can't handle on all platforms.
[
    genrule(
        name = name + "_without_spaces",
        srcs = [":" + name],
        outs = [name + ".txt"],
        cmd = "cp \"$<\" $@",
    )
    for name in [
        "copy_with_spaces_with_bash_and_batch",
        "copy_with_spaces_with_bash_and_powershell",
    ]
]

[
    diff_test(
        name = name + "_test",
        size = "small",
        file1 = file1,
        file2 = "hello.txt",
    )
    for name, file1 in [
        ("copy_with_bash_and_batch", ":copy_with_bash_and_batch"),
        ("copy_with_bash_and_powershell", ":copy_with_bash_and_powershell"),
        ("copy_with_spaces_with_bash_and_batch", ":copy_with_spaces_with_bash_and_batch_without_spaces"),
        ("copy_with_spaces_with_bash_and_powershell", ":copy_with_spaces_with_bash_and_powershell_without_spaces"),
    ]
]

# Batch and Powershell commands that exceed the maximum command length on
# Windows are written to a script.
genrule(
    name = "batch_script",
    outs = ["batch_script.txt"],
    # cmd.exe would echo a space before "&&".
    cmd_bat = "&& ".join(["echo Hello world>>$(location batch_script.txt)"] * 1000),
    target_compatible_with = ["@platforms//os:windows"],
)

genrule(
    name = "powershell_script",
    outs = ["powershell_script.txt"],
    cmd_ps = "; ".join(["echo \"Hello world\">>$(location powershell_script.txt)"] * 1000),
    target_compatible_with = ["@platforms//os:windows"],
)

# Counts the lines of the output, ignoring carriage returns and UTF-8 byte
# order marks in Batch and Powershell output.
[
    genrule(
        name = name + "_count",
        srcs = [":" + name],
        outs = [name + "_count.txt"],
        cmd = "LC_ALL=C tr -d '\\r\\357\\273\\277' < $< | grep -c '^Hello world$$' > $@",
        target_compatible_with = ["@platforms//os:windows"],
    )
    for name in [
        "batch_script",
        "powershell_script",
    ]
]

[
    diff_test(
        name = name + "_test",
        size = "small",
        file1 = ":%s_count" % name,
        file2 = "1000.golden",
        target_compatible_with = ["@platforms//os:windows"],
    )
    for name in [
        "batch_script",
        "powershell_script",
    ]
]

# A failing cmdlet stops the Powershell command.
genrule(
    name = "powershell_failing_cmdlet",
    outs = ["powershell_failing_cmdlet.txt"],
    cmd_ps = "try { echo hello > $@; Get-Item does_not_exist; echo world >> $@ } catch { echo stopped >> $@ }",
    target_compatible_with = ["@platforms//os:windows"],
)

# Removes carriage returns and UTF-8 byte order marks from Powershell output.
genrule(
    name = "powershell_failing_cmdlet_normalized",
    srcs = [":powershell_failing_cmdlet"],
    outs = ["powershell_failing_cmdlet_normalized.txt"],
    cmd = "LC_ALL=C tr -d '\\r\\357\\273\\277' < $< > $@",
    target_compatible_with = ["@platforms//os:windows"],
)

diff_test(
    name = "powershell_failing_cmdlet_test",
    size = "small",
    file1 = ":powershell_failing_cmdlet_normalized",
    file2 = "powershell_failing_cmdlet.golden",
    target_compatible_with = ["@platforms//os:windows"],
)

# Genrules in external repositories resolve labels relative to their
# repository and write to its output directory.
[
    diff_test(
        name = "external_repo_%s_test" % out.replace("/", "_"),
        size = "small",
        file1 = "@genrule_test_repo//package:" + out,
        file2 = "hi.golden",
    )
    for out in [
        "a/b",
        "c/d",
    ]
]

# The outputs of genrules in external repositories can be used as sources and
# tools.
genrule(
    name = "external_location",
    srcs = ["@genrule_test_repo//package:hello"],
    outs = ["external_location.txt"],
    cmd = "cat $(location @genrule_test_repo//package:hello) > \"$@\"",
)

genrule(
    name = "external_location_tool",
    outs = ["external_location_tool.txt"],
    cmd = "$(location @genrule_test_repo//package:hello_tool) > \"$@\"",
    tools = ["@genrule_test_repo//package:hello_tool"],
)

[
    diff_test(
        name = name + "_test",
        size = "small",
        file1 = ":" + name,
        file2 = "hello.golden",
    )
    for name in [
        "external_location",
        "external_location_tool",
    ]
]
