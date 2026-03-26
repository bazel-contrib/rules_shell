#!/bin/sh
# shellcheck disable=SC3043
#
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
set -eu

NL='
'

_log_base() {
  _prefix=$1
  shift
  echo >&2 "${_prefix}[runfiles_test.sh ($(date "+%H:%M:%S %z"))] $*"
}

fail() {
  _log_base "FAILED" "$@"
  exit 1
}

log_fail() {
  _log_base "FAILED" "$@"
}

log_info() {
  _log_base "INFO" "$@"
}

is_windows() {
  [ -n "${SYSTEMROOT:-}" ] || [ -n "${COMSPEC:-}" ]
}

find_runfiles_lib() {
  if type rlocation >/dev/null 2>&1; then
    unset -f rlocation
    unset -f runfiles_export_envvars
  fi

  if ! [ -d "${RUNFILES_DIR:-/dev/null}" ] && ! [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    if [ -f "$0.runfiles_manifest" ]; then
      export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
    elif [ -f "$0.runfiles/MANIFEST" ]; then
      export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
    elif [ -f "$0.runfiles/_main/shell/runfiles/runfiles.sh" ]; then
      export RUNFILES_DIR="$0.runfiles"
    fi
  fi
  if [ -f "${RUNFILES_DIR:-/dev/null}/_main/shell/runfiles/runfiles.sh" ]; then
    echo "${RUNFILES_DIR}/_main/shell/runfiles/runfiles.sh"
  elif [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    _target="_main/shell/runfiles/runfiles.sh"
    while IFS= read -r _line; do
      case "$_line" in
        "${_target} "*)
          echo "${_line#"${_target} "}"
          return 0
          ;;
      esac
    done < "$RUNFILES_MANIFEST_FILE"
    echo >&2 "ERROR: cannot find //shell/runfiles:runfiles.sh"
    exit 1
  else
    echo >&2 "ERROR: cannot find //shell/runfiles:runfiles.sh"
    exit 1
  fi
}

test_rlocation_call_requires_no_envvars() {
  export RUNFILES_DIR=mock/runfiles
  export RUNFILES_MANIFEST_FILE=
  export RUNFILES_MANIFEST_ONLY=
  . "$runfiles_lib_path" || fail
}

test_rlocation_argument_validation() {
  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE=
  export RUNFILES_MANIFEST_ONLY=
  . "$runfiles_lib_path"

  if rlocation "../foo" >/dev/null 2>&1; then
    fail
  fi
  if rlocation "foo/.." >/dev/null 2>&1; then
    fail
  fi
  if rlocation "foo/../bar" >/dev/null 2>&1; then
    fail
  fi
  if rlocation "./foo" >/dev/null 2>&1; then
    fail
  fi
  if rlocation "foo/." >/dev/null 2>&1; then
    fail
  fi
  if rlocation "foo/./bar" >/dev/null 2>&1; then
    fail
  fi
  if rlocation "//foo" >/dev/null 2>&1; then
    fail
  fi
  if rlocation "foo//" >/dev/null 2>&1; then
    fail
  fi
  if rlocation "foo//bar" >/dev/null 2>&1; then
    fail
  fi
  if rlocation "\\foo" >/dev/null 2>&1; then
    fail
  fi
}

test_rlocation_abs_path() {
  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE=
  export RUNFILES_MANIFEST_ONLY=
  . "$runfiles_lib_path"

  if is_windows; then
    [ "$(rlocation "c:/Foo" || echo failed)" = "c:/Foo" ] || fail
    [ "$(rlocation "c:\\Foo" || echo failed)" = "c:\\Foo" ] || fail
  else
    [ "$(rlocation "/Foo" || echo failed)" = "/Foo" ] || fail
  fi
}

test_init_manifest_based_runfiles() {
  local tmpdir
  tmpdir="$(mktemp -d "$TEST_TMPDIR/tmp.XXXXXXXX")"
  cat > "$tmpdir/foo.runfiles_manifest" << EOF
a/b $tmpdir/c/d
e/f $tmpdir/g h
y $tmpdir/y
c/dir $tmpdir/dir
unresolved $tmpdir/unresolved
 h/\si $tmpdir/ j k
 h/\s\bi $tmpdir/ j k b
 h/\n\bi $tmpdir/ \bnj k \na
 dir\swith\sspaces $tmpdir/dir with spaces
 space\snewline\nbackslash\b_dir $tmpdir/space newline\nbackslash\ba
EOF
  mkdir "${tmpdir}/c"
  mkdir "${tmpdir}/y"
  mkdir -p "${tmpdir}/dir/deeply/nested"
  touch "${tmpdir}/c/d" "${tmpdir}/g h"
  touch "${tmpdir}/dir/file"
  ln -s /does/not/exist "${tmpdir}/dir/unresolved"
  touch "${tmpdir}/dir/deeply/nested/file"
  touch "${tmpdir}/dir/deeply/nested/file with spaces"
  ln -s /does/not/exist "${tmpdir}/unresolved"
  touch "${tmpdir}/ j k"
  touch "${tmpdir}/ j k b"
  mkdir -p "${tmpdir}/dir with spaces/nested"
  touch "${tmpdir}/dir with spaces/nested/file"
  if ! is_windows; then
    touch "${tmpdir}/ \\nj k ${NL}a"
    mkdir -p "${tmpdir}/space newline${NL}backslash\\a"
    touch "${tmpdir}/space newline${NL}backslash\\a/f i\\le"
  fi

  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/foo.runfiles_manifest"
  . "$runfiles_lib_path"

  [ -z "$(rlocation a || echo failed)" ] || fail
  [ -z "$(rlocation c/d || echo failed)" ] || fail
  [ "$(rlocation a/b || echo failed)" = "$tmpdir/c/d" ] || fail
  [ "$(rlocation e/f || echo failed)" = "$tmpdir/g h" ] || fail
  [ "$(rlocation y || echo failed)" = "$tmpdir/y" ] || fail
  [ -z "$(rlocation c || echo failed)" ] || fail
  [ -z "$(rlocation c/di || echo failed)" ] || fail
  [ "$(rlocation c/dir || echo failed)" = "$tmpdir/dir" ] || fail
  [ "$(rlocation c/dir/file || echo failed)" = "$tmpdir/dir/file" ] || fail
  [ -z "$(rlocation c/dir/unresolved || echo failed)" ] || fail
  [ "$(rlocation c/dir/deeply/nested/file || echo failed)" = "$tmpdir/dir/deeply/nested/file" ] || fail
  [ "$(rlocation "c/dir/deeply/nested/file with spaces" || echo failed)" = "$tmpdir/dir/deeply/nested/file with spaces" ] || fail
  [ -z "$(rlocation unresolved || echo failed)" ] || fail
  [ "$(rlocation "h/ i" || echo failed)" = "$tmpdir/ j k" ] || fail
  [ "$(rlocation "h/ \\i" || echo failed)" = "$tmpdir/ j k b" ] || fail
  [ "$(rlocation "dir with spaces" || echo failed)" = "$tmpdir/dir with spaces" ] || fail
  [ "$(rlocation "dir with spaces/nested/file" || echo failed)" = "$tmpdir/dir with spaces/nested/file" ] || fail
  if ! is_windows; then
    [ "$(rlocation "h/${NL}\\i" || echo failed)" = "$tmpdir/ \\nj k ${NL}a" ] || fail
    [ "$(rlocation "space newline${NL}backslash\\_dir/f i\\le" || echo failed)" = "${tmpdir}/space newline${NL}backslash\\a/f i\\le" ] || fail
  fi

  rm -r "$tmpdir/c/d" "$tmpdir/g h" "$tmpdir/y" "$tmpdir/dir" "$tmpdir/unresolved" "$tmpdir/ j k" "$tmpdir/dir with spaces"
  if ! is_windows; then
    rm -r "$tmpdir/ \\nj k ${NL}a" "${tmpdir}/space newline${NL}backslash\\a"
    [ -z "$(rlocation "h/${NL}\\i" || echo failed)" ] || fail
    [ -z "$(rlocation "space newline${NL}backslash\\_dir/f i\\le" || echo failed)" ] || fail
  fi
  [ -z "$(rlocation a/b || echo failed)" ] || fail
  [ -z "$(rlocation e/f || echo failed)" ] || fail
  [ -z "$(rlocation y || echo failed)" ] || fail
  [ -z "$(rlocation c/dir || echo failed)" ] || fail
  [ -z "$(rlocation c/dir/file || echo failed)" ] || fail
  [ -z "$(rlocation c/dir/deeply/nested/file || echo failed)" ] || fail
  [ -z "$(rlocation "h/ i" || echo failed)" ] || fail
  [ -z "$(rlocation "dir with spaces" || echo failed)" ] || fail
  [ -z "$(rlocation "dir with spaces/nested/file" || echo failed)" ] || fail
}

test_manifest_based_envvars() {
  local tmpdir
  tmpdir="$(mktemp -d "$TEST_TMPDIR/tmp.XXXXXXXX")"
  echo "a b" > "$tmpdir/foo.runfiles_manifest"

  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/foo.runfiles_manifest"
  mkdir -p "$tmpdir/foo.runfiles"
  . "$runfiles_lib_path"

  runfiles_export_envvars
  [ "${RUNFILES_DIR:-}" = "$tmpdir/foo.runfiles" ] || fail
  [ "${RUNFILES_MANIFEST_FILE:-}" = "$tmpdir/foo.runfiles_manifest" ] || fail
}

test_init_directory_based_runfiles() {
  local tmpdir
  tmpdir="$(mktemp -d "$TEST_TMPDIR/tmp.XXXXXXXX")"

  export RUNFILES_DIR="${tmpdir}/mock/runfiles"
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  mkdir -p "$RUNFILES_DIR/a"
  touch "$RUNFILES_DIR/a/b" "$RUNFILES_DIR/c d"
  [ "$(rlocation a || echo failed)" = "$RUNFILES_DIR/a" ] || fail
  [ "$(rlocation c/d || echo failed)" = "failed" ] || fail
  [ "$(rlocation a/b || echo failed)" = "$RUNFILES_DIR/a/b" ] || fail
  [ "$(rlocation "c d" || echo failed)" = "$RUNFILES_DIR/c d" ] || fail
  [ "$(rlocation "c" || echo failed)" = "failed" ] || fail
  rm -r "$RUNFILES_DIR/a" "$RUNFILES_DIR/c d"
  [ "$(rlocation a || echo failed)" = "failed" ] || fail
  [ "$(rlocation a/b || echo failed)" = "failed" ] || fail
  [ "$(rlocation "c d" || echo failed)" = "failed" ] || fail
}

test_directory_based_runfiles_with_repo_mapping_from_main() {
  local tmpdir
  tmpdir="$(mktemp -d "$TEST_TMPDIR/tmp.XXXXXXXX")"

  export RUNFILES_DIR="${tmpdir}/mock/runfiles"
  mkdir -p "$RUNFILES_DIR"
  cat > "$RUNFILES_DIR/_repo_mapping" <<EOF
,config.json,config.json+1.2.3
,my_module,_main
,my_protobuf,protobuf+3.19.2
,my_workspace,_main
protobuf+3.19.2,protobuf,protobuf+3.19.2
protobuf+3.19.2,config.json,config.json+1.2.3
EOF
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  mkdir -p "$RUNFILES_DIR/_main/bar"
  touch "$RUNFILES_DIR/_main/bar/runfile"
  mkdir -p "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted"
  touch "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/file"
  touch "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le"
  mkdir -p "$RUNFILES_DIR/protobuf+3.19.2/foo"
  touch "$RUNFILES_DIR/protobuf+3.19.2/foo/runfile"
  touch "$RUNFILES_DIR/config.json"

  [ "$(rlocation "my_module/bar/runfile" "" || echo failed)" = "$RUNFILES_DIR/_main/bar/runfile" ] || fail
  [ "$(rlocation "my_workspace/bar/runfile" "" || echo failed)" = "$RUNFILES_DIR/_main/bar/runfile" ] || fail
  [ "$(rlocation "my_protobuf/foo/runfile" "" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/foo/runfile" ] || fail
  [ "$(rlocation "my_protobuf/bar/dir" "" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir" ] || fail
  [ "$(rlocation "my_protobuf/bar/dir/file" "" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/file" ] || fail
  [ "$(rlocation "my_protobuf/bar/dir/de eply/nes ted/fi+le" "" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" ] || fail

  [ "$(rlocation "protobuf/foo/runfile" "" || echo failed)" = "failed" ] || fail
  [ "$(rlocation "protobuf/bar/dir/dir/de eply/nes ted/fi+le" "" || echo failed)" = "failed" ] || fail

  [ "$(rlocation "_main/bar/runfile" "" || echo failed)" = "$RUNFILES_DIR/_main/bar/runfile" ] || fail
  [ "$(rlocation "protobuf+3.19.2/foo/runfile" "" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/foo/runfile" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir" "" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir/file" "" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/file" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" "" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" ] || fail

  [ "$(rlocation "config.json" "" || echo failed)" = "$RUNFILES_DIR/config.json" ] || fail
}

test_directory_based_runfiles_with_repo_mapping_from_other_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "$TEST_TMPDIR/tmp.XXXXXXXX")"

  export RUNFILES_DIR="${tmpdir}/mock/runfiles"
  mkdir -p "$RUNFILES_DIR"
  cat > "$RUNFILES_DIR/_repo_mapping" <<EOF
,config.json,config.json+1.2.3
,my_module,_main
,my_protobuf,protobuf+3.19.2
,my_workspace,_main
protobuf+3.19.2,protobuf,protobuf+3.19.2
protobuf+3.19.2,config.json,config.json+1.2.3
EOF
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  mkdir -p "$RUNFILES_DIR/_main/bar"
  touch "$RUNFILES_DIR/_main/bar/runfile"
  mkdir -p "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted"
  touch "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/file"
  touch "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le"
  mkdir -p "$RUNFILES_DIR/protobuf+3.19.2/foo"
  touch "$RUNFILES_DIR/protobuf+3.19.2/foo/runfile"
  touch "$RUNFILES_DIR/config.json"

  [ "$(rlocation "protobuf/foo/runfile" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/foo/runfile" ] || fail
  [ "$(rlocation "protobuf/bar/dir" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir" ] || fail
  [ "$(rlocation "protobuf/bar/dir/file" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/file" ] || fail
  [ "$(rlocation "protobuf/bar/dir/de eply/nes ted/fi+le" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" ] || fail

  [ "$(rlocation "my_module/bar/runfile" "protobuf+3.19.2" || echo failed)" = "failed" ] || fail
  [ "$(rlocation "my_protobuf/bar/dir/de eply/nes ted/fi+le" "protobuf+3.19.2" || echo failed)" = "failed" ] || fail

  [ "$(rlocation "_main/bar/runfile" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/_main/bar/runfile" ] || fail
  [ "$(rlocation "protobuf+3.19.2/foo/runfile" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/foo/runfile" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir/file" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/file" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" ] || fail

  [ "$(rlocation "config.json" "protobuf+3.19.2" || echo failed)" = "$RUNFILES_DIR/config.json" ] || fail
}

test_directory_based_runfiles_with_repo_mapping_from_extension_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "$TEST_TMPDIR/tmp.XXXXXXXX")"

  export RUNFILES_DIR="${tmpdir}/mock/runfiles"
  mkdir -p "$RUNFILES_DIR"
  cat > "$RUNFILES_DIR/_repo_mapping" <<EOF
