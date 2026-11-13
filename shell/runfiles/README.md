# Runfiles library

`runfiles.sh` is the runfiles library for `sh_binary` and `sh_test` scripts,
written in POSIX shell. `runfiles.bash` is a thin wrapper that sources it, for
bash scripts and for the `bazel_tools/tools/bash/runfiles/runfiles.bash`
initialization snippets they already carry. Both expose the same public API:
`rlocation`, `runfiles_export_envvars`, `runfiles_current_repository` and
`runfiles_rlocation_checked`. The header of each file documents its
initialization snippet and the environment variables it reads.

Under bash the library behaves the way the bash library always has: the
caller's repository is detected from `BASH_SOURCE`, and the functions are
exported with `export -f`, which is how the `use_bash_launcher` launcher makes
them available to a script without a snippet. Under any other shell neither is
possible: `runfiles_current_repository` needs the caller's script path as its
argument, `rlocation` without a second argument assumes the main repository,
and every script sources the library itself.

## What a lookup costs

A lookup served from a runfiles directory is one `stat`, with nothing forked. A
lookup served from a manifest has to search it. Which of the two a script gets
is not a property of the platform: the manifest is used whenever
`RUNFILES_MANIFEST_FILE` names an existing file. On Linux a sandboxed
`bazel test` sees only `RUNFILES_DIR`; `bazel run`, a directly executed binary
and everything on Windows go through the manifest.

The library searches a manifest with one `awk` process per lookup when awk
can be found (`AWK` names the program, `awk` from `PATH` otherwise). awk reads
the file in bulk, so the cost of a lookup does not grow with the manifest.
With `RULES_SHELL_RUNFILES_USE_AWK=0`, or on a host without awk, a shell
`read` loop searches instead, at 10 to 45 µs per line: a lookup then costs in
proportion to how far down the manifest its key sits, and a miss costs two
passes, one for the key and one for its directory prefixes. Nothing is forked
in that mode. The initialization snippets find the library the same way.

## Measurements

`bazel run //tests/runfiles:benchmark` generates manifests with keys shaped
like a pip dependency's, times a script that sources the library and resolves
keys spread through them, and prints this table. `--baseline FILE` adds a
column for another `runfiles.bash`; here it is the library before this one,
`git show 660e16c:shell/runfiles/runfiles.bash`. Measured on one Linux machine
with bash 5.2, dash as `sh` and gawk 5.2, best of 3.

| manifest | baseline | `runfiles.bash` | `runfiles.sh`, bash | `runfiles.sh`, sh | `runfiles.sh`, sh, no awk |
|---|---|---|---|---|---|
| 5000 lines, 5 keys spread through it | 81 ms | 21 ms | 21 ms | 14 ms | 316 ms |
| 20000 lines, 5 keys spread through it | 84 ms | 30 ms | 29 ms | 21 ms | 1.1 s |
| 50000 lines, 5 keys spread through it | 90 ms | 42 ms | 41 ms | 34 ms | 2.7 s |
| 5000 lines, 1 key near the top | 22 ms | 7 ms | 7 ms | 4 ms | 2 ms |
| runfiles directory, 1 key | 3 ms | 3 ms | 3 ms | 1 ms | 1 ms |

50 keys spread through the 50000-line manifest: 380 ms through `runfiles.bash`,
7.4 s with the shell loops under bash.
