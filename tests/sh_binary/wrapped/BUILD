load(":wrapper.bzl", "wrapper")

# Lives in a separate package as the wrapped executable has the same name as
# the original one.
[
    wrapper(
        name = "wrapped_" + name,
        target = "//tests/sh_binary:" + name,
        visibility = ["//tests/sh_binary:__pkg__"],
    )
    for name in [
        "hello",
        "hello_bash_launcher",
    ]
]