,config.json,config.json+1.2.3
,my_module,_main
,my_protobuf,protobuf+3.19.2
,my_workspace,_main
my_module++ex+*,my_module,my_module+
my_module++ext+*,my_module,my_module+
my_module++ext+*,repo1,my_module++ext+repo1
my_module++ext1+*,my_module,my_module+
EOF
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  mkdir -p "$RUNFILES_DIR/_main/bar"
  touch "$RUNFILES_DIR/_main/bar/runfile"
  mkdir -p "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted"
  touch "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/file"
  touch "$RUNFILES_DIR/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le"
  mkdir -p "$RUNFILES_DIR/protobuf+3.19.2/foo"
  touch "$RUNFILES_DIR/protobuf+3.19.2/foo/runfile"
  touch "$RUNFILES_DIR/config.json"
  mkdir -p "$RUNFILES_DIR/my_module+/foo"
  touch "$RUNFILES_DIR/my_module+/foo/runfile"
  mkdir -p "$RUNFILES_DIR/my_module++ext+repo1/foo"
  touch "$RUNFILES_DIR/my_module++ext+repo1/foo/runfile"
  mkdir -p "$RUNFILES_DIR/repo2+/foo"
  touch "$RUNFILES_DIR/repo2+/foo/runfile"

  [ "$(rlocation "my_module/foo/runfile" "my_module++ext+repo1" || echo failed)" = "$RUNFILES_DIR/my_module+/foo/runfile" ] || fail
  [ "$(rlocation "repo1/foo/runfile" "my_module++ext+repo1" || echo failed)" = "$RUNFILES_DIR/my_module++ext+repo1/foo/runfile" ] || fail
  [ "$(rlocation "repo2+/foo/runfile" "my_module++ext+repo1" || echo failed)" = "$RUNFILES_DIR/repo2+/foo/runfile" ] || fail
}

