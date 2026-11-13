#!/bin/sh
# shellcheck shell=sh
# The library under test is sourced from a path computed at run time.
# shellcheck disable=SC1090
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

# This suite tests the POSIX shell runfiles library, so it is meant to run under
# a real POSIX shell: bash-in-POSIX-mode still parses bashisms. Which shell
# `#!/bin/sh` resolves to is the host's choice (dash on Debian and Ubuntu, bash
# on Fedora and macOS), so the suite runs under whatever it gets, and the
# `test_posix_shell_runfiles` presubmit task, which runs where /bin/sh is dash,
# sets RUNFILES_TEST_REQUIRE_POSIX_SH=1 so that interpreter drift there cannot
# silently cost dash coverage.
if [ -n "${BASH_VERSION:-}" ] && [ -n "${RUNFILES_TEST_REQUIRE_POSIX_SH:-}" ]; then
  echo >&2 "ERROR[runfiles_test.sh]: POSIX suite invoked under bash ($BASH_VERSION)" \
           "with RUNFILES_TEST_REQUIRE_POSIX_SH set"
  exit 1
fi

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

  # RUNFILES_LIBRARY_FILE is the rlocation path of runfiles.sh, plumbed in via
  # the sh_test rule's `env` (see tests/runfiles/BUILD). The main-repo prefix
  # varies between Bzlmod (`_main/...`) and WORKSPACE (`rules_shell/...`), so
  # we can't hardcode it.
  _target="${RUNFILES_LIBRARY_FILE:-}"
  if [ -z "$_target" ]; then
    echo >&2 "ERROR: RUNFILES_LIBRARY_FILE is not set — the sh_test rule must" \
             "pass \$(rlocationpath //shell/runfiles:runfiles_sh)"
    exit 1
  fi

  if ! [ -d "${RUNFILES_DIR:-/dev/null}" ] && ! [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    if [ -f "$0.runfiles_manifest" ]; then
      export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
    elif [ -f "$0.runfiles/MANIFEST" ]; then
      export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
    elif [ -f "$0.runfiles/${_target}" ]; then
      export RUNFILES_DIR="$0.runfiles"
    fi
  fi
  if [ -f "${RUNFILES_DIR:-/dev/null}/${_target}" ]; then
    echo "${RUNFILES_DIR}/${_target}"
  elif [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    while IFS= read -r _line; do
      case "$_line" in
        "${_target} "*)
          echo "${_line#"${_target} "}"
          return 0
          ;;
      esac
    done < "$RUNFILES_MANIFEST_FILE"
    echo >&2 "ERROR: cannot find $_target"
    exit 1
  else
    echo >&2 "ERROR: cannot find $_target"
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
  tmpdir="$TEST_TMPDIR/test_init_manifest_based_runfiles"
  mkdir -p "$tmpdir"
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
  tmpdir="$TEST_TMPDIR/test_manifest_based_envvars"
  mkdir -p "$tmpdir"
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
  tmpdir="$TEST_TMPDIR/test_init_directory_based_runfiles"
  mkdir -p "$tmpdir"

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

# Without RUNFILES_DIR and RUNFILES_MANIFEST_FILE the library derives them from
# $0. A runfiles directory counts when it holds the library under either of
# the names //shell/runfiles installs it as, including the legacy bazel_tools
# one alone, which is all a tree built against Bazel's own runfiles target has.
test_init_derives_runfiles_dir_from_legacy_location() {
  tmpdir="$TEST_TMPDIR/test_init_derives_runfiles_dir_from_legacy_location"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir/bin.runfiles/bazel_tools/tools/bash/runfiles" "$tmpdir/bin.runfiles/r"
  cp "$runfiles_lib_path" "$tmpdir/bin.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash"
  touch "$tmpdir/bin.runfiles/r/f"
  printf '#!/bin/sh\n. "%s"\nrlocation r/f\n' "$runfiles_lib_path" > "$tmpdir/bin"

  actual=$(RUNFILES_DIR='' RUNFILES_MANIFEST_FILE='' sh "$tmpdir/bin")
  [ "$actual" = "$tmpdir/bin.runfiles/r/f" ] \
    || fail "expected RUNFILES_DIR to be derived from \$0.runfiles, got: $actual"
}

test_directory_based_runfiles_with_repo_mapping_from_main() {
  tmpdir="$TEST_TMPDIR/test_directory_based_runfiles_with_repo_mapping_from_main"
  mkdir -p "$tmpdir"

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
  tmpdir="$TEST_TMPDIR/test_directory_based_runfiles_with_repo_mapping_from_other_repo"
  mkdir -p "$tmpdir"

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
  tmpdir="$TEST_TMPDIR/test_directory_based_runfiles_with_repo_mapping_from_extension_repo"
  mkdir -p "$tmpdir"

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
  tmpdir="$TEST_TMPDIR/test_manifest_based_runfiles_with_repo_mapping_from_main"
  mkdir -p "$tmpdir"

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
  tmpdir="$TEST_TMPDIR/test_manifest_based_runfiles_with_repo_mapping_from_other_repo"
  mkdir -p "$tmpdir"

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
  tmpdir="$TEST_TMPDIR/test_manifest_based_runfiles_with_repo_mapping_from_extension_repo"
  mkdir -p "$tmpdir"

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

test_directory_based_runfiles_with_repo_mapping_from_module_root_repo() {
  # A bzlmod module's canonical name ("rules_shell+") ends in a separator with
  # no safe characters after it, so the sed pattern that
  # __runfiles_compute_repo_prefix emulates leaves it unchanged. A wildcard
  # prefix ("rules_shell+*") would let an unrelated compact-form mapping row
  # match and rlocation return the wrong file.
  tmpdir="$TEST_TMPDIR/test_directory_based_runfiles_with_repo_mapping_from_module_root_repo"
  mkdir -p "$tmpdir"

  export RUNFILES_DIR="${tmpdir}/mock/runfiles"
  mkdir -p "$RUNFILES_DIR"
  # No literal "rules_shell+,dep,..." row; only a compact form that matches the
  # wildcard prefix and nothing else.
  cat > "$RUNFILES_DIR/_repo_mapping" <<EOF
rules_shell+*,dep,wrong+
EOF
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  mkdir -p "$RUNFILES_DIR/dep/pkg"
  touch "$RUNFILES_DIR/dep/pkg/f"
  mkdir -p "$RUNFILES_DIR/wrong+/pkg"
  touch "$RUNFILES_DIR/wrong+/pkg/f"

  # The compact row does not match, so rlocation keeps the path as given.
  [ "$(rlocation "dep/pkg/f" "rules_shell+" || echo failed)" = "$RUNFILES_DIR/dep/pkg/f" ] || fail
}

test_directory_based_envvars() {
  export RUNFILES_DIR=mock/runfiles
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  runfiles_export_envvars
  [ "${RUNFILES_DIR:-}" = "mock/runfiles" ] || fail
  [ -z "${RUNFILES_MANIFEST_FILE:-}" ] || fail
}

test_rlocation_auto_detects_source_repo_under_bash() {
  # Under bash, rlocation with no source-repo arg must walk BASH_SOURCE[2] via
  # runfiles_current_repository to identify the caller's repo — matching
  # runfiles.bash. Without this the repo mapping is silently resolved through
  # the main repo for every downstream sh_binary/sh_test.
  # Skipped under a POSIX shell (no BASH_SOURCE, no auto-detect possible).
  if ! command -v bash > /dev/null 2>&1; then
    return 0
  fi

  tmpdir="$TEST_TMPDIR/test_rlocation_auto_detects_source_repo_under_bash"
  mkdir -p "$tmpdir"

  export RUNFILES_DIR="${tmpdir}/mock/runfiles"
  mkdir -p "$RUNFILES_DIR/some_repo+/pkg"

  # Repo mapping: from source repo "some_repo+", "dep" -> "realdep+".
  # Also add a main-repo row that maps "dep" somewhere ELSE, so we can tell
  # whether auto-detection ran (the caller lives in some_repo+, not _main).
  cat > "$RUNFILES_DIR/_repo_mapping" <<EOF
,dep,mainrepo_dep+
some_repo+,dep,realdep+
EOF

  mkdir -p "$RUNFILES_DIR/realdep+" "$RUNFILES_DIR/mainrepo_dep+"
  touch "$RUNFILES_DIR/realdep+/foo" "$RUNFILES_DIR/mainrepo_dep+/foo"

  # Helper lives at RUNFILES_DIR/some_repo+/pkg/caller.sh so
  # runfiles_current_repository can identify its repo as "some_repo+" via the
  # under-RUNFILES_DIR branch.
  cat > "$RUNFILES_DIR/some_repo+/pkg/caller.sh" <<HELPER
#!/bin/bash
# shellcheck disable=SC1090
. "$runfiles_lib_path"
rlocation "dep/foo"
HELPER
  chmod +x "$RUNFILES_DIR/some_repo+/pkg/caller.sh"

  export RUNFILES_MANIFEST_FILE=

  actual=$(bash "$RUNFILES_DIR/some_repo+/pkg/caller.sh")
  [ "$actual" = "$RUNFILES_DIR/realdep+/foo" ] \
    || fail "expected $RUNFILES_DIR/realdep+/foo, got: $actual"
}

test_runfiles_current_repository_under_set_u() {
  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  # Enabling nounset must not crash runfiles_current_repository, regardless of
  # calling convention. rc is expected to be non-zero since no runfiles are
  # configured, but the function must not error on unbound $1.
  set -u
  runfiles_current_repository "$0" >/dev/null 2>&1 || :
  runfiles_current_repository >/dev/null 2>&1 || :
  set +u
}

# runfiles_current_repository resolves the repository of the script at the path
# it is given, which is the POSIX calling convention: a sourced library has no
# BASH_SOURCE, so it passes its own location. Writes a library at $1 defining
# function $2, which reports that repository, or the fixed string $3 for a
# stale copy that must never be sourced.
write_current_repository_lib() {
  mkdir -p "${1%/*}"
  if [ -n "${3:-}" ]; then
    printf '%s() {\n  echo "%s"\n}\n' "$2" "$3" > "$1"
  else
    printf '%s() {\n  runfiles_current_repository "%s"\n}\n' "$2" "$1" > "$1"
  fi
}

test_current_repository_directory_based() {
  tmpdir="$TEST_TMPDIR/test_current_repository_directory_based"
  rm -rf "$tmpdir"

  export RUNFILES_DIR="$tmpdir/mock/runfiles"
  export RUNFILES_MANIFEST_FILE=
  write_current_repository_lib "$RUNFILES_DIR/protobuf+3.19.2/foo/lib.sh" repo_of_other
  write_current_repository_lib "$RUNFILES_DIR/_main/bar/lib.sh" repo_of_main
  . "$runfiles_lib_path"

  . "$(rlocation "protobuf+3.19.2/foo/lib.sh" "")" || fail
  [ "$(repo_of_other || echo failed)" = "protobuf+3.19.2" ] \
    || fail "expected protobuf+3.19.2, got: $(repo_of_other || echo failed)"

  . "$(rlocation "_main/bar/lib.sh" "")" || fail
  [ "$(repo_of_main || echo failed)" = "" ] \
    || fail "expected the main repository, got: $(repo_of_main || echo failed)"
}

test_current_repository_manifest_based() {
  tmpdir="$TEST_TMPDIR/test_current_repository_manifest_based"
  rm -rf "$tmpdir"

  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/foo.runfiles_manifest"
  write_current_repository_lib "$tmpdir/protobuf+3.19.2/foo/lib.sh" repo_of_other
  write_current_repository_lib "$tmpdir/_main/bar/lib.sh" repo_of_main
  cat > "$RUNFILES_MANIFEST_FILE" <<EOF
protobuf+3.19.2/foo/lib.sh $tmpdir/protobuf+3.19.2/foo/lib.sh
_main/bar/lib.sh $tmpdir/_main/bar/lib.sh
EOF
  . "$runfiles_lib_path"

  . "$(rlocation "protobuf+3.19.2/foo/lib.sh" "")" || fail
  [ "$(repo_of_other || echo failed)" = "protobuf+3.19.2" ] \
    || fail "expected protobuf+3.19.2, got: $(repo_of_other || echo failed)"

  . "$(rlocation "_main/bar/lib.sh" "")" || fail
  [ "$(repo_of_main || echo failed)" = "" ] \
    || fail "expected the main repository, got: $(repo_of_main || echo failed)"
}

# Both variables are set at once e.g. on Windows with --enable_runfiles, where
# the runfiles directory holds the MANIFEST that runfiles_export_envvars
# promotes to RUNFILES_MANIFEST_FILE. The manifest maps rlocation paths to the
# *original* files, so a caller looked up through it is never found under the
# directory.
test_current_repository_directory_and_manifest_based() {
  tmpdir="$TEST_TMPDIR/test_current_repository_directory_and_manifest_based"
  rm -rf "$tmpdir"

  export RUNFILES_DIR="$tmpdir/mock/runfiles"
  export RUNFILES_MANIFEST_FILE="$RUNFILES_DIR/MANIFEST"
  write_current_repository_lib "$tmpdir/protobuf+3.19.2/foo/lib.sh" repo_of_other
  write_current_repository_lib "$tmpdir/_main/bar/lib.sh" repo_of_main
  # The runfiles directory may hold stale contents, so the manifest wins.
  write_current_repository_lib "$RUNFILES_DIR/protobuf+3.19.2/foo/lib.sh" repo_of_other stale
  write_current_repository_lib "$RUNFILES_DIR/_main/bar/lib.sh" repo_of_main stale
  cat > "$RUNFILES_MANIFEST_FILE" <<EOF
protobuf+3.19.2/foo/lib.sh $tmpdir/protobuf+3.19.2/foo/lib.sh
_main/bar/lib.sh $tmpdir/_main/bar/lib.sh
EOF
  . "$runfiles_lib_path"

  [ "$(rlocation "protobuf+3.19.2/foo/lib.sh" "" || echo failed)" = "$tmpdir/protobuf+3.19.2/foo/lib.sh" ] || fail
  . "$(rlocation "protobuf+3.19.2/foo/lib.sh" "")" || fail
  [ "$(repo_of_other || echo failed)" = "protobuf+3.19.2" ] \
    || fail "expected protobuf+3.19.2, got: $(repo_of_other || echo failed)"

  [ "$(rlocation "_main/bar/lib.sh" "" || echo failed)" = "$tmpdir/_main/bar/lib.sh" ] || fail
  . "$(rlocation "_main/bar/lib.sh" "")" || fail
  [ "$(repo_of_main || echo failed)" = "" ] \
    || fail "expected the main repository, got: $(repo_of_main || echo failed)"
}

# Platform detection must work without shelling out to uname. Drive
# __runfiles_detect_platform directly with a faked environment so that the
# Windows branches are covered on non-Windows hosts too.
test_platform_detection_without_uname() {
  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  tmpdir="$TEST_TMPDIR/test_platform_detection_without_uname"
  mkdir -p "$tmpdir"

  # A /proc/version that does not exist, so only the environment is consulted.
  absent="$tmpdir/absent"

  check_detection() {
    _what="$1"
    _want="$2"
    if [ "${_RLOCATION_ISABS_WINDOWS:-}" != "$_want" ] ||
      [ "${_RLOCATION_CASE_INSENSITIVE:-}" != "$_want" ]; then
      fail "$_what: expected windows='$_want', got" \
        "_RLOCATION_ISABS_WINDOWS='${_RLOCATION_ISABS_WINDOWS:-}'" \
        "_RLOCATION_CASE_INSENSITIVE='${_RLOCATION_CASE_INSENSITIVE:-}'"
    fi
  }

  # 1. MSYSTEM, set by every MSYS2 / MinGW / Git-for-Windows shell.
  (
    MSYSTEM=MINGW64 __runfiles_detect_platform "$absent"
    check_detection "MSYSTEM=MINGW64" 1
  ) || return 1

  # 2. OSTYPE, set by bash on Cygwin and MSYS.
  for ostype in cygwin msys win32; do
    (
      unset MSYSTEM
      OSTYPE="$ostype" __runfiles_detect_platform "$absent"
      check_detection "OSTYPE=$ostype" 1
    ) || return 1
  done

  # 3. /proc/version naming a Windows runtime.
  for procver in "CYGWIN_NT-10.0-19045 version 3.4.7" \
    "MSYS_NT-10.0-19045 version 3.4.7" \
    "MINGW64_NT-10.0-19045 version 3.4.7"; do
    echo "$procver" > "$tmpdir/proc_version"
    (
      unset MSYSTEM OSTYPE
      __runfiles_detect_platform "$tmpdir/proc_version"
      check_detection "/proc/version=$procver" 1
    ) || return 1
  done

  # 4. A Unix /proc/version wins over inherited Windows env vars: WSL can
  #    import WINDIR from the host through WSLENV and must not be mistaken for
  #    a Windows shell.
  echo "Linux version 5.15.0-1051-microsoft-standard-WSL2" > "$tmpdir/proc_version"
  (
    unset MSYSTEM OSTYPE
    WINDIR='C:\Windows' SYSTEMROOT='C:\Windows' \
      __runfiles_detect_platform "$tmpdir/proc_version"
    check_detection "WSL with WINDIR set" ""
  ) || return 1

  # 5. No /proc at all, but Windows env vars present.
  (
    unset MSYSTEM OSTYPE
    WINDIR='C:\Windows' __runfiles_detect_platform "$absent"
    check_detection "WINDIR without /proc" 1
  ) || return 1

  # 6. Nothing indicates Windows.
  (
    unset MSYSTEM OSTYPE WINDIR SystemRoot SYSTEMROOT
    __runfiles_detect_platform "$absent"
    check_detection "no Windows signals" ""
  ) || return 1

  # The library must leave no temporaries behind in the caller's environment.
  for leaked in _rf_dp_win _rf_dp_line _rf_dp_procver_file; do
    eval "_value=\${$leaked:-}"
    if [ -n "$_value" ]; then
      fail "detection leaked \$$leaked='$_value' into the environment"
    fi
  done
}

# A manifest lookup falls back to the longest path prefix of the requested
# path, to resolve files only reachable through a directory runfile. That
# prefix has to end on a path separator: `c/dir` must not be treated as a
# prefix of `c/dirx/file` or of `c/dirfile`. The shared bash suite has no such
# collision, so cover it here.
test_manifest_prefix_respects_path_boundaries() {
  tmpdir="$TEST_TMPDIR/test_manifest_prefix_respects_path_boundaries"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir/dir" "$tmpdir/dirx"
  touch "$tmpdir/dir/file" "$tmpdir/dirx/file" "$tmpdir/dirfile"
  echo "c/dir $tmpdir/dir" > "$tmpdir/manifest"

  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/manifest"
  . "$runfiles_lib_path"

  [ "$(rlocation c/dir/file)" = "$tmpdir/dir/file" ] \
    || fail "expected c/dir/file to resolve through the c/dir prefix"
  [ -z "$(rlocation c/dirx/file)" ] \
    || fail "c/dir must not be treated as a path prefix of c/dirx/file"
  [ -z "$(rlocation c/dirfile)" ] \
    || fail "c/dir must not be treated as a path prefix of c/dirfile"
  # The prefix walk must also stop at the shortest segment, not match a bare
  # substring of the first one.
  [ -z "$(rlocation c)" ] || fail "c must not resolve"
}

# Manifest matching is case-insensitive on Windows. The shared bash suite only
# covers that when actually running on Windows, so force the flag on here to
# get the branch exercised everywhere.
test_manifest_lookup_case_insensitive() {
  tmpdir="$TEST_TMPDIR/test_manifest_lookup_case_insensitive"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir/dir"
  touch "$tmpdir/f" "$tmpdir/dir/file"
  cat > "$tmpdir/manifest" <<EOF
A/B/File.TXT $tmpdir/f
C/Dir $tmpdir/dir
EOF

  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/manifest"
  . "$runfiles_lib_path"
  export _RLOCATION_CASE_INSENSITIVE=1

  [ "$(rlocation a/b/file.txt)" = "$tmpdir/f" ] \
    || fail "expected a case-insensitive exact match"
  [ "$(rlocation A/B/File.TXT)" = "$tmpdir/f" ] \
    || fail "expected the exact-case lookup to keep working"
  [ "$(rlocation c/dir/file)" = "$tmpdir/dir/file" ] \
    || fail "expected a case-insensitive prefix match"
  [ -z "$(rlocation c/dirx/file)" ] \
    || fail "case-insensitive matching must still respect path boundaries"
}

# Manifests are searched with awk when it can be found, and with shell loops
# under RULES_SHELL_RUNFILES_USE_AWK=0, which is how `runfiles_sh_no_awk_test`
# runs this whole suite. The tests below cover the switch itself: awk is on by
# default, AWK names the program, and one that cannot be found leaves the shell
# loops in place rather than breaking every lookup.
write_awk_test_manifest() {
  rm -rf "$1"
  mkdir -p "$1/dir"
  touch "$1/f" "$1/dir/file"
  cat > "$1/manifest" <<EOF
r/f $1/f
r/d $1/dir
EOF
  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$1/manifest"
}

test_awk_on_by_default() {
  if ! command -v awk >/dev/null 2>&1; then
    log_info "no awk on PATH, skipping"
    return 0
  fi
  tmpdir="$TEST_TMPDIR/test_awk_on_by_default"
  write_awk_test_manifest "$tmpdir"

  unset AWK RULES_SHELL_RUNFILES_USE_AWK
  . "$runfiles_lib_path"

  [ "${_RULES_SHELL_RUNFILES_AWK:-}" = awk ] \
    || fail "expected awk from PATH, got: ${_RULES_SHELL_RUNFILES_AWK:-}"
  [ "$(rlocation r/f)" = "$tmpdir/f" ] || fail "expected an exact match through awk"
  [ "$(rlocation r/d/file)" = "$tmpdir/dir/file" ] \
    || fail "expected a prefix match through awk"
  [ -z "$(rlocation r/nope)" ] || fail "expected a miss through awk"
}

test_awk_disabled_by_env() {
  tmpdir="$TEST_TMPDIR/test_awk_disabled_by_env"
  write_awk_test_manifest "$tmpdir"

  unset AWK
  export RULES_SHELL_RUNFILES_USE_AWK=0
  . "$runfiles_lib_path"

  [ -z "${_RULES_SHELL_RUNFILES_AWK:-}" ] \
    || fail "expected RULES_SHELL_RUNFILES_USE_AWK=0 to keep the shell loops"
  [ "$(rlocation r/f)" = "$tmpdir/f" ] || fail "expected an exact match without awk"
  [ "$(rlocation r/d/file)" = "$tmpdir/dir/file" ] \
    || fail "expected a prefix match without awk"
  [ -z "$(rlocation r/nope)" ] || fail "expected a miss without awk"
}

test_awk_enabled_by_program() {
  if ! command -v awk >/dev/null 2>&1; then
    log_info "no awk on PATH, skipping"
    return 0
  fi
  tmpdir="$TEST_TMPDIR/test_awk_enabled_by_program"
  write_awk_test_manifest "$tmpdir"
  printf '#!/bin/sh\n: > "%s/called"\nexec awk "$@"\n' "$tmpdir" > "$tmpdir/myawk"
  chmod +x "$tmpdir/myawk"

  unset RULES_SHELL_RUNFILES_USE_AWK
  export AWK="$tmpdir/myawk"
  . "$runfiles_lib_path"

  [ "${_RULES_SHELL_RUNFILES_AWK:-}" = "$tmpdir/myawk" ] \
    || fail "expected AWK to be selected, got: ${_RULES_SHELL_RUNFILES_AWK:-}"
  [ "$(rlocation r/f)" = "$tmpdir/f" ] || fail "expected an exact match through awk"
  [ -e "$tmpdir/called" ] || fail "expected the configured awk program to be run"
  [ "$(rlocation r/d/file)" = "$tmpdir/dir/file" ] \
    || fail "expected a prefix match through awk"
  [ -z "$(rlocation r/nope)" ] || fail "expected a miss through awk"
}

test_awk_falls_back_when_program_is_missing() {
  tmpdir="$TEST_TMPDIR/test_awk_falls_back_when_program_is_missing"
  write_awk_test_manifest "$tmpdir"

  export AWK="$tmpdir/no-such-awk"
  . "$runfiles_lib_path"

  [ -z "${_RULES_SHELL_RUNFILES_AWK:-}" ] \
    || fail "expected the shell loops when the awk program is missing"
  [ "$(rlocation r/f)" = "$tmpdir/f" ] || fail "expected an exact match without awk"
  [ "$(rlocation r/d/file)" = "$tmpdir/dir/file" ] \
    || fail "expected a prefix match without awk"
  [ -z "$(rlocation r/nope)" ] || fail "expected a miss without awk"
}

# Writes a runfiles layout containing unresolved symlinks with relative
# targets, both as a manifest pointing at the original files and as a
# materialized runfiles directory.
write_relative_symlink_target_layout() {
  _wl_dir="$1/foo.runfiles"

  mkdir -p "$1/original/dir/deeply/nested"
  echo file > "$1/original/file"
  echo nested_file > "$1/original/dir/deeply/nested/file"
  # Lies next to the runfiles directory and is thus only reachable through a
  # relative target that leaves the runfiles tree.
  echo outside > "$1/outside"

  cat > "$1/foo.runfiles_manifest" <<EOF
_main/pkg/file $1/original/file
_main/pkg/dir $1/original/dir
_main/pkg/link ../pkg/file
_main/pkg/nested/link ../../pkg/link
_main/pkg/dir_link ./dir
_main/pkg/dangling ../pkg/missing
_main/pkg/escaping ../../../outside
_main/pkg/loop_a loop_b
_main/pkg/loop_b loop_a
 _main/pkg/link\swith\sspaces ../pkg/file
EOF

  mkdir -p "$_wl_dir/_main/pkg/nested"
  ln -s "$1/original/file" "$_wl_dir/_main/pkg/file"
  ln -s "$1/original/dir" "$_wl_dir/_main/pkg/dir"
  ln -s ../pkg/file "$_wl_dir/_main/pkg/link"
  ln -s ../../pkg/link "$_wl_dir/_main/pkg/nested/link"
  ln -s ./dir "$_wl_dir/_main/pkg/dir_link"
  ln -s ../pkg/missing "$_wl_dir/_main/pkg/dangling"
  ln -s ../../../outside "$_wl_dir/_main/pkg/escaping"
  ln -s loop_b "$_wl_dir/_main/pkg/loop_a"
  ln -s loop_a "$_wl_dir/_main/pkg/loop_b"
  ln -s ../pkg/file "$_wl_dir/_main/pkg/link with spaces"
}

# Asserts that $1 resolves to a file with contents $2. Only the contents are
# compared, since the path necessarily differs between the two lookup modes: a
# materialized runfiles directory resolves to the entry in that directory, not
# to the file it points at.
assert_rlocation_contents() {
  _ac_resolved="$(rlocation "$1" || echo failed)"
  [ -f "$_ac_resolved" ] || fail "$1 did not resolve to a file, got: $_ac_resolved"
  [ "$(cat "$_ac_resolved")" = "$2" ] \
    || fail "$1 resolved to $_ac_resolved with unexpected contents"
}

# Asserts that $1 does not resolve, which rlocation reports as an empty result
# when it uses the manifest and as a non-zero exit code when it uses the
# runfiles directory (see the FIXME on runfiles_rlocation_checked).
assert_no_rlocation() {
  _an_resolved="$(rlocation "$1" || echo failed)"
  [ -z "$_an_resolved" ] || [ "$_an_resolved" = failed ] \
    || fail "$1 unexpectedly resolved to $_an_resolved"
}

# The lookups whose outcome must not depend on whether the manifest or the
# runfiles directory backs them: resolving a relative target against the
# manifest has to arrive at the same file that the file system arrives at when
# resolving the corresponding symlink in the runfiles directory.
assert_relative_symlink_target_lookups() {
  assert_rlocation_contents _main/pkg/link file
  assert_rlocation_contents _main/pkg/nested/link file
  assert_rlocation_contents "_main/pkg/link with spaces" file
  # A relative target that resolves to a directory runfile also resolves paths
  # underneath it.
  [ -d "$(rlocation _main/pkg/dir_link || echo failed)" ] || fail
  assert_rlocation_contents _main/pkg/dir_link/deeply/nested/file nested_file
  # A target that doesn't resolve to an existing file behaves like a missing
  # runfile.
  assert_no_rlocation _main/pkg/dangling
  assert_no_rlocation _main/pkg/dir_link/does/not/exist
  # A cycle terminates instead of looping forever.
  assert_no_rlocation _main/pkg/loop_a
}

test_manifest_based_relative_symlink_targets() {
  tmpdir="$TEST_TMPDIR/test_manifest_based_relative_symlink_targets"
  rm -rf "$tmpdir"
  write_relative_symlink_target_layout "$tmpdir"

  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/foo.runfiles_manifest"
  . "$runfiles_lib_path"

  assert_relative_symlink_target_lookups
  # The one lookup the manifest cannot reproduce: a relative target that leaves
  # the runfiles tree can only be resolved against a materialized runfiles
  # directory, whose existence the manifest does not imply. Bazel does not
  # generate such a runfile.
  assert_no_rlocation _main/pkg/escaping
}

test_directory_based_relative_symlink_targets() {
  # MSYS2 may materialize symlinks as copies, which does not preserve relative
  # targets.
  if is_windows; then
    return 0
  fi

  tmpdir="$TEST_TMPDIR/test_directory_based_relative_symlink_targets"
  rm -rf "$tmpdir"
  write_relative_symlink_target_layout "$tmpdir"

  export RUNFILES_DIR="$tmpdir/foo.runfiles"
  export RUNFILES_MANIFEST_FILE=
  . "$runfiles_lib_path"

  assert_relative_symlink_target_lookups
  assert_rlocation_contents _main/pkg/escaping outside
}

# The documented initialization snippet, taken from the library's own header,
# and the library have to work on a host without awk: the snippet's awk attempt
# fails and its shell loop takes over, and the library keeps its shell loops.
test_survives_without_awk() {
  tmpdir="$TEST_TMPDIR/test_survives_without_awk"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir/lib/rules_shell/shell/runfiles"
  cp "$runfiles_lib_path" "$tmpdir/lib/rules_shell/shell/runfiles/runfiles.sh"
  touch "$tmpdir/f"
  printf 'r/f %s\nrules_shell/shell/runfiles/runfiles.sh %s\n' "$tmpdir/f" \
    "$tmpdir/lib/rules_shell/shell/runfiles/runfiles.sh" > "$tmpdir/manifest"
  {
    echo '#!/bin/sh'
    sed -n '/^# *# --- begin runfiles.sh initialization v4 ---/,/^# *# --- end runfiles.sh initialization v4 ---/p' \
      "$runfiles_lib_path" | sed 's/^#       //'
    echo 'rlocation r/f'
  } > "$tmpdir/script.sh"
  sh_path=$(command -v sh)

  actual=$(RUNFILES_DIR='' RUNFILES_MANIFEST_FILE="$tmpdir/manifest" \
    PATH=/nonexistent "$sh_path" "$tmpdir/script.sh")
  [ "$actual" = "$tmpdir/f" ] || fail "expected $tmpdir/f without awk, got: $actual"
}

# The snippet sources the first library it finds, so a library that fails to
# load has to abort the script rather than leave it without rlocation.
test_init_snippet_aborts_when_library_fails() {
  tmpdir="$TEST_TMPDIR/test_init_snippet_aborts_when_library_fails"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir/broken/rules_shell/shell/runfiles"
  echo 'return 1' > "$tmpdir/broken/rules_shell/shell/runfiles/runfiles.sh"
  {
    echo '#!/bin/sh'
    sed -n '/^# *# --- begin runfiles.sh initialization v4 ---/,/^# *# --- end runfiles.sh initialization v4 ---/p' \
      "$runfiles_lib_path" | sed 's/^#       //'
    echo 'echo reached'
  } > "$tmpdir/script.sh"

  if output=$(RUNFILES_DIR="$tmpdir/broken" RUNFILES_MANIFEST_FILE='' sh "$tmpdir/script.sh" 2>&1); then
    fail "expected the snippet to abort, got: $output"
  fi
  [ "${output#*reached}" = "$output" ] || fail "expected the script not to run past the snippet"
}

# awk takes an operand of the form name=value as an assignment, so a manifest
# path shaped like that has to reach it some other way, in the library and in
# the snippet alike.
test_manifest_path_with_equals_sign() {
  tmpdir="$TEST_TMPDIR/test_manifest_path_with_equals_sign"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir/lib/rules_shell/shell/runfiles"
  cp "$runfiles_lib_path" "$tmpdir/lib/rules_shell/shell/runfiles/runfiles.sh"
  touch "$tmpdir/f"
  printf 'r/f %s\nrules_shell/shell/runfiles/runfiles.sh %s\n' "$tmpdir/f" \
    "$tmpdir/lib/rules_shell/shell/runfiles/runfiles.sh" > "$tmpdir/out=1.manifest"

  export RUNFILES_DIR=
  export RUNFILES_MANIFEST_FILE="$tmpdir/out=1.manifest"
  . "$runfiles_lib_path"
  [ "$(rlocation r/f)" = "$tmpdir/f" ] || fail "expected a lookup through out=1.manifest, got: $(rlocation r/f)"

  {
    echo '#!/bin/sh'
    sed -n '/^# *# --- begin runfiles.sh initialization v4 ---/,/^# *# --- end runfiles.sh initialization v4 ---/p' \
      "$runfiles_lib_path" | sed 's/^#       //'
    echo 'rlocation r/f'
  } > "$tmpdir/script.sh"
  actual=$(sh "$tmpdir/script.sh")
  [ "$actual" = "$tmpdir/f" ] || fail "expected the snippet to find the library through out=1.manifest, got: $actual"
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
    test_init_derives_runfiles_dir_from_legacy_location
    test_directory_based_runfiles_with_repo_mapping_from_main
    test_directory_based_runfiles_with_repo_mapping_from_other_repo
    test_directory_based_runfiles_with_repo_mapping_from_extension_repo
    test_manifest_based_runfiles_with_repo_mapping_from_main
    test_manifest_based_runfiles_with_repo_mapping_from_other_repo
    test_manifest_based_runfiles_with_repo_mapping_from_extension_repo
    test_directory_based_runfiles_with_repo_mapping_from_module_root_repo
    test_directory_based_envvars
    test_rlocation_auto_detects_source_repo_under_bash
    test_runfiles_current_repository_under_set_u
    test_current_repository_directory_based
    test_current_repository_manifest_based
    test_current_repository_directory_and_manifest_based
    test_platform_detection_without_uname
    test_manifest_prefix_respects_path_boundaries
    test_manifest_lookup_case_insensitive
    test_manifest_based_relative_symlink_targets
    test_directory_based_relative_symlink_targets
    test_awk_on_by_default
    test_awk_disabled_by_env
    test_awk_enabled_by_program
    test_awk_falls_back_when_program_is_missing
    test_survives_without_awk
    test_init_snippet_aborts_when_library_fails
    test_manifest_path_with_equals_sign
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
