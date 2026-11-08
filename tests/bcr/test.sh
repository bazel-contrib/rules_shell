#!/usr/bin/env bash
# Copyright 2024 The Bazel Authors. All rights reserved.
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

# --- begin runfiles.bash initialization v4 ---
# Copy-pasted from the Bazel Bash runfiles library v4.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash; _rf_p=; _rf_a=
if [ -n "${AWK:-}" ] || [ "${RULES_SHELL_RUNFILES_USE_AWK:-}" != 0 ]; then _rf_a=1; fi
_rf_d() { [ -f "$1/$f" ] && _rf_p="$1/$f"; }
_rf_m() { [ -f "$1" ] || return 1; if [ -n "$_rf_a" ]; then \
  _rf_p=$(${AWK:-awk} -v k="$f " 'index($0,k)==1{print substr($0,length(k)+1);m=1;exit}END{exit !m}' "$1" 2>/dev/null) && return; fi; \
  while IFS= read -r _rf_l || [ -n "$_rf_l" ]; do \
  case "$_rf_l" in "$f "*) _rf_p="${_rf_l#"$f "}"; return;; esac; done < "$1"; return 1; }
_rf_d "${RUNFILES_DIR:-/dev/null}" || _rf_m "${RUNFILES_MANIFEST_FILE:-/dev/null}" || \
  _rf_d "$0.runfiles" || _rf_m "$0.runfiles_manifest" || _rf_m "$0.exe.runfiles_manifest" || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }
# shellcheck disable=SC1090
source "$_rf_p" || { echo>&2 "ERROR: cannot source $_rf_p"; exit 1; }; f=; unset -f _rf_d _rf_m; unset _rf_l _rf_p _rf_a; set -e
# --- end runfiles.bash initialization v4 ---

bin_path="$(rlocation "rules_shell_tests/bin.sh")"
if [[ ! -x "${bin_path}" ]]; then
  echo "Expected '${bin_path}' to be an executable"
  exit 1
fi

runfiles_export_envvars

greeting=$("${bin_path}")
if [[ "${greeting}" != "hello from rules_shell" ]]; then
  echo "Expected 'hello from rules_shell', got '${greeting}'"
  exit 1
fi
