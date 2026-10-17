"""A rule that wraps an executable, as a symlink with the same runfiles."""

def _wrapper_impl(ctx):
    target = ctx.attr.target
    original_executable = target[DefaultInfo].files_to_run.executable
    executable = ctx.actions.declare_file(original_executable.basename)
    ctx.actions.symlink(output = executable, target_file = original_executable)
    data_runfiles = ctx.runfiles([executable]).merge(target[DefaultInfo].data_runfiles)
    default_runfiles = ctx.runfiles([executable]).merge(target[DefaultInfo].default_runfiles)
    return [
        DefaultInfo(
            executable = executable,
            files = target[DefaultInfo].files,
            data_runfiles = data_runfiles,
            default_runfiles = default_runfiles,
        ),
    ]

wrapper = rule(
    implementation = _wrapper_impl,
    attrs = {
        "target": attr.label(
            cfg = "target",
            executable = True,
        ),
    },
    executable = True,
)
