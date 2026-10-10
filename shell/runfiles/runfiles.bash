# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Runfiles lookup library for Bazel-built Bash binaries and tests, version 3.
#
# This file is the bash entry point to the runfiles library. The implementation
# is runfiles.sh, next to this file, which this file sources; README.md in this
# directory describes both. It adds one default: unless AWK is set or
# RULES_SHELL_RUNFILES_USE_AWK=0, manifests are searched with `awk` from PATH,
# so that scripts written for the historical grep-based runfiles.bash keep
# lookups whose cost does not grow with the manifest. If there is no awk,
# runfiles.sh falls back to its shell loops.
#
# Everything the historical runfiles.bash exported is still exported here: the
# public functions, RUNFILES_REPO_MAPPING, _RLOCATION_ISABS_PATTERN and
# _RLOCATION_GREP_CASE_INSENSITIVE_ARGS, and the `__runfiles_*` helpers, two of
# which live at the end of this file for that reason alone. The helpers are not
# API; __runfiles_normalize_rlocation_path now stores its result in _rf_np_out
# instead of printing it.
#
# VERSION HISTORY:
# - version 3: Fixes a bug in the init code on macOS and makes the library aware
#              of Bzlmod repository mappings.
#   Features:
#     - With Bzlmod enabled, rlocation now takes the repository mapping of the
#       Bazel repository containing the calling script into account when
#       looking up runfiles. The new, optional second argument to rlocation can
#       be used to specify the canonical name of the Bazel repository to use
#       instead of this default. The new runfiles_current_repository function
#       can be used to obtain the canonical name of the N-th caller's Bazel
#       repository.
#   Fixed:
#     - Sourcing a shell script that contains the init code from a shell script
#       that itself contains the init code no longer fails on macOS.
#   Compatibility:
#     - The init script and the runfiles library are backwards and forwards
#       compatible with version 2.
# - version 2: Shorter init code.
#   Features:
#     - "set -euo pipefail" only at end of init code.
#       "set -e" breaks the source <path1> || source <path2> || ... scheme on
#       macOS, because it terminates if path1 does not exist.
#     - Not exporting any environment variables in init code.
#       This is now done in runfiles.bash itself.
#   Compatibility:
#     - The v1 init code can load the v2 library, i.e. if you have older source
#       code (still using v1 init) then you can build it with newer Bazel (which
#       contains the v2 library).
#     - The reverse is not true: the v2 init code CANNOT load the v1 library,
#       i.e. if your project (or any of its external dependencies) use v2 init
#       code, then you need a newer Bazel version (which contains the v2
#       library).
# - version 1: Original Bash runfiles library.
#
# ENVIRONMENT:
# - If RUNFILES_LIB_DEBUG=1 is set, the script will print diagnostic messages to
#   stderr.
# - AWK and RULES_SHELL_RUNFILES_USE_AWK, see above.
#
# USAGE:
# 1.  Depend on this runfiles library from your build rule:
#
#       sh_binary(
#           name = "my_binary",
#           ...
#           deps = ["@rules_shell//shell/runfiles"],
#       )
#
# 2.  Source the runfiles library.
#
#     The runfiles library itself defines rlocation which you would need to look
#     up the library's runtime location, thus we have a chicken-and-egg problem.
#     Insert the following code snippet to the top of your main script:
#
#       # --- begin runfiles.bash initialization v3 ---
#       # Copy-pasted from the Bazel Bash runfiles library v3.
#       set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
#       # shellcheck disable=SC1090
#       source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
#         source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
#         source "$0.runfiles/$f" 2>/dev/null || \
#         source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
#         source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
#         { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
#       # --- end runfiles.bash initialization v3 ---
#
#
# 3.  Use rlocation to look up runfile paths.
#
#       cat "$(rlocation my_workspace/path/to/my/data.txt)"
#
# You can skip steps 1 and 2 when setting "use_bash_launcher" attribute in sh_binary or sh_test.
#

# runfiles.sh is installed next to this file wherever this file is: in the
# source tree, and under bazel_tools/tools/bash/runfiles/ in a runfiles
# directory (see //shell/runfiles:runfiles_at_legacy_location). A manifest
# entry for this file points at the source tree, so the same holds there.
_rf_bash_dir="${BASH_SOURCE[0]%/*}"
[[ "$_rf_bash_dir" == "${BASH_SOURCE[0]}" ]] && _rf_bash_dir=.
if [[ ! -f "$_rf_bash_dir/runfiles.sh" ]]; then
  echo >&2 "ERROR[runfiles.bash]: cannot find runfiles.sh next to ${BASH_SOURCE[0]}"
  unset _rf_bash_dir
  return 1
fi

# Enable awk unless the caller has made a choice. AWK is only set for the
# duration of the source: runfiles.sh records the program it will use in an
# exported variable of its own, so neither this shell nor its children need AWK
# in their environment afterwards.
_rf_bash_awk=
if [[ -z "${AWK:-}" && "${RULES_SHELL_RUNFILES_USE_AWK:-}" != 0 ]]; then
  _rf_bash_awk=1
  AWK="awk"
fi

# Tells runfiles.sh that it is being sourced through this file, so that it
# looks one frame further up BASH_SOURCE for the script that sourced it.
_rf_bash_wrapped=1

# shellcheck disable=SC1091
source "$_rf_bash_dir/runfiles.sh"

[[ -n "$_rf_bash_awk" ]] && unset AWK
unset _rf_bash_dir _rf_bash_awk _rf_bash_wrapped

# --- Exported by the historical runfiles.bash, kept for compatibility ---

# runfiles.sh detects the platform with shell builtins and records it in
# _RLOCATION_ISABS_WINDOWS / _RLOCATION_CASE_INSENSITIVE; these are the
# grep-era spellings of the same answer.
if [[ -n "${_RLOCATION_ISABS_WINDOWS:-}" ]]; then
  # matches an absolute Windows path
  export _RLOCATION_ISABS_PATTERN="^[a-zA-Z]:[/\\]"
  # Windows paths are case insensitive and Bazel and MSYS2 capitalize differently, so we can't
  # assume that all paths are in the same native case.
  export _RLOCATION_GREP_CASE_INSENSITIVE_ARGS=-i
else
  # matches an absolute Unix path
  export _RLOCATION_ISABS_PATTERN="^/[^/].*"
  export _RLOCATION_GREP_CASE_INSENSITIVE_ARGS=
fi

# Does not exit with a non-zero exit code if no match is found and performs a case-insensitive
# search on Windows.
function __runfiles_maybe_grep() {
  # The GREP_XXX variables influence how grep behaves. Specifically, they can
  # affect the output from the grep command.
  GREP_COLOR="" GREP_OPTIONS="" grep $_RLOCATION_GREP_CASE_INSENSITIVE_ARGS "$@" || test $? = 1;
}
export -f __runfiles_maybe_grep

# Escape the argument for use in a grep regex.
# This is used to escape paths that may contain special characters.
function __runfiles_escape_grep() {
  echo -n "$1" | sed 's/[.[\*^$]/\\&/g'
}
export -f __runfiles_escape_grep
