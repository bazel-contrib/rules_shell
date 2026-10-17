#!/usr/bin/env bash
# Copyright 2026 The Bazel Authors. All rights reserved.
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

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

# Arguments that are hard to pass through the launcher on Windows. Shell
# metacharacters such as $ or ; are only passed through correctly as of Bazel
# 10 (https://github.com/bazelbuild/bazel/commit/aa3eebdee0874b1620d84febbfd8358ea0ffb9f6).
args=('a' 'a b' '"b"' 'C:\a\b\' '"C:\a b\c\"' '')
expected=$(printf '%s\n' "${#args[@]}"; printf '[%s]\n' "${args[@]}")

runfiles_export_envvars

# The binaries under test are passed as runfiles paths of the generated
# executables, not the scripts.
for binary in "$@"; do
  binary_path=$(rlocation "$binary")
  actual=$("$binary_path" "${args[@]}")
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected output of $binary:"
    echo "--- expected"
    echo "$expected"
    echo "--- actual"
    echo "$actual"
    exit 1
  fi
done