test_manifest_based_runfiles_with_repo_mapping_from_main() {
  local tmpdir
  tmpdir="$(mktemp -d "$TEST_TMPDIR/tmp.XXXXXXXX")"

  cat > "$tmpdir/foo.repo_mapping" <<EOF
,config.json,config.json+1.2.3
,my_module,_main
,my_protobuf,protobuf+3.19.2
,my_workspace,_main
protobuf+3.19.2,protobuf,protobuf+3.19.2
protobuf+3.19.2,config.json,config.json+1.2.3
EOF
  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/foo.runfiles_manifest"
  cat > "$RUNFILES_MANIFEST_FILE" << EOF
_repo_mapping $tmpdir/foo.repo_mapping
config.json $tmpdir/config.json
protobuf+3.19.2/foo/runfile $tmpdir/protobuf+3.19.2/foo/runfile
_main/bar/runfile $tmpdir/_main/bar/runfile
protobuf+3.19.2/bar/dir $tmpdir/protobuf+3.19.2/bar/dir
EOF
  . "$runfiles_lib_path"

  mkdir -p "$tmpdir/_main/bar"
  touch "$tmpdir/_main/bar/runfile"
  mkdir -p "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted"
  touch "$tmpdir/protobuf+3.19.2/bar/dir/file"
  touch "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le"
  mkdir -p "$tmpdir/protobuf+3.19.2/foo"
  touch "$tmpdir/protobuf+3.19.2/foo/runfile"
  touch "$tmpdir/config.json"

  [ "$(rlocation "my_module/bar/runfile" "" || echo failed)" = "$tmpdir/_main/bar/runfile" ] || fail
  [ "$(rlocation "my_workspace/bar/runfile" "" || echo failed)" = "$tmpdir/_main/bar/runfile" ] || fail
  [ "$(rlocation "my_protobuf/foo/runfile" "" || echo failed)" = "$tmpdir/protobuf+3.19.2/foo/runfile" ] || fail
  [ "$(rlocation "my_protobuf/bar/dir" "" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir" ] || fail
  [ "$(rlocation "my_protobuf/bar/dir/file" "" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir/file" ] || fail
  [ "$(rlocation "my_protobuf/bar/dir/de eply/nes ted/fi+le" "" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" ] || fail

  [ -z "$(rlocation "protobuf/foo/runfile" "" || echo failed)" ] || fail
  [ -z "$(rlocation "protobuf/bar/dir/dir/de eply/nes ted/fi+le" "" || echo failed)" ] || fail

  [ "$(rlocation "_main/bar/runfile" "" || echo failed)" = "$tmpdir/_main/bar/runfile" ] || fail
  [ "$(rlocation "protobuf+3.19.2/foo/runfile" "" || echo failed)" = "$tmpdir/protobuf+3.19.2/foo/runfile" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir" "" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir/file" "" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir/file" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" "" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" ] || fail

  [ "$(rlocation "config.json" "" || echo failed)" = "$tmpdir/config.json" ] || fail
}

test_manifest_based_runfiles_with_repo_mapping_from_other_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "$TEST_TMPDIR/tmp.XXXXXXXX")"

  cat > "$tmpdir/foo.repo_mapping" <<EOF
