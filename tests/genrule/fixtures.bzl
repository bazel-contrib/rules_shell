"""Helper rules for the `genrule` tests."""

load("@with_cfg.bzl", "with_cfg")
load("//shell:genrule.bzl", "genrule")

def _template_variables_impl(ctx):
    variables = dict(ctx.attr.variables)
    files = []
    if ctx.file.file:
        variables[ctx.attr.file_variable] = ctx.file.file.path
        files.append(ctx.file.file)
    if ctx.attr.generated_file_variable:
        generated_file = ctx.actions.declare_file(ctx.label.name + ".txt")
        ctx.actions.write(generated_file, "generated\n")
        variables[ctx.attr.generated_file_variable] = generated_file.path
        files.append(generated_file)
    return [
        platform_common.TemplateVariableInfo(variables),
        DefaultInfo(files = depset(files)),
    ]

template_variables = rule(
    implementation = _template_variables_impl,
    doc = "Provides \"Make\" variables to the `toolchains` of a genrule.",
    attrs = {
        "variables": attr.string_dict(),
        # A file whose path is provided as the variable `file_variable`.
        "file": attr.label(allow_single_file = True),
        "file_variable": attr.string(),
        # The variable that provides the path of a generated file.
        "generated_file_variable": attr.string(),
    },
)

def _template_toolchain_impl(ctx):
    return [
        platform_common.TemplateVariableInfo(ctx.attr.variables),
        platform_common.ToolchainInfo(),
    ]

template_toolchain = rule(
    implementation = _template_toolchain_impl,
    doc = "A toolchain that provides \"Make\" variables.",
    attrs = {
        "variables": attr.string_dict(),
    },
)

GenruleInputsInfo = provider(
    doc = "The inputs of the genrule action of a target.",
    fields = ["inputs"],
)

def _genrule_inputs_aspect_impl(target, _ctx):
    inputs = [
        action.inputs
        for action in target.actions
        if action.mnemonic == "Genrule"
    ]
    return [GenruleInputsInfo(inputs = depset(transitive = inputs))]

_genrule_inputs_aspect = aspect(
    implementation = _genrule_inputs_aspect_impl,
)

def _exec_genrule_inputs_impl(ctx):
    return [ctx.attr.genrule[GenruleInputsInfo]]

exec_genrule_inputs = rule(
    implementation = _exec_genrule_inputs_impl,
    doc = "Exposes the inputs of a genrule analyzed in the exec configuration.",
    attrs = {
        "genrule": attr.label(
            aspects = [_genrule_inputs_aspect],
            cfg = "exec",
            mandatory = True,
        ),
    },
)

def _script_without_default_files_impl(ctx):
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = script,
        content = "#!/bin/sh\necho 'hello world' > \"$1\"\n",
        is_executable = True,
    )
    return [DefaultInfo(
        files = depset(),
        executable = script,
    )]

script_without_default_files = rule(
    implementation = _script_without_default_files_impl,
    doc = "An executable that is not among its default outputs.",
    executable = True,
)

# A genrule built with an --action_env entry.
genrule_with_action_env, _genrule_with_action_env = (
    with_cfg(genrule)
        .extend("action_env", ["FROM_ACTION_ENV=action_env_value"])
        .build()
)

def _executable_with_multiple_files_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = executable,
        content = "#!/bin/sh\n",
        is_executable = True,
    )
    data = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(
        output = data,
        content = "",
    )
    return [DefaultInfo(
        files = depset([data, executable]),
        executable = executable,
    )]

executable_with_multiple_files = rule(
    implementation = _executable_with_multiple_files_impl,
    doc = "An executable whose default outputs also contain another file.",
    executable = True,
)

def _executable_dependency_impl(ctx):
    return [DefaultInfo(files = depset([ctx.executable.executable]))]

executable_dependency = rule(
    implementation = _executable_dependency_impl,
    doc = "Depends on an executable in the exec configuration.",
    attrs = {
        "executable": attr.label(
            cfg = "exec",
            executable = True,
            mandatory = True,
        ),
    },
)
