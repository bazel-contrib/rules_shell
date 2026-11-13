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

# Times the runfiles library against generated manifests and prints the table
# in shell/runfiles/README.md. Run with
#
#   bazel run //tests/runfiles:benchmark -- [--baseline FILE] [--sizes "5000 20000 50000"] [--runs 3]
#
# --baseline names a runfiles.bash to time alongside, for example the library
# before this one: `git show 660e16c:shell/runfiles/runfiles.bash`. The POSIX
# columns run under `sh`, whatever that is on the host; the last one sets
# RULES_SHELL_RUNFILES_USE_AWK=0, so that the shell loops search the manifests.
set -euo pipefail

baseline=
sizes="5000 20000 50000"
runs=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline) baseline="$2"; shift 2 ;;
    --sizes) sizes="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    *) echo >&2 "unknown argument: $1"; exit 2 ;;
  esac
done

runfiles_dir="${RUNFILES_DIR:-$0.runfiles}"
sh_lib="$runfiles_dir/${RUNFILES_SH:?set by the BUILD target}"
bash_lib="$runfiles_dir/${RUNFILES_BASH:?set by the BUILD target}"
[[ -f "$sh_lib" && -f "$bash_lib" ]] || { echo >&2 "cannot find the library under $runfiles_dir"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/dir/_main/pkg"
: > "$work/leaf"
: > "$work/repo_mapping"
ln -s "$work/leaf" "$work/dir/_main/pkg/leaf"

# A manifest of n entries with keys shaped like a pip dependency's, plus
# _repo_mapping and one main-repository key, which sort to the top.
generate() {
  awk -v n="$1" -v leaf="$work/leaf" -v rm="$work/repo_mapping" 'BEGIN {
    srand(7)
    np = split("sphinxcontrib_applehelp requests urllib3 charset_normalizer numpy pandas setuptools pip wheel certifi idna packaging typing_extensions pyyaml markupsafe jinja2", p, " ")
    ns = split("locales/ca/LC_MESSAGES util/ssl_ core/internal _vendor/rich tests/data/fixtures __pycache__ static/css templates/admin", s, " ")
    for (i = 0; i < n; i++)
      printf "rules_python++pip+pip_312_%s_py3_none_any_%08x/site-packages/%s/%s/file%d.py %s\n", p[i % np + 1], int(rand() * 4294967296), p[i % np + 1], s[i % ns + 1], i, leaf
    print "_main/pkg/leaf " leaf
    print "_repo_mapping " rm
  }' | LC_ALL=C sort > "$work/m$1"
}

# Wall time in ms, best of $runs, of: <shell> -c ". <lib>; <body>" with <env>.
ms() {
  local shell="$1" lib="$2" extra="$3" body="$4" best=999999 t r
  for ((r = 0; r < runs; r++)); do
    t=$( { TIMEFORMAT=%R; time env -u AWK -u RULES_SHELL_RUNFILES_USE_AWK $extra "$shell" -c ". '$lib'; $body" >/dev/null 2>&1; } 2>&1 )
    t=$(awk -v t="$t" 'BEGIN { printf "%d", t * 1000 }')
    (( t < best )) && best=$t
  done
  echo "$best"
}

fmt() { if (( $1 >= 1000 )); then awk -v t="$1" 'BEGIN { printf "%.1f s", t / 1000 }'; else echo "$1 ms"; fi; }

# One row: label, env for the manifest or directory, body of lookups.
row() {
  local label="$1" env="$2" body="$3" cells=
  [[ -n "$baseline" ]] && cells+=" $(fmt "$(ms bash "$baseline" "$env" "$body")") |"
  cells+=" $(fmt "$(ms bash "$bash_lib" "$env" "$body")") |"
  cells+=" $(fmt "$(ms bash "$sh_lib" "$env" "$body")") |"
  cells+=" $(fmt "$(ms sh "$sh_lib" "$env" "$body")") |"
  cells+=" $(fmt "$(ms sh "$sh_lib" "$env RULES_SHELL_RUNFILES_USE_AWK=0" "$body")") |"
  echo "| $label |$cells"
}

sh_name=$(sh -c 'echo "${BASH_VERSION:+bash $BASH_VERSION}"'); sh_name="${sh_name:-$(basename "$(readlink -f "$(command -v sh)")")}"
header="| manifest |"; rule="|---|"
[[ -n "$baseline" ]] && { header+=" baseline |"; rule+="---|"; }
header+=" \`runfiles.bash\` | \`runfiles.sh\`, bash | \`runfiles.sh\`, sh | \`runfiles.sh\`, sh, no awk |"; rule+="---|---|---|---|"
echo "Shells: bash $BASH_VERSION, sh is $sh_name, awk is $(${AWK:-awk} --version 2>/dev/null | head -1 || echo "${AWK:-awk}"). Best of $runs."
echo
echo "$header"; echo "$rule"

for n in $sizes; do
  generate "$n"
  env="RUNFILES_DIR= RUNFILES_MANIFEST_FILE=$work/m$n"
  body=
  for pct in 2 4 6 8 10; do
    key=$(sed -n "$((n * pct / 10))p" "$work/m$n" | cut -d' ' -f1)
    body+="x=\$(rlocation $key);"
  done
  row "$n lines, 5 keys spread through it" "$env" "$body"
done
first=$(echo "$sizes" | cut -d' ' -f1)
row "$first lines, 1 key near the top" "RUNFILES_DIR= RUNFILES_MANIFEST_FILE=$work/m$first" 'x=$(rlocation _main/pkg/leaf);'
row "runfiles directory, 1 key" "RUNFILES_DIR=$work/dir RUNFILES_MANIFEST_FILE=" 'x=$(rlocation _main/pkg/leaf);'

last=$(echo "$sizes" | awk '{ print $NF }')
env="RUNFILES_DIR= RUNFILES_MANIFEST_FILE=$work/m$last"
body=
for _ in 1 2 3 4 5 6 7 8 9 10; do
  for pct in 2 4 6 8 10; do
    key=$(sed -n "$((last * pct / 10))p" "$work/m$last" | cut -d' ' -f1)
    body+="x=\$(rlocation $key);"
  done
done
echo
echo "50 keys spread through the $last-line manifest: $(fmt "$(ms bash "$bash_lib" "$env" "$body")") through \`runfiles.bash\`, $(fmt "$(ms bash "$sh_lib" "$env RULES_SHELL_RUNFILES_USE_AWK=0" "$body")") with the shell loops under bash."