,config.json,config.json+1.2.3
,my_module,_main
,my_protobuf,protobuf+3.19.2
,my_workspace,_main
protobuf+3.19.2,protobuf,protobuf+3.19.2
protobuf+3.19.2,config.json,config.json+1.2.3
EOF
  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/foo.runfiles_manifest"
  cat > "$RUNFILES_MANIFEST_FILE" << EOF
_repo_mapping $tmpdir/foo.repo_mapping
config.json $tmpdir/config.json
protobuf+3.19.2/foo/runfile $tmpdir/protobuf+3.19.2/foo/runfile
_main/bar/runfile $tmpdir/_main/bar/runfile
protobuf+3.19.2/bar/dir $tmpdir/protobuf+3.19.2/bar/dir
EOF
  . "$runfiles_lib_path"

  mkdir -p "$tmpdir/_main/bar"
  touch "$tmpdir/_main/bar/runfile"
  mkdir -p "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted"
  touch "$tmpdir/protobuf+3.19.2/bar/dir/file"
  touch "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le"
  mkdir -p "$tmpdir/protobuf+3.19.2/foo"
  touch "$tmpdir/protobuf+3.19.2/foo/runfile"
  touch "$tmpdir/config.json"

  [ "$(rlocation "protobuf/foo/runfile" "protobuf+3.19.2" || echo failed)" = "$tmpdir/protobuf+3.19.2/foo/runfile" ] || fail
  [ "$(rlocation "protobuf/bar/dir" "protobuf+3.19.2" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir" ] || fail
  [ "$(rlocation "protobuf/bar/dir/file" "protobuf+3.19.2" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir/file" ] || fail
  [ "$(rlocation "protobuf/bar/dir/de eply/nes ted/fi+le" "protobuf+3.19.2" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" ] || fail

  [ -z "$(rlocation "my_module/bar/runfile" "protobuf+3.19.2" || echo failed)" ] || fail
  [ -z "$(rlocation "my_protobuf/bar/dir/de eply/nes ted/fi+le" "protobuf+3.19.2" || echo failed)" ] || fail

  [ "$(rlocation "_main/bar/runfile" "protobuf+3.19.2" || echo failed)" = "$tmpdir/_main/bar/runfile" ] || fail
  [ "$(rlocation "protobuf+3.19.2/foo/runfile" "protobuf+3.19.2" || echo failed)" = "$tmpdir/protobuf+3.19.2/foo/runfile" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir" "protobuf+3.19.2" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir/file" "protobuf+3.19.2" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir/file" ] || fail
  [ "$(rlocation "protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" "protobuf+3.19.2" || echo failed)" = "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le" ] || fail

  [ "$(rlocation "config.json" "protobuf+3.19.2" || echo failed)" = "$tmpdir/config.json" ] || fail
}

