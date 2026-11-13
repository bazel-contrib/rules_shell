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

# Runfiles lookup library for Bazel-built Bash binaries and tests, version 4.
#
# This file is the bash entry point to the runfiles library. The implementation
# is runfiles.sh, next to this file, which this file sources; README.md in this
# directory describes both.
#
# VERSION HISTORY:
# - version 4: The init code resolves the library's location before sourcing
#              it, instead of sourcing each candidate location in turn.
#   Features:
#     - Errors the library prints while it is sourced are no longer hidden,
#       and a library that fails to load aborts the script.
#     - The manifest is searched with awk, or a shell loop, instead of grep
#       and cut.
#   Compatibility:
#     - The init script and the runfiles library are backwards and forwards
#       compatible with versions 2 and 3.
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
# - AWK and RULES_SHELL_RUNFILES_USE_AWK, see runfiles.sh.
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
#       # --- begin runfiles.bash initialization v4 ---
#       # Copy-pasted from the Bazel Bash runfiles library v4.
#       set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash; _rf_p=; _rf_a=
#       if [ -n "${AWK:-}" ] || [ "${RULES_SHELL_RUNFILES_USE_AWK:-}" != 0 ]; then _rf_a=1; fi
#       _rf_d() { [ -f "$1/$f" ] && _rf_p="$1/$f"; }
#       _rf_m() { [ -f "$1" ] || return 1; if [ -n "$_rf_a" ]; then \
#         _rf_p=$(${AWK:-awk} -v k="$f " 'index($0,k)==1{print substr($0,length(k)+1);m=1;exit}END{exit !m}' "$1" 2>/dev/null) && return; fi; \
#         while IFS= read -r _rf_l || [ -n "$_rf_l" ]; do \
#         case "$_rf_l" in "$f "*) _rf_p="${_rf_l#"$f "}"; return;; esac; done < "$1"; return 1; }
#       _rf_d "${RUNFILES_DIR:-/dev/null}" || _rf_m "${RUNFILES_MANIFEST_FILE:-/dev/null}" || \
#         _rf_d "$0.runfiles" || _rf_m "$0.runfiles_manifest" || _rf_m "$0.exe.runfiles_manifest" || \
#         { echo>&2 "ERROR: cannot find $f"; exit 1; }
#       # shellcheck disable=SC1090
#       source "$_rf_p" || { echo>&2 "ERROR: cannot source $_rf_p"; exit 1; }; f=; unset -f _rf_d _rf_m; unset _rf_l _rf_p _rf_a; set -e
#       # --- end runfiles.bash initialization v4 ---
#
#     `_rf_d` checks a runfiles directory and `_rf_m` searches a manifest, with
#     awk unless RULES_SHELL_RUNFILES_USE_AWK=0 and a shell loop otherwise, so
#     that only an existing file is sourced. The v3 snippet keeps working.
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
# A missing runfiles.sh fails the source the way a missing runfiles.bash does.
# The message is visible with the v4 snippet and the launcher; the v3 snippet
# redirects stderr.
if [[ ! -f "$_rf_bash_dir/runfiles.sh" ]]; then
  echo >&2 "ERROR[runfiles.bash]: cannot find runfiles.sh next to ${BASH_SOURCE[0]}"
  unset _rf_bash_dir
  return 1
fi

# shellcheck disable=SC1091
source "$_rf_bash_dir/runfiles.sh"

unset _rf_bash_dir
