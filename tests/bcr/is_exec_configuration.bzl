def _is_exec_configuration(ctx):
    # https://github.com/bazelbuild/bazel/issues/14444
    return config_common.FeatureFlagInfo(
        # feature flags must be strings, so we're avoiding True and False in
        # favor of "yes" and "no" to avoid confusion between "True" and True
        value = "yes" if "-exec" in ctx.bin_dir.path else "no",
    )

is_exec_configuration = rule(
    doc = "identify if the current target is in exec configuration",
    implementation = _is_exec_configuration,
)