test_manifest_based_runfiles_with_repo_mapping_from_extension_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "$TEST_TMPDIR/tmp.XXXXXXXX")"

  cat > "$tmpdir/foo.repo_mapping" <<EOF
,config.json,config.json+1.2.3
,my_module,_main
,my_protobuf,protobuf+3.19.2
,my_workspace,_main
my_module++ex+*,my_module,my_module+
my_module++ext+*,my_module,my_module+
my_module++ext+*,repo1,my_module++ext+repo1
my_module++ext1+*,my_module,my_module+
EOF
  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/foo.runfiles_manifest"
  cat > "$RUNFILES_MANIFEST_FILE" << EOF
_repo_mapping $tmpdir/foo.repo_mapping
config.json $tmpdir/config.json
protobuf+3.19.2/foo/runfile $tmpdir/protobuf+3.19.2/foo/runfile
_main/bar/runfile $tmpdir/_main/bar/runfile
protobuf+3.19.2/bar/dir $tmpdir/protobuf+3.19.2/bar/dir
my_module+/foo/runfile $tmpdir/my_module+/runfile
my_module++ext+repo1/foo/runfile $tmpdir/my_module++ext+repo1/runfile
repo2+/foo/runfile $tmpdir/repo2+/runfile
EOF
  . "$runfiles_lib_path"

  mkdir -p "$tmpdir/_main/bar"
  touch "$tmpdir/_main/bar/runfile"
  mkdir -p "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted"
  touch "$tmpdir/protobuf+3.19.2/bar/dir/file"
  touch "$tmpdir/protobuf+3.19.2/bar/dir/de eply/nes ted/fi+le"
  mkdir -p "$tmpdir/protobuf+3.19.2/foo"
  touch "$tmpdir/protobuf+3.19.2/foo/runfile"
  touch "$tmpdir/config.json"
  mkdir -p "$tmpdir/my_module+"
  touch "$tmpdir/my_module+/runfile"
  mkdir -p "$tmpdir/my_module++ext+repo1"
  touch "$tmpdir/my_module++ext+repo1/runfile"
  mkdir -p "$tmpdir/repo2+"
  touch "$tmpdir/repo2+/runfile"

  [ "$(rlocation "my_module/foo/runfile" "my_module++ext+repo1" || echo failed)" = "$tmpdir/my_module+/runfile" ] || fail
  [ "$(rlocation "repo1/foo/runfile" "my_module++ext+repo1" || echo failed)" = "$tmpdir/my_module++ext+repo1/runfile" ] || fail
  [ "$(rlocation "repo2+/foo/runfile" "my_module++ext+repo1" || echo failed)" = "$tmpdir/repo2+/runfile" ] || fail
}

test_directory_based_envvars() {
  export RUNFILES_DIR=mock/runfiles
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  runfiles_export_envvars
  [ "${RUNFILES_DIR:-}" = "mock/runfiles" ] || fail
  [ -z "${RUNFILES_MANIFEST_FILE:-}" ] || fail
}

main() {
  manifest_file="${RUNFILES_MANIFEST_FILE:-}"
  dir="${RUNFILES_DIR:-}"
  runfiles_lib_path=$(find_runfiles_lib)

  tests="
    test_rlocation_call_requires_no_envvars
    test_rlocation_argument_validation
    test_rlocation_abs_path
    test_init_manifest_based_runfiles
    test_manifest_based_envvars
    test_init_directory_based_runfiles
    test_directory_based_runfiles_with_repo_mapping_from_main
    test_directory_based_runfiles_with_repo_mapping_from_other_repo
    test_directory_based_runfiles_with_repo_mapping_from_extension_repo
    test_manifest_based_runfiles_with_repo_mapping_from_main
    test_manifest_based_runfiles_with_repo_mapping_from_other_repo
    test_manifest_based_runfiles_with_repo_mapping_from_extension_repo
    test_directory_based_envvars
  "
  failure=0
  for t in $tests; do
    export RUNFILES_MANIFEST_FILE="$manifest_file"
    export RUNFILES_DIR="$dir"
    log_info "Running $t"
    if ! ($t); then
      log_fail "$t"
      failure=1
    fi
  done
  return $failure
}

main
