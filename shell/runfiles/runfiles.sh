# shellcheck shell=sh
# shellcheck disable=SC3043
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

# Runfiles lookup library for Bazel-built shell binaries and tests, in POSIX
# shell. Forks nothing unless asked to.
#
# This file is the implementation behind both @rules_shell//shell/runfiles
# entry points. Sourced directly, it is the pure POSIX library. runfiles.bash,
# next to it, is a thin wrapper that sources it with awk enabled by default,
# for scripts written against the grep-based bash library that Bazel shipped
# ("the historical bash library" below). It exposes that library's public API
# -- rlocation, runfiles_export_envvars, runfiles_current_repository and
# runfiles_rlocation_checked -- and passes its test suite. Under bash it keeps
# the bash-specific behavior too: the caller's repository is detected from
# BASH_SOURCE, and the functions are exported with `export -f`. Under any
# other shell, runfiles_current_repository needs the caller's script path as
# its argument, rlocation without a second argument assumes the main
# repository, and every script has to source the library itself.
#
# README.md in this directory covers what a lookup costs, the opt-in manifest
# index, the launcher, and measurements.
#
# ENVIRONMENT
#
# Read when the library is sourced, so a setting has to be in the environment
# by then: the rule's `env` attribute, --test_env / --action_env, or an export
# before the initialization snippet.
#
# - RUNFILES_DIR, RUNFILES_MANIFEST_FILE: where the runfiles are, as set by
#   Bazel or by a parent's runfiles_export_envvars; derived from $0 when
#   neither is set. The manifest is used whenever it names an existing file.
# - RUNFILES_LIB_DEBUG=1: print a diagnostic to stderr for every lookup.
# - AWK: search manifests with this awk program, one process per lookup,
#   instead of shell loops. Expanded unquoted, so `busybox awk` works. A
#   program that cannot be found leaves the shell loops in place.
# - RULES_SHELL_RUNFILES_USE_AWK=1: the same, with `awk` from PATH.
#   RULES_SHELL_RUNFILES_USE_AWK=0: keep the shell loops even when sourced
#   through runfiles.bash. Neither has an effect when AWK is set.
# - RULES_SHELL_RUNFILES_CACHE=1: parse the manifest once, at source time, into
#   an in-memory index instead of scanning it per lookup. See README.md.
# - RULES_SHELL_RUNFILES_PORTABLE_INDEX=1: use the portable key mangling and
#   case folding even under bash. For the test suite.
#
# Exported for child processes: RUNFILES_DIR, RUNFILES_MANIFEST_FILE and
# JAVA_RUNFILES (by runfiles_export_envvars); RUNFILES_REPO_MAPPING, the path
# of the repository mapping manifest; the platform detection results
# _RLOCATION_ISABS_WINDOWS and _RLOCATION_CASE_INSENSITIVE; and the internal
# configuration _RULES_SHELL_RUNFILES_INDEX_OK, _RULES_SHELL_RUNFILES_INDEX_FOLD,
# _RULES_SHELL_RUNFILES_AWK and _RULES_SHELL_RUNFILES_NL, so that a bash process
# inheriting the functions through `export -f` sees the same settings.
#
# USAGE
#
# 1.  Depend on this runfiles library from your build rule:
#
#       sh_binary(
#           name = "my_binary",
#           ...
#           deps = ["@rules_shell//shell/runfiles"],
#       )
#
# 2.  Source the runfiles library. It defines rlocation, which you would need
#     to look up its own location, so insert this snippet at the top of your
#     main script:
#
#       # --- begin runfiles.sh initialization v1 ---
#       # Copy-pasted from the Bazel POSIX shell runfiles library v1.
#       set +e; f=rules_shell/shell/runfiles/runfiles.sh; _rf_p=
#       _rf_d() { [ -f "$1/$f" ] && _rf_p="$1/$f"; }
#       _rf_m() { [ -f "$1" ] || return 1; if [ -n "${AWK:-}" ] || [ "${RULES_SHELL_RUNFILES_USE_AWK:-}" = 1 ]; then \
#         _rf_p=$(${AWK:-awk} -v k="$f " 'index($0,k)==1{print substr($0,length(k)+1);m=1;exit}END{exit !m}' "$1" 2>/dev/null) && return; fi; \
#         while IFS= read -r _rf_l || [ -n "$_rf_l" ]; do \
#         case "$_rf_l" in "$f "*) _rf_p="${_rf_l#"$f "}"; return;; esac; done < "$1"; return 1; }
#       _rf_d "${RUNFILES_DIR:-/dev/null}" || _rf_m "${RUNFILES_MANIFEST_FILE:-/dev/null}" || \
#         _rf_d "$0.runfiles" || _rf_m "$0.runfiles_manifest" || _rf_m "$0.exe.runfiles_manifest" || \
#         { echo>&2 "ERROR: cannot find $f"; exit 1; }
#       # shellcheck disable=SC1090
#       . "$_rf_p"; f=; unset -f _rf_d _rf_m; unset _rf_l _rf_p; set -e
#       # --- end runfiles.sh initialization v1 ---
#
#     `.` on a missing file is fatal in a POSIX shell, so the snippet resolves
#     each candidate location to an existing path before sourcing it, in the
#     order the bash snippet tries them: `_rf_d` checks a runfiles directory,
#     `_rf_m` searches a manifest, with awk when AWK or
#     RULES_SHELL_RUNFILES_USE_AWK=1 says so and a shell loop otherwise.
#     `rules_shell/shell/runfiles/runfiles.sh` is where the target
#     @rules_shell//shell/runfiles installs this file, whatever the
#     repository's canonical name is.
#
# 3.  Use rlocation to look up runfile paths.
#
#       cat "$(rlocation my_workspace/path/to/my/data.txt)"
#

# --- Initialization ---

if ! [ -d "${RUNFILES_DIR:-/dev/null}" ] && ! [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
  if [ -f "$0.runfiles_manifest" ]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
  elif [ -f "$0.runfiles/MANIFEST" ]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
  elif [ -f "$0.runfiles/rules_shell/shell/runfiles/runfiles.sh" ]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi

# Detects whether we are running in a Windows shell environment (MSYS2, MinGW
# or Cygwin) and sets _RLOCATION_ISABS_WINDOWS / _RLOCATION_CASE_INSENSITIVE
# accordingly. The historical bash library shells out to `uname -s | tr ...`
# for this; here it is done with the environment and shell builtins only.
#
# Signals, in order of reliability:
#   1. MSYSTEM is set by every MSYS2, MinGW and Git-for-Windows shell.
#   2. OSTYPE is set by bash to "cygwin" / "msys" (absent under dash).
#   3. /proc/version names the runtime on Cygwin and MSYS2 ("CYGWIN_NT-...",
#      "MSYS_NT-...", "MINGW64_NT-..."). If the file exists and does not name
#      one of those, we are on a Unix-like system and must not consult the
#      Windows environment variables below -- WSL, for instance, can inherit
#      WINDIR from the host through WSLENV.
#   4. Only when there is no /proc at all (so, not Linux and not Cygwin/MSYS)
#      do WINDIR / SystemRoot indicate a Windows environment.
#
# $1 optionally overrides the /proc/version path so that the Windows branches
# can be covered by tests on non-Windows hosts.
__runfiles_detect_platform() {
  _rf_dp_procver_file="${1:-/proc/version}"
  _rf_dp_win=
  _rf_dp_line=

  if [ -n "${MSYSTEM:-}" ]; then
    _rf_dp_win=1
  else
    # OSTYPE is a bash variable and simply expands to the empty string under a
    # POSIX shell, which is why it is read through ${OSTYPE:-}. Consulting it
    # costs nothing and catches a Cygwin bash that has no MSYSTEM and no /proc.
    # shellcheck disable=SC3028
    case "${OSTYPE:-}" in
      cygwin*|msys*|win32*) _rf_dp_win=1 ;;
    esac
  fi

  if [ -z "$_rf_dp_win" ]; then
    if [ -r "$_rf_dp_procver_file" ]; then
      IFS= read -r _rf_dp_line < "$_rf_dp_procver_file" || :
      case "$_rf_dp_line" in
        *CYGWIN*|*Cygwin*|*cygwin*|*MSYS*|*Msys*|*msys*|*MINGW*|*Mingw*|*mingw*)
          _rf_dp_win=1
          ;;
      esac
    elif [ -n "${WINDIR:-}${SystemRoot:-}${SYSTEMROOT:-}" ]; then
      _rf_dp_win=1
    fi
  fi

  if [ -n "$_rf_dp_win" ]; then
    export _RLOCATION_ISABS_WINDOWS=1
    export _RLOCATION_CASE_INSENSITIVE=1
  else
    export _RLOCATION_ISABS_WINDOWS=
    export _RLOCATION_CASE_INSENSITIVE=
  fi

  _rf_dp_procver_file=
  _rf_dp_win=
  _rf_dp_line=
}

__runfiles_detect_platform

# Literal newline for use in case patterns and string comparisons.
_RULES_SHELL_RUNFILES_NL='
'
export _RULES_SHELL_RUNFILES_NL

# --- Internal helper functions ---

# Print a diagnostic to stderr under RUNFILES_LIB_DEBUG=1. Written as an `if`
# rather than `[ ... ] && echo`, so that it never returns 1 into a caller's
# `set -e`.
__runfiles_debug() {
  if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
    echo >&2 "$@"
  fi
}

# Returns 0 if $1 is an absolute path, 1 otherwise.
__runfiles_is_abs() {
  case "$1" in
    /[!/]*) return 0 ;;
  esac
  if [ -n "$_RLOCATION_ISABS_WINDOWS" ]; then
    case "$1" in
      # Spelled out rather than written as ranges: bash before 5.0 collates
      # bracket ranges by locale, so [a-z] can match characters outside ASCII.
      [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz]:[/\\]*) return 0 ;;
    esac
  fi
  return 1
}

# Replace one or more consecutive backslashes with a single forward slash.
# Equivalent to: sed 's|\\\\*|/|g'
__runfiles_normalize_backslashes() {
  _rf_nb_in="$1"
  _rf_nb_out=""
  _rf_nb_bs=false
  while [ -n "$_rf_nb_in" ]; do
    _rf_nb_c="${_rf_nb_in%"${_rf_nb_in#?}"}"
    _rf_nb_in="${_rf_nb_in#?}"
    case "$_rf_nb_c" in
      "\\")
        if [ "$_rf_nb_bs" = false ]; then
          _rf_nb_out="${_rf_nb_out}/"
          _rf_nb_bs=true
        fi
        ;;
      *)
        _rf_nb_bs=false
        _rf_nb_out="${_rf_nb_out}${_rf_nb_c}"
        ;;
    esac
  done
  printf '%s' "$_rf_nb_out"
}

# Replace all occurrences of $2 in $1 with $3, into _rf_gs_out. Stored rather
# than printed so that encoding and decoding escaped manifest keys, which take
# several passes, do not fork per pass.
# Equivalent to: ${1//$2/$3} (bash-only).
__runfiles_gsub() {
  _rf_gs_in="$1"
  _rf_gs_old="$2"
  _rf_gs_new="$3"
  _rf_gs_out=""
  # An empty needle would loop forever: `*""*` matches unconditionally and the
  # parameter expansion strips nothing.
  if [ -z "$_rf_gs_old" ]; then
    _rf_gs_out="$_rf_gs_in"
    return 0
  fi
  while :; do
    case "$_rf_gs_in" in
      *"$_rf_gs_old"*)
        _rf_gs_out="${_rf_gs_out}${_rf_gs_in%%"$_rf_gs_old"*}${_rf_gs_new}"
        _rf_gs_in="${_rf_gs_in#*"$_rf_gs_old"}"
        ;;
      *)
        _rf_gs_out="${_rf_gs_out}${_rf_gs_in}"
        break
        ;;
    esac
  done
}

# Compute the wildcard prefix for repo mapping lookups, into _rf_cp_out.
# Replaces the rightmost run of safe chars ([-a-zA-Z0-9_.]) that follows a
# separator (non-safe char) with `*`, preserving any trailing non-safe chars.
# Leaves the input unchanged when there is no non-safe-followed-by-safe pair
# (e.g. `rules_shell+`, `protobuf+`, and other bzlmod module root names).
# Equivalent to: sed 's/\(.*[^-a-zA-Z0-9_.]\)[-a-zA-Z0-9_.]\{1,\}/\1*/'
#
# The result is stored rather than printed so that rlocation does not fork a
# subshell for it on every lookup.
__runfiles_compute_repo_prefix() {
  _rf_cp_repo="$1"
  # Phase 1: peel any trailing non-safe chars into $suffix. Sed keeps these
  # after the star (e.g. `my_module++ext+` -> `my_module++*+`).
  _rf_cp_suffix=""
  _rf_cp_head="$_rf_cp_repo"
  while [ -n "$_rf_cp_head" ]; do
    _rf_cp_last="${_rf_cp_head#"${_rf_cp_head%?}"}"
    case "$_rf_cp_last" in
      [-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.]) break ;;
      *)
        _rf_cp_suffix="${_rf_cp_last}${_rf_cp_suffix}"
        _rf_cp_head="${_rf_cp_head%?}"
        ;;
    esac
  done
  # Phase 2: peel the trailing safe run off $head. We only need to know
  # whether we stripped at least one safe char (sed requires ≥1).
  _rf_cp_stripped_safe=0
  while [ -n "$_rf_cp_head" ]; do
    _rf_cp_last="${_rf_cp_head#"${_rf_cp_head%?}"}"
    case "$_rf_cp_last" in
      [-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.])
        _rf_cp_stripped_safe=1
        _rf_cp_head="${_rf_cp_head%?}"
        ;;
      *) break ;;
    esac
  done
  # Sed requires BOTH ≥1 safe chars AND a non-safe char before them.
  if [ "$_rf_cp_stripped_safe" -eq 0 ] || [ -z "$_rf_cp_head" ]; then
    _rf_cp_out="$_rf_cp_repo"
    return 0
  fi
  _rf_cp_out="${_rf_cp_head}*${_rf_cp_suffix}"
}

# --- Manifest index ---
#
# With RULES_SHELL_RUNFILES_CACHE=1, sourcing this library parses the manifest
# once into a set of variables named `_rf_ci<generation>_<mangled key>`, read
# and written through `eval`, and a lookup becomes O(1) in the manifest's size.
# README.md explains the design; the invariants the code below relies on are:
#   - Only the sourcing shell builds the index. A lookup runs in a `$(...)`
#     subshell, which inherits variables but cannot hand anything back.
#   - Values reach `eval` as a variable *reference*, never as text, so nothing
#     a manifest contains is evaluated as shell source.
#   - Escaped entries (keys with a space or newline) and keys the mangling
#     cannot represent are left out, and such lookups scan. Neither can be a
#     path prefix of an indexed key, since the mangling accepts a key only if
#     every prefix of it is acceptable too, which is what lets
#     __runfiles_find_prefix walk a path's prefixes through the index without
#     missing a longer match.

# Configuration, exported alongside _RLOCATION_CASE_INSENSITIVE so that a
# script which inherits the library's functions through `export -f` rather than
# sourcing it still sees the same settings. The index itself is never exported:
# it would have to be copied into the environment of every process the script
# starts, and a process that inherits the functions can parse its own.
_RULES_SHELL_RUNFILES_INDEX_OK=    # source-time caching is possible and wanted
_RULES_SHELL_RUNFILES_INDEX_FOLD=  # the mangling can fold case cheaply

# Mutable state, never exported. Every read below tolerates it being unset, so
# that a process which inherits only the functions starts without believing in
# an index that its parent holds.
_rf_ix_file=       # manifest the current index was built from, empty if none
_rf_ix_ci=         # _RLOCATION_CASE_INSENSITIVE that index was built under
_rf_ix_pfx=        # variable-name prefix of the current index
_rf_ix_gen=${_rf_ix_gen:-0}  # bumped per build, so replacing an index is O(1)
                   # rather than a walk that unsets every variable of the old
                   # one. Carried over when the library is sourced twice in one
                   # shell, so that the second index cannot read the first's
                   # variables back.
_rf_rc_memo_key=   # inputs the memoized caller repository was resolved from
_rf_rc_memo_val=   # that caller's repository (see rlocation)

# RULES_SHELL_RUNFILES_CACHE=1 turns the source-time work on, for a script that
# resolves enough paths to amortize a parse.
case "${RULES_SHELL_RUNFILES_CACHE:-}" in
  1) _RULES_SHELL_RUNFILES_INDEX_OK=1 ;;
esac

# RULES_SHELL_RUNFILES_PORTABLE_INDEX forces the pure-POSIX key mangling and
# case folding even under bash, so that the test suite covers both variants on
# one host.
#
# Case folding decides whether an index is possible at all on a
# case-insensitive platform: every key has to be lowercased on the way in, and
# without bash's ${var,,} that is a character-at-a-time loop over the whole
# manifest, which costs more than the index wins back. macOS still ships bash
# 3.2, which has no ${var,,}; Windows, the only case-insensitive platform,
# resolves its sh_toolchain to MSYS2 bash 5.
_rf_ix_bash=
if [ -n "${BASH_VERSION:-}" ] && [ -z "${RULES_SHELL_RUNFILES_PORTABLE_INDEX:-}" ]; then
  _rf_ix_bash=1
  case "$BASH_VERSION" in
    [0-3].*) ;;
    *) _RULES_SHELL_RUNFILES_INDEX_FOLD=1 ;;
  esac
fi
export _RULES_SHELL_RUNFILES_INDEX_OK
export _RULES_SHELL_RUNFILES_INDEX_FOLD

# Convert ASCII uppercase to lowercase, into _rf_tl_out. Stored rather than
# printed so that no caller forks for it: the case-insensitive manifest scans
# call it once per line.
#
# Return 0 iff the first ${#2} characters of $1, lowercased, equal $2, which
# must already be lowercase: a prefix test that does not fold the whole line.
#
# Under bash 4 and later -- which is what Windows, the one case-insensitive
# platform, runs -- ${var,,} folds a string in one builtin operation. The
# portable variants loop over the characters; folding a string of length N
# costs O(N^2) in most shells, since every append copies the output, which is
# why the prefix test exists as its own loop that stops at the first mismatch.
if [ -n "$_RULES_SHELL_RUNFILES_INDEX_FOLD" ]; then
  # ${var:offset:length} is bash 3 syntax and ${var,,} bash 4; both stay
  # inside `eval` so that no other shell has to parse them.
  eval '__runfiles_tolower() { _rf_tl_out="${1,,}"; }'
  eval '__runfiles_line_starts_with_ci() {
    _rf_lsw_head="${1:0:${#2}}"
    [ "${_rf_lsw_head,,}" = "$2" ]
  }'
else
  __runfiles_tolower() {
    _rf_tl_in="$1"
    _rf_tl_out=""
    while [ -n "$_rf_tl_in" ]; do
      _rf_tl_c="${_rf_tl_in%"${_rf_tl_in#?}"}"
      _rf_tl_in="${_rf_tl_in#?}"
      case "$_rf_tl_c" in
        A) _rf_tl_c=a;; B) _rf_tl_c=b;; C) _rf_tl_c=c;; D) _rf_tl_c=d;;
        E) _rf_tl_c=e;; F) _rf_tl_c=f;; G) _rf_tl_c=g;; H) _rf_tl_c=h;;
        I) _rf_tl_c=i;; J) _rf_tl_c=j;; K) _rf_tl_c=k;; L) _rf_tl_c=l;;
        M) _rf_tl_c=m;; N) _rf_tl_c=n;; O) _rf_tl_c=o;; P) _rf_tl_c=p;;
        Q) _rf_tl_c=q;; R) _rf_tl_c=r;; S) _rf_tl_c=s;; T) _rf_tl_c=t;;
        U) _rf_tl_c=u;; V) _rf_tl_c=v;; W) _rf_tl_c=w;; X) _rf_tl_c=x;;
        Y) _rf_tl_c=y;; Z) _rf_tl_c=z;;
      esac
      _rf_tl_out="${_rf_tl_out}${_rf_tl_c}"
    done
  }
  __runfiles_line_starts_with_ci() {
    _rf_lsw_line="$1"
    _rf_lsw_lpfx="$2"
    while [ -n "$_rf_lsw_lpfx" ]; do
      [ -z "$_rf_lsw_line" ] && return 1
      _rf_lsw_pc="${_rf_lsw_lpfx%"${_rf_lsw_lpfx#?}"}"
      _rf_lsw_lpfx="${_rf_lsw_lpfx#?}"
      _rf_lsw_lc="${_rf_lsw_line%"${_rf_lsw_line#?}"}"
      _rf_lsw_line="${_rf_lsw_line#?}"
      case "$_rf_lsw_lc" in
        A) _rf_lsw_lc=a;; B) _rf_lsw_lc=b;; C) _rf_lsw_lc=c;; D) _rf_lsw_lc=d;;
        E) _rf_lsw_lc=e;; F) _rf_lsw_lc=f;; G) _rf_lsw_lc=g;; H) _rf_lsw_lc=h;;
        I) _rf_lsw_lc=i;; J) _rf_lsw_lc=j;; K) _rf_lsw_lc=k;; L) _rf_lsw_lc=l;;
        M) _rf_lsw_lc=m;; N) _rf_lsw_lc=n;; O) _rf_lsw_lc=o;; P) _rf_lsw_lc=p;;
        Q) _rf_lsw_lc=q;; R) _rf_lsw_lc=r;; S) _rf_lsw_lc=s;; T) _rf_lsw_lc=t;;
        U) _rf_lsw_lc=u;; V) _rf_lsw_lc=v;; W) _rf_lsw_lc=w;; X) _rf_lsw_lc=x;;
        Y) _rf_lsw_lc=y;; Z) _rf_lsw_lc=z;;
      esac
      [ "$_rf_lsw_lc" != "$_rf_lsw_pc" ] && return 1
    done
    return 0
  }
fi

# A set AWK, or RULES_SHELL_RUNFILES_USE_AWK=1, searches manifests with awk
# rather than a shell `read` loop, the way the historical bash library searched
# them with grep: a fork per lookup, but one that reads the file in bulk, so
# the cost stops growing with the manifest. AWK names the program, `awk` on
# PATH when only the switch is set, and is expanded unquoted where it runs, as
# that library expanded it. The index, when built, is still consulted first.
_RULES_SHELL_RUNFILES_AWK=
if [ -n "${AWK:-}" ] || [ "${RULES_SHELL_RUNFILES_USE_AWK:-}" = 1 ]; then
  _RULES_SHELL_RUNFILES_AWK="${AWK:-awk}"
  if ! command -v "${_RULES_SHELL_RUNFILES_AWK%% *}" >/dev/null 2>&1; then
    __runfiles_debug "WARNING[runfiles.sh]: '$_RULES_SHELL_RUNFILES_AWK' cannot be found; searching manifests with shell loops"
    _RULES_SHELL_RUNFILES_AWK=
  fi
fi
export _RULES_SHELL_RUNFILES_AWK

# Run the configured awk program: $1 is the program, $2 the file to search and
# every further argument a parameter, which the program reads from ARGV[2],
# ARGV[3], ... in its BEGIN block and blanks, so that awk does not open it as a
# file. Parameters travel as arguments rather than through `-v`, which would
# process the backslashes of an escaped key.
#
# awk runs in the C locale: a path is a byte string, gawk warns on stderr about
# bytes that are not valid in a UTF-8 locale, and ASCII-only case folding is
# what the shell loops do too.
__runfiles_awk() {
  LC_ALL=C $_RULES_SHELL_RUNFILES_AWK "$@"
}

# Mangle the manifest key $1 into the tail of an index variable name, in
# _rf_ck. Returns 1 for a key that cannot be represented, whose lookups then
# fall back to scanning.
#
# The mapping stays injective by escaping `_` first: every literal `_` becomes
# `_u` before `/`, `.`, `-` and `+` introduce `_s`, `_d`, `_m` and `_p`.
# Without that, `a/b`, `a.b` and `a_b` would collide on a single entry.
#
# The accepted characters are spelled out rather than written as ranges: bash
# before 5.0 collates bracket ranges by locale, so under a UTF-8 locale [A-Z]
# can match an accented letter, which would then reach `eval` as part of a
# variable name and fail the assignment.
#
# _RLOCATION_CASE_INSENSITIVE is read per call rather than baked in at source
# time, because the rest of the library reads it per call too and tests set it
# after sourcing to exercise the Windows path on a Unix host.
if [ -n "$_rf_ix_bash" ]; then
  # bash substitutes one character class per builtin operation; the portable
  # variant below costs three to five times as much on a 10k-line manifest.
  # Case folding goes through __runfiles_tolower: one operation on bash 4, a
  # loop on bash 3, which __runfiles_index_ready keeps away from
  # case-insensitive lookups anyway.
  # shellcheck disable=SC3060  # guarded by the BASH_VERSION test above
  __runfiles_cache_key() {
    case "$1" in *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_/.+-]*) return 1 ;; esac
    if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
      __runfiles_tolower "$1"
      _rf_ck="$_rf_tl_out"
    else
      _rf_ck="$1"
    fi
    _rf_ck="${_rf_ck//_/_u}"
    _rf_ck="${_rf_ck//\//_s}"
    _rf_ck="${_rf_ck//./_d}"
    _rf_ck="${_rf_ck//-/_m}"
    _rf_ck="${_rf_ck//+/_p}"
  }
else
  # The loop advances to the next character needing escaping rather than
  # walking the key one character at a time: a runfiles path has a handful of
  # separators among dozens of ordinary characters, and __runfiles_gsub would
  # have to make a full pass per character class.
  __runfiles_cache_key() {
    case "$1" in *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_/.+-]*) return 1 ;; esac
    _rf_ck_in="$1"
    _rf_ck=
    while :; do
      case "$_rf_ck_in" in
        *[_/.+-]*)
          _rf_ck_head="${_rf_ck_in%%[_/.+-]*}"
          _rf_ck_in="${_rf_ck_in#"$_rf_ck_head"}"
          _rf_ck_c="${_rf_ck_in%"${_rf_ck_in#?}"}"
          _rf_ck_in="${_rf_ck_in#?}"
          case $_rf_ck_c in
            _) _rf_ck_c=_u ;;
            /) _rf_ck_c=_s ;;
            .) _rf_ck_c=_d ;;
            -) _rf_ck_c=_m ;;
            +) _rf_ck_c=_p ;;
          esac
          _rf_ck="${_rf_ck}${_rf_ck_head}${_rf_ck_c}"
          ;;
        *)
          _rf_ck="${_rf_ck}${_rf_ck_in}"
          break
          ;;
      esac
    done
  }
fi

# Parse the manifest $1 into a fresh index, replacing any index already built.
# Leaves the library without an index -- every lookup then scans, which is
# always correct -- when $1 is not a file, when caching is off, or when keys
# would have to be folded on a shell that cannot fold them cheaply.
__runfiles_index_build() {
  _rf_ix_file=
  [ -n "${_RULES_SHELL_RUNFILES_INDEX_OK:-}" ] || return 0
  [ -f "${1:-/dev/null}" ] || return 0
  if [ -n "$_RLOCATION_CASE_INSENSITIVE" ] && [ -z "${_RULES_SHELL_RUNFILES_INDEX_FOLD:-}" ]; then
    return 0
  fi
  _rf_ix_gen=$((${_rf_ix_gen:-0} + 1))
  _rf_ix_pfx="_rf_ci${_rf_ix_gen}_"
  __runfiles_debug "INFO[runfiles.sh]: indexing runfiles manifest ($1)"
  while IFS= read -r _rf_ib_line || [ -n "$_rf_ib_line" ]; do
    _rf_ib_key="${_rf_ib_line%% *}"
    # Rejects blank lines and escaped entries, which begin with a space.
    [ -n "$_rf_ib_key" ] || continue
    case "$_rf_ib_line" in *" "*) ;; *) continue ;; esac
    _rf_ib_val="${_rf_ib_line#* }"
    __runfiles_cache_key "$_rf_ib_key" || continue
    # An entry with an empty value is stored as a lone newline rather than
    # skipped, so that it still claims its key: a later duplicate with a value
    # must not take over what the scan, stopping at the first entry, reports as
    # empty. A manifest value is a path on a single line, so a lone newline is
    # never one.
    [ -n "$_rf_ib_val" ] || _rf_ib_val="$_RULES_SHELL_RUNFILES_NL"
    # ${name=value} assigns only when name is unset, so the first entry for a
    # key wins, matching the `grep -m1` the historical bash library does.
    eval ": \"\${${_rf_ix_pfx}${_rf_ck}=\$_rf_ib_val}\""
  done < "$1"
  _rf_ix_file="$1"
  _rf_ix_ci="$_RLOCATION_CASE_INSENSITIVE"
}

# Return 0 if lookups against the manifest $1 can be served from the index.
#
# An index is never built from here: a lookup usually runs in a command
# substitution's subshell, so it would be rebuilt per lookup and cost more than
# scanning. A script that points RUNFILES_MANIFEST_FILE at another manifest
# after sourcing therefore goes back to scanning, and can call
# __runfiles_index_build itself to index the new one, as
# runfiles_export_envvars does for the manifest it promotes.
__runfiles_index_ready() {
  [ -n "${_rf_ix_file:-}" ] && [ "$1" = "$_rf_ix_file" ] || return 1
  # Keys are folded on the way into the index, so an index is only usable in
  # the case-sensitivity mode it was built under.
  [ "$_RLOCATION_CASE_INSENSITIVE" = "${_rf_ix_ci:-}" ]
}

# Find the first line in $2 whose key is exactly $1 and store the value
# (everything after the key and the separating space) in _rf_fl_val.
# $1 must already be in manifest (escaped) form.
# On Windows (_RLOCATION_CASE_INSENSITIVE=1), matching is case-insensitive
# but the value is returned with its original casing.
#
# The result is stored rather than printed so that callers do not fork a
# subshell per lookup.
__runfiles_find_line() {
  _rf_fl_val=

  # An escaped search key starts with a space, so __runfiles_cache_key rejects
  # it and the lookup drops through to the scan, which is where escaped entries
  # live.
  if __runfiles_index_ready "$2" && __runfiles_cache_key "$1"; then
    eval "_rf_fl_val=\"\${${_rf_ix_pfx}${_rf_ck}-}\""
    [ -n "$_rf_fl_val" ] || return 1
    # A listed entry whose value is empty, which the scan reports the same way.
    [ "$_rf_fl_val" = "$_RULES_SHELL_RUNFILES_NL" ] && _rf_fl_val=
    return 0
  fi

  if [ -n "${_RULES_SHELL_RUNFILES_AWK:-}" ]; then
    __runfiles_find_line_awk "$1" "$2"
  else
    __runfiles_find_line_scan "$1" "$2"
  fi
}

# The awk search behind __runfiles_find_line.
__runfiles_find_line_awk() {
  _rf_fl_val=$(__runfiles_awk '
    BEGIN { k = ARGV[2]; c = ARGV[3]; ARGV[2] = ARGV[3] = ""
            n = length(k); if (c) k = tolower(k) }
    { h = substr($0, 1, n); if (c) h = tolower(h)
      if (h == k) { print substr($0, n + 1); f = 1; exit } }
    END { exit !f }' "$2" "$1 " "$_RLOCATION_CASE_INSENSITIVE")
}

# The shell-loop search behind __runfiles_find_line: a single quoted `case`
# rejects a line, and nothing is copied out of one until it matches.
__runfiles_find_line_scan() {
  _rf_fl_pfx_sp="$1 "
  if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
    __runfiles_tolower "$_rf_fl_pfx_sp"
    _rf_fl_lpfx="$_rf_tl_out"
    _rf_fl_plen=${#_rf_fl_pfx_sp}
    while IFS= read -r _rf_fl_line || [ -n "$_rf_fl_line" ]; do
      if __runfiles_line_starts_with_ci "$_rf_fl_line" "$_rf_fl_lpfx"; then
        _rf_fl_val="$_rf_fl_line"
        _rf_fl_i=0
        while [ "$_rf_fl_i" -lt "$_rf_fl_plen" ]; do
          _rf_fl_val="${_rf_fl_val#?}"
          _rf_fl_i=$((_rf_fl_i + 1))
        done
        return 0
      fi
    done < "$2"
  else
    while IFS= read -r _rf_fl_line || [ -n "$_rf_fl_line" ]; do
      case "$_rf_fl_line" in
        "${_rf_fl_pfx_sp}"*)
          _rf_fl_val="${_rf_fl_line#"${_rf_fl_pfx_sp}"}"
          return 0
          ;;
      esac
    done < "$2"
  fi
  return 1
}

# Find the entry in $2 for the longest proper `/`-separated path prefix of the
# rlocation path $1. This resolves a file that is only reachable through a
# directory runfile, since a manifest lists the directory and not its contents.
#
# Resolving every prefix in one pass is a performance requirement rather than a
# style choice. The historical bash library greps the manifest once per
# candidate prefix, which stays cheap because grep reads the file in bulk,
# while here every scan is a `read` loop costing microseconds per line.
#
# Comparison happens in the manifest's own (escaped) domain, so that no line
# has to be decoded during the scan; only the winning entry is decoded, by the
# caller. On Windows matching is case-insensitive but values are returned with
# their original casing.
#
# Args: $1=rlocation path $2=manifest $3=escaped form of $1
#       $4=non-empty iff $1 has to be looked up in escaped form
# Sets:
#   _rf_fp_val     the matched value, still escaped
#   _rf_fp_esc     non-empty iff the matched entry was an escaped one
#   _rf_fp_suffix  the part of $1 below the matched key, to append to the value
# Returns 1 if no prefix matched.
__runfiles_find_prefix() {
  _rf_fp_path="$1"
  _rf_fp_epath="$3"
  _rf_fp_want_esc="$4"
  _rf_fp_val=
  _rf_fp_esc=
  _rf_fp_suffix=
  _rf_fp_key=

  # The index holds exactly the unescaped entries, which is the set the scan
  # considers when $4 is empty. Requiring $1 itself to be indexable is what
  # makes the walk complete: every prefix of an indexable key is itself
  # indexable, so no prefix can be hiding in the manifest unindexed.
  if [ -z "$_rf_fp_want_esc" ] && __runfiles_index_ready "$2" &&
    __runfiles_cache_key "$_rf_fp_path"; then
    __runfiles_find_prefix_indexed
    return
  fi
  if [ -n "${_RULES_SHELL_RUNFILES_AWK:-}" ]; then
    __runfiles_find_prefix_awk "$2" || return 1
  else
    __runfiles_find_prefix_scan "$2" || return 1
  fi

  # The matched key is a prefix of the escaped path, so the suffix is the rest
  # of that path. `/` is never escaped, so cutting the escaped form at a
  # segment boundary and decoding what follows yields the unescaped suffix;
  # without an escaped lookup the two forms are the same string. On a
  # case-insensitive platform the key may differ from the path in case, so it
  # is cut by length rather than by pattern.
  if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
    _rf_fp_suffix="$_rf_fp_epath"
    _rf_fp_n=${#_rf_fp_key}
    while [ "$_rf_fp_n" -gt 0 ]; do
      _rf_fp_suffix="${_rf_fp_suffix#?}"
      _rf_fp_n=$((_rf_fp_n - 1))
    done
  else
    _rf_fp_suffix="${_rf_fp_epath#"$_rf_fp_key"}"
  fi
  if [ -n "$_rf_fp_want_esc" ]; then
    __runfiles_gsub "$_rf_fp_suffix" '\n' "$_RULES_SHELL_RUNFILES_NL"
    __runfiles_gsub "$_rf_gs_out" '\s' ' '
    __runfiles_gsub "$_rf_gs_out" '\b' '\'
    _rf_fp_suffix="$_rf_gs_out"
  fi
  return 0
}

# The index walk behind __runfiles_find_prefix. Walking the prefixes
# longest-first yields the longest matching key by construction, which is what
# the scan computes the hard way, and the suffix falls out of the walk.
__runfiles_find_prefix_indexed() {
  _rf_fp_t="${_rf_fp_path%/*}"
  while :; do
    __runfiles_cache_key "$_rf_fp_t" || return 1
    eval "_rf_fp_val=\"\${${_rf_ix_pfx}${_rf_ck}-}\""
    # An entry with an empty value is treated as absent, as it is in the scan
    # and in the historical bash library: it does not stop the walk.
    if [ -n "$_rf_fp_val" ] && [ "$_rf_fp_val" != "$_RULES_SHELL_RUNFILES_NL" ]; then
      _rf_fp_suffix="${_rf_fp_path#"$_rf_fp_t"}"
      return 0
    fi
    case "$_rf_fp_t" in
      */*) _rf_fp_t="${_rf_fp_t%/*}" ;;
      *) return 1 ;;
    esac
  done
}

# The awk search behind __runfiles_find_prefix: one pass applies the same rules
# as the scan and reports the escaped flag, key and value on three lines.
__runfiles_find_prefix_awk() {
  _rf_fp_out=$(__runfiles_awk '
    BEGIN { p = ARGV[2]; e = ARGV[3]; c = ARGV[4]; ARGV[2] = ARGV[3] = ARGV[4] = ""
            if (c) p = tolower(p); best = 0 }
    { esc = (substr($0, 1, 1) == " ")
      if (esc && e == "") next
      line = esc ? substr($0, 2) : $0
      i = index(line, " "); if (i == 0) next
      n = i - 1
      if (n <= best || n >= length(p)) next
      k = substr(line, 1, n)
      if ((c ? tolower(k) : k) != substr(p, 1, n) || substr(p, n + 1, 1) != "/") next
      v = substr(line, i + 1); if (v == "") next
      best = n; bk = k; bv = v; be = esc }
    END { if (!best) exit 1; if (be) print "1"; else print ""; print bk; print bv }' \
    "$1" "$_rf_fp_epath" "$_rf_fp_want_esc" "$_RLOCATION_CASE_INSENSITIVE") || return 1
  _rf_fp_esc="${_rf_fp_out%%"$_RULES_SHELL_RUNFILES_NL"*}"
  _rf_fp_out="${_rf_fp_out#*"$_RULES_SHELL_RUNFILES_NL"}"
  _rf_fp_key="${_rf_fp_out%%"$_RULES_SHELL_RUNFILES_NL"*}"
  _rf_fp_val="${_rf_fp_out#*"$_RULES_SHELL_RUNFILES_NL"}"
}

# The shell-loop search behind __runfiles_find_prefix. The loop body runs once
# per manifest line, so everything that is not needed to reject a line is
# deferred -- in particular the value, which is never copied out of a line that
# does not match. The reject is a single quoted `case`: a manifest key can only
# be a prefix of the path if the path starts with it, which is as selective as
# the pattern the historical bash library hands to grep.
__runfiles_find_prefix_scan() {
  _rf_fp_klen=0
  if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
    __runfiles_tolower "$_rf_fp_epath"
    _rf_fp_lepath="$_rf_tl_out"
  fi
  while IFS= read -r _rf_fp_line || [ -n "$_rf_fp_line" ]; do
    _rf_fp_k="${_rf_fp_line%% *}"
    if [ -z "$_rf_fp_k" ]; then
      # Leading space: an escaped entry, or a blank line.
      [ -n "$_rf_fp_want_esc" ] || continue
      _rf_fp_k="${_rf_fp_line# }"
      _rf_fp_k="${_rf_fp_k%% *}"
      [ -n "$_rf_fp_k" ] || continue
      _rf_fp_this_esc=1
    else
      _rf_fp_this_esc=
    fi
    if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
      # Folding the key is one builtin operation under bash 4 and a loop over
      # its characters elsewhere; either way nothing is forked per line.
      __runfiles_tolower "$_rf_fp_k"
      _rf_fp_cmp="$_rf_tl_out"
      _rf_fp_against="$_rf_fp_lepath"
    else
      _rf_fp_cmp="$_rf_fp_k"
      _rf_fp_against="$_rf_fp_epath"
    fi
    case "$_rf_fp_against" in
      "$_rf_fp_cmp"*) ;;
      *) continue ;;
    esac

    # Past this point the line is a genuine candidate, so the rest of the work
    # is off the hot path.
    #
    # The key has to end on a path separator: `c/dir` is a prefix of
    # `c/dir/file` but not of `c/dirx/file`.
    case "$_rf_fp_against" in
      "$_rf_fp_cmp"/*) ;;
      *) continue ;;
    esac
    # Only a longer key than the best one so far can win.
    [ "${#_rf_fp_k}" -gt "$_rf_fp_klen" ] || continue
    case "$_rf_fp_line" in *" "*) ;; *) continue ;; esac
    if [ -n "$_rf_fp_this_esc" ]; then
      _rf_fp_v="${_rf_fp_line# }"
      _rf_fp_v="${_rf_fp_v#* }"
    else
      _rf_fp_v="${_rf_fp_line#* }"
    fi
    # An entry with an empty value is treated as absent, matching the
    # historical bash library: it does not stop the walk up the path prefixes.
    [ -n "$_rf_fp_v" ] || continue
    _rf_fp_key="$_rf_fp_k"
    _rf_fp_klen=${#_rf_fp_k}
    _rf_fp_val="$_rf_fp_v"
    _rf_fp_esc="$_rf_fp_this_esc"
  done < "$1"
  [ -n "$_rf_fp_key" ]
}

# Find the first non-escaped manifest line whose value (target path) matches
# $1. Prints the key (rlocation path) on stdout.
# On Windows, matching is case-insensitive.
__runfiles_find_by_target() {
  _rf_ft_target="$1"
  _rf_ft_file="$2"

  if [ -n "${_RULES_SHELL_RUNFILES_AWK:-}" ]; then
    __runfiles_awk '
      BEGIN { t = ARGV[2]; c = ARGV[3]; ARGV[2] = ARGV[3] = ""; if (c) t = tolower(t) }
      substr($0, 1, 1) == " " { next }
      { i = index($0, " "); if (i == 0) next
        v = substr($0, i + 1); if (c) v = tolower(v)
        if (v == t) { printf "%s", substr($0, 1, i - 1); f = 1; exit } }
      END { exit !f }' "$_rf_ft_file" "$_rf_ft_target" "$_RLOCATION_CASE_INSENSITIVE"
    return
  fi

  if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
    __runfiles_tolower "$_rf_ft_target"
    _rf_ft_ltgt="$_rf_tl_out"
    _rf_ft_tlen=${#_rf_ft_target}
    while IFS= read -r _rf_ft_line || [ -n "$_rf_ft_line" ]; do
      case "$_rf_ft_line" in " "*) continue ;; esac
      _rf_ft_key="${_rf_ft_line%% *}"
      _rf_ft_val="${_rf_ft_line#* }"
      # Cheap length check first — avoids per-char lowercasing when lengths
      # can't match.
      [ "${#_rf_ft_val}" = "$_rf_ft_tlen" ] || continue
      if __runfiles_line_starts_with_ci "$_rf_ft_val" "$_rf_ft_ltgt"; then
        printf '%s' "$_rf_ft_key"
        return 0
      fi
    done < "$_rf_ft_file"
  else
    while IFS= read -r _rf_ft_line || [ -n "$_rf_ft_line" ]; do
      # One quoted `case` rejects the ~all lines that do not match, without
      # copying anything out of them. A non-escaped entry contains exactly one
      # space, so ending in " $target" is the same test as its value being
      # $target; the split below re-checks it regardless.
      case "$_rf_ft_line" in
        " "*) continue ;;
        *" $_rf_ft_target") ;;
        *) continue ;;
      esac
      _rf_ft_key="${_rf_ft_line%% *}"
      _rf_ft_val="${_rf_ft_line#* }"
      if [ "$_rf_ft_val" = "$_rf_ft_target" ]; then
        printf '%s' "$_rf_ft_key"
        return 0
      fi
    done < "$_rf_ft_file"
  fi
  return 1
}

# Look up a repo mapping entry.
# Args: $1=source_repo $2=source_repo_prefix $3=target_apparent_name
#       $4=mapping_file
# Stores the canonical target repo name in _rf_rm_out and returns 1 if there is
# no entry. Stored rather than printed so that rlocation does not fork a
# subshell for it on every lookup.
# On Windows, matching is case-insensitive.
#
# The mapping lists every repository visible from every repository in the
# binary's runfiles, so it can run to thousands of lines; with awk enabled it
# is searched by awk like the manifest, as the historical bash library searched
# it with grep.
__runfiles_find_repo_mapping() {
  _rf_rm_src="$1"
  _rf_rm_pfx="$2"
  _rf_rm_tgt="$3"
  _rf_rm_file="$4"
  _rf_rm_out=

  if [ -n "${_RULES_SHELL_RUNFILES_AWK:-}" ]; then
    _rf_rm_out=$(__runfiles_awk '
      BEGIN { a = ARGV[2]; b = ARGV[3]; c = ARGV[4]; ARGV[2] = ARGV[3] = ARGV[4] = ""
              if (c) { a = tolower(a); b = tolower(b) } na = length(a); nb = length(b) }
      { l = c ? tolower($0) : $0
        if (substr(l, 1, na) == a || substr(l, 1, nb) == b) {
          r = $0; sub(/^[^,]*,[^,]*,/, "", r); print r; f = 1; exit } }
      END { exit !f }' "$_rf_rm_file" "${_rf_rm_src},${_rf_rm_tgt}," "${_rf_rm_pfx},${_rf_rm_tgt}," \
      "$_RLOCATION_CASE_INSENSITIVE") || return 1
    return 0
  fi

  if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
    __runfiles_tolower "${_rf_rm_src},${_rf_rm_tgt},"
    _rf_rm_pfx_src="$_rf_tl_out"
    __runfiles_tolower "${_rf_rm_pfx},${_rf_rm_tgt},"
    _rf_rm_pfx_pfx="$_rf_tl_out"
    while IFS= read -r _rf_rm_line || [ -n "$_rf_rm_line" ]; do
      # Compare only the prefix (src,tgt,) case-insensitively — a cheap early
      # exit for the ~all lines that don't match, without the O(N^2) lowercase
      # of a whole line.
      if __runfiles_line_starts_with_ci "$_rf_rm_line" "$_rf_rm_pfx_src" \
        || __runfiles_line_starts_with_ci "$_rf_rm_line" "$_rf_rm_pfx_pfx"; then
        _rf_rm_rest="${_rf_rm_line#*,}"
        _rf_rm_out="${_rf_rm_rest#*,}"
        return 0
      fi
    done < "$_rf_rm_file"
  else
    while IFS= read -r _rf_rm_line || [ -n "$_rf_rm_line" ]; do
      case "$_rf_rm_line" in
        "${_rf_rm_src},${_rf_rm_tgt},"*|"${_rf_rm_pfx},${_rf_rm_tgt},"*)
          _rf_rm_rest="${_rf_rm_line#*,}"
          _rf_rm_out="${_rf_rm_rest#*,}"
          return 0
          ;;
      esac
    done < "$_rf_rm_file"
  fi
  return 1
}

# Parse the repository name from an exec path.
# Scans path segments for /bazel-out/<config>/bin/external/<repo>/ or
# /bazel-bin/external/<repo>/ and returns the last matching <repo>.
# Equivalent to: grep -E -o '...' | tail -1 | awk -F/ '{print $(NF-1)}'
__runfiles_parse_exec_path_repo() {
  _rf_pe_path="$1"
  _rf_pe_result=""
  _rf_pe_rest="$_rf_pe_path"

  # Track last 4 path segments via a sliding window.
  _rf_pe_p4="" _rf_pe_p3="" _rf_pe_p2="" _rf_pe_p1=""
  while :; do
    case "$_rf_pe_rest" in
      */*)
        _rf_pe_seg="${_rf_pe_rest%%/*}"
        _rf_pe_rest="${_rf_pe_rest#*/}"
        ;;
      *)
        _rf_pe_seg="$_rf_pe_rest"
        _rf_pe_rest=""
        ;;
    esac

    # Pattern: bazel-bin/external/<repo>
    if [ "$_rf_pe_p2" = "bazel-bin" ] && [ "$_rf_pe_p1" = "external" ] \
       && [ -n "$_rf_pe_seg" ]; then
      _rf_pe_result="$_rf_pe_seg"
    fi
    # Pattern: bazel-out/<config>/bin/external/<repo>
    if [ "$_rf_pe_p4" = "bazel-out" ] && [ "$_rf_pe_p2" = "bin" ] \
       && [ "$_rf_pe_p1" = "external" ] && [ -n "$_rf_pe_seg" ]; then
      _rf_pe_result="$_rf_pe_seg"
    fi

    _rf_pe_p4="$_rf_pe_p3"
    _rf_pe_p3="$_rf_pe_p2"
    _rf_pe_p2="$_rf_pe_p1"
    _rf_pe_p1="$_rf_pe_seg"

    [ -z "$_rf_pe_rest" ] && break
  done

  if [ -n "$_rf_pe_result" ]; then
    printf '%s' "$_rf_pe_result"
    return 0
  fi
  return 1
}

# --- Public API ---

# Prints to stdout the runtime location of a data-dependency.
# The optional second argument specifies the canonical name of the repository
# whose repository mapping should be used to resolve the repository part of
# the provided path. If not specified:
#   * Under bash, the caller's repository is auto-detected via BASH_SOURCE,
#     as the historical bash library did. Every bash script that sources
#     runfiles.bash gets this file, so third-party callers depend on this.
#   * Under a pure POSIX shell there is no BASH_SOURCE, so the main repository
#     is assumed. Portable callers should pass the source repo explicitly.
rlocation() {
  __runfiles_debug "INFO[runfiles.sh]: rlocation($1): start"
  if __runfiles_is_abs "$1"; then
    __runfiles_debug "INFO[runfiles.sh]: rlocation($1): absolute path, return"
    printf '%s\n' "$1"
    return 0
  fi
  case "$1" in
    ../*|*/..|./*|*/./*|*/.|*//*) # shellcheck disable=SC2254
      __runfiles_debug "ERROR[runfiles.sh]: rlocation($1): path is not normalized"
      return 1
      ;;
    \\*)
      __runfiles_debug "ERROR[runfiles.sh]: rlocation($1): absolute path without" \
        "drive name"
      return 1
      ;;
  esac

  if [ -f "${RUNFILES_REPO_MAPPING:-}" ]; then
    local target_repo_apparent_name="${1%%/*}"
    local remainder=
    case "$1" in
      */*) remainder="${1#*/}" ;;
    esac
    if [ -n "$remainder" ]; then
      local source_repo=""
      if [ -n "${2+x}" ]; then
        source_repo="$2"
      elif [ -n "${BASH_VERSION:-}" ]; then
        # Idx 2 walks past runfiles_current_repository and rlocation to the
        # actual caller, mirroring runfiles.bash; BASH_SOURCE[1] here is that
        # same frame, one call closer.
        #
        # The answer depends only on the caller's script and on where the
        # runfiles live, and resolving it costs a command substitution plus,
        # with a manifest, a search on entry values that the index cannot
        # serve. __runfiles_memo_caller_repository may therefore have resolved
        # it already. The memo is only read here, never written: rlocation
        # prints its answer, so it runs in a `$(...)` subshell whose variables
        # die with it.
        local _rf_rc_key
        eval '_rf_rc_key="${BASH_SOURCE[1]:-}"'
        _rf_rc_key="$_rf_rc_key|${RUNFILES_MANIFEST_FILE:-}|${RUNFILES_DIR:-}|${PWD:-}"
        if [ "${RUNFILES_LIB_DEBUG:-}" != 1 ] &&
          [ "$_rf_rc_key" = "${_rf_rc_memo_key:-}" ]; then
          source_repo="$_rf_rc_memo_val"
        else
          # `|| true` preserves whatever repo name the parse-exec-path fallback
          # already printed to stdout, mirroring bash's `local -r x=$(...)`
          # where `local` masks the subshell's exit code.
          source_repo="$(runfiles_current_repository 2 || true)"
        fi
      fi
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1): looking up canonical name for ($target_repo_apparent_name) from ($source_repo) in ($RUNFILES_REPO_MAPPING)"
      local source_repo_prefix
      __runfiles_compute_repo_prefix "$source_repo"
      source_repo_prefix="$_rf_cp_out"
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1): matching source_repo ($source_repo) or prefix ($source_repo_prefix) with target ($target_repo_apparent_name)"
      local target_repo
      __runfiles_find_repo_mapping "$source_repo" "$source_repo_prefix" "$target_repo_apparent_name" "$RUNFILES_REPO_MAPPING" || true
      target_repo="$_rf_rm_out"
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1): canonical name of target repo is ($target_repo)"
      if [ -n "$target_repo" ]; then
        local rlocation_path="$target_repo/$remainder"
      else
        local rlocation_path="$1"
      fi
    else
      local rlocation_path="$1"
    fi
  else
    __runfiles_debug "INFO[runfiles.sh]: rlocation($1): not using repository mapping (${RUNFILES_REPO_MAPPING:-}) since it does not exist"
    local rlocation_path="$1"
  fi

  runfiles_rlocation_checked "$rlocation_path"
}

# Exports the environment variables that subprocesses need in order to use
# runfiles.
# If a subprocess is a Bazel-built binary rule that also uses the runfiles
# libraries under @bazel_tools//tools/<lang>/runfiles, then that binary needs
# these envvars in order to initialize its own runfiles library.
runfiles_export_envvars() {
  if ! [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ] \
     && ! [ -d "${RUNFILES_DIR:-/dev/null}" ]; then
    return 1
  fi

  if ! [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    if [ -f "$RUNFILES_DIR/MANIFEST" ]; then
      export RUNFILES_MANIFEST_FILE="$RUNFILES_DIR/MANIFEST"
    elif [ -f "${RUNFILES_DIR}_manifest" ]; then
      export RUNFILES_MANIFEST_FILE="${RUNFILES_DIR}_manifest"
    else
      export RUNFILES_MANIFEST_FILE=
    fi
  elif ! [ -d "${RUNFILES_DIR:-/dev/null}" ]; then
    case "$RUNFILES_MANIFEST_FILE" in
      */MANIFEST)
        if [ -d "${RUNFILES_MANIFEST_FILE%/MANIFEST}" ]; then
          export RUNFILES_DIR="${RUNFILES_MANIFEST_FILE%/MANIFEST}"
          export JAVA_RUNFILES="$RUNFILES_DIR"
        else
          export RUNFILES_DIR=
        fi
        ;;
      *_manifest)
        if [ -d "${RUNFILES_MANIFEST_FILE%_manifest}" ]; then
          export RUNFILES_DIR="${RUNFILES_MANIFEST_FILE%_manifest}"
          export JAVA_RUNFILES="$RUNFILES_DIR"
        else
          export RUNFILES_DIR=
        fi
        ;;
      *)
        export RUNFILES_DIR=
        ;;
    esac
  fi

  # Lookups may now go through a manifest that was not in use when the library
  # was sourced -- on Linux a `bazel test` starts with only RUNFILES_DIR set and
  # the MANIFEST inside it is promoted above -- so bring the index and the
  # memoized caller repository up to date. Both are no-ops unless
  # RULES_SHELL_RUNFILES_CACHE=1, and like sourcing, they only take effect in
  # the shell that runs this function.
  __runfiles_index_ready "${RUNFILES_MANIFEST_FILE:-}" || __runfiles_index_build "${RUNFILES_MANIFEST_FILE:-}"
  if [ -n "${BASH_VERSION:-}" ]; then
    eval '__runfiles_memo_caller_repository "${BASH_SOURCE[1]:-}"'
  fi
}

# Resolve the repository of the script at $1 once, for rlocation to reuse
# instead of resolving it on every call. Only the shell that sourced this file
# can fill the memo -- rlocation runs in `$(...)`, so anything it stored would
# die with the subshell -- so this runs at source time and again from
# runfiles_export_envvars, which changes the inputs the answer depends on. Does
# nothing, and clears the memo, unless the index is on, the shell is bash and
# there is a repo mapping for rlocation to consult.
__runfiles_memo_caller_repository() {
  if [ -z "${_RULES_SHELL_RUNFILES_INDEX_OK:-}" ] || [ -z "${BASH_VERSION:-}" ] ||
    [ "${RUNFILES_LIB_DEBUG:-}" = 1 ] || ! [ -f "${RUNFILES_REPO_MAPPING:-}" ] ||
    [ -z "${1:-}" ]; then
    _rf_rc_memo_key=
    _rf_rc_memo_val=
    return 0
  fi
  _rf_mc_key="$1|${RUNFILES_MANIFEST_FILE:-}|${RUNFILES_DIR:-}|${PWD:-}"
  [ "$_rf_mc_key" = "${_rf_rc_memo_key:-}" ] && return 0
  _rf_rc_memo_val="$(runfiles_current_repository "$1" || true)"
  _rf_rc_memo_key="$_rf_mc_key"
}

# Print the repository of a script that is not in the runfiles tree -- the
# sh_binary entrypoint, or a binary run directly from bazel-bin -- parsed from
# its path under the execroot: empty for the main repository. $1 is the
# normalized path, $2 the argument runfiles_current_repository was called
# with, for the diagnostic.
__runfiles_print_exec_path_repository() {
  _rf_pr_repo="$(__runfiles_parse_exec_path_repo "$1")" || true
  if [ -n "$_rf_pr_repo" ]; then
    __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository($2): ($1) lies in repository ($_rf_pr_repo) (parsed exec path)"
  else
    __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository($2): ($1) lies in the main repository (parsed exec path)"
  fi
  printf '%s\n' "$_rf_pr_repo"
}

# Returns the canonical name of the Bazel repository containing the calling
# script.
#
# Calling convention:
#   * Under bash, this matches the historical bash library: the optional
#     first argument is a numeric index N (default 1) selecting the N-th
#     caller via BASH_SOURCE. This lets bash consumers that source this file
#     -- directly or via the launcher -- call runfiles_current_repository with
#     no arguments.
#   * Under a POSIX shell there is no BASH_SOURCE, so the caller must supply
#     its own script path as the first argument:
#
#       runfiles_current_repository "$0"
#
# Note: This function only works correctly with Bzlmod enabled. Without
# Bzlmod, its return value is ignored if passed to rlocation.
runfiles_current_repository() {
  local raw_caller_path=
  local _rf_arg="${1:-}"
  # Non-numeric arg: caller passed a script path (POSIX calling convention).
  # Accepted under both bash and POSIX so portable scripts work.
  case "$_rf_arg" in
    *[!0123456789]*) raw_caller_path="$_rf_arg" ;;
  esac
  if [ -z "$raw_caller_path" ]; then
    if [ -n "${BASH_VERSION:-}" ]; then
      # Empty arg defaults to idx=1 (bash convention, N-th caller).
      # BASH_SOURCE array indexing is bash-only syntax; hide it from POSIX
      # shells via eval so parsing succeeds. `:-` guards against out-of-bounds
      # indices under `set -u`.
      eval 'raw_caller_path="${BASH_SOURCE[${_rf_arg:-1}]:-}"'
      if [ -z "$raw_caller_path" ]; then
        __runfiles_debug "ERROR[runfiles.sh]: runfiles_current_repository: no caller" \
          "path resolvable from BASH_SOURCE (idx=${_rf_arg:-1} out of range)"
        return 1
      fi
    else
      if [ -z "$_rf_arg" ]; then
        __runfiles_debug "ERROR[runfiles.sh]: runfiles_current_repository: caller" \
          "path argument is required under a POSIX shell (pass \"\$0\")"
      else
        __runfiles_debug "ERROR[runfiles.sh]: runfiles_current_repository: numeric" \
          "caller index ($_rf_arg) requires bash; pass the caller" \
          "path (\"\$0\") instead"
      fi
      return 1
    fi
  fi
  if __runfiles_is_abs "$raw_caller_path"; then
    local caller_path="$raw_caller_path"
  else
    # dirname/basename without external binaries
    local _rf_dir _rf_base
    case "$raw_caller_path" in
      */*) _rf_dir="${raw_caller_path%/*}"; [ -z "$_rf_dir" ] && _rf_dir="/" ;;
      *)   _rf_dir="." ;;
    esac
    _rf_base="${raw_caller_path##*/}"
    local caller_path
    caller_path="$(cd "$_rf_dir" || return 1; pwd)/$_rf_base"
  fi
  __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): caller's path is ($caller_path)"

  local rlocation_path=

  # If the runfiles manifest exists, search for an entry with target the
  # caller's path.
  if [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    local normalized_caller_path
    normalized_caller_path="$(__runfiles_normalize_backslashes "$caller_path")"
    local escaped_caller_path="$normalized_caller_path"
    rlocation_path="$(__runfiles_find_by_target "$escaped_caller_path" "$RUNFILES_MANIFEST_FILE")" || true
    if [ -z "$rlocation_path" ]; then
      __runfiles_debug "ERROR[runfiles.sh]: runfiles_current_repository(${1:-}): ($normalized_caller_path) is not the target of an entry in the runfiles manifest ($RUNFILES_MANIFEST_FILE)"
      __runfiles_print_exec_path_repository "$normalized_caller_path" "${1:-}"
      return 1
    else
      __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($normalized_caller_path) is the target of ($rlocation_path) in the runfiles manifest"
    fi
  fi

  # If the runfiles directory exists, check if the caller's path is of the
  # form $RUNFILES_DIR/rlocation_path and if so, set $rlocation_path.
  if [ -z "$rlocation_path" ] && [ -d "${RUNFILES_DIR:-/dev/null}" ]; then
    local normalized_caller_path normalized_dir
    normalized_caller_path="$(__runfiles_normalize_backslashes "$caller_path")"
    local _rf_rd="${RUNFILES_DIR%/}"
    _rf_rd="${_rf_rd%\\}"
    normalized_dir="$(__runfiles_normalize_backslashes "$_rf_rd")"
    if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
      __runfiles_tolower "$normalized_caller_path"
      normalized_caller_path="$_rf_tl_out"
      __runfiles_tolower "$normalized_dir"
      normalized_dir="$_rf_tl_out"
    fi
    case "$normalized_caller_path" in
      "$normalized_dir"/*)
        rlocation_path="${normalized_caller_path#"$normalized_dir"}"
        rlocation_path="${rlocation_path#/}"
        ;;
    esac
    if [ -z "$rlocation_path" ]; then
      __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($normalized_caller_path) does not lie under the runfiles directory ($normalized_dir)"
      __runfiles_print_exec_path_repository "$normalized_caller_path" "${1:-}"
      return 0
    else
      __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($caller_path) has path ($rlocation_path) relative to the runfiles directory ($RUNFILES_DIR)"
    fi
  fi

  if [ -z "$rlocation_path" ]; then
    __runfiles_debug "ERROR[runfiles.sh]: runfiles_current_repository(${1:-}): cannot determine repository for ($caller_path) since neither the runfiles directory (${RUNFILES_DIR:-}) nor the runfiles manifest (${RUNFILES_MANIFEST_FILE:-}) exist"
    return 1
  fi

  __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($caller_path) corresponds to rlocation path ($rlocation_path)"
  # Normalize the rlocation path to be of the form repo/pkg/file.
  rlocation_path="${rlocation_path#_main/external/}"
  rlocation_path="${rlocation_path#_main/../}"
  local repository="${rlocation_path%%/*}"
  if [ "$repository" = "_main" ]; then
    __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($rlocation_path) lies in the main repository"
    printf '%s\n' ""
  else
    __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($rlocation_path) lies in repository ($repository)"
    printf '%s\n' "$repository"
  fi
}

# Lexically resolve the "." and ".." segments of the rlocation path $1, into
# _rf_np_out. Returns 1 for an empty path or one that would escape the runfiles
# root.
__runfiles_normalize_rlocation_path() {
  _rf_np_rest="$1"
  _rf_np_out=
  while [ -n "$_rf_np_rest" ]; do
    case "$_rf_np_rest" in
      */*) _rf_np_seg="${_rf_np_rest%%/*}"; _rf_np_rest="${_rf_np_rest#*/}" ;;
      *) _rf_np_seg="$_rf_np_rest"; _rf_np_rest= ;;
    esac
    case "$_rf_np_seg" in
      ""|.) ;;
      ..)
        case "$_rf_np_out" in
          */*) _rf_np_out="${_rf_np_out%/*}" ;;
          ?*) _rf_np_out= ;;
          *) return 1 ;;
        esac
        ;;
      *) _rf_np_out="${_rf_np_out:+$_rf_np_out/}$_rf_np_seg" ;;
    esac
  done
  [ -n "$_rf_np_out" ]
}

# Resolve the target $2 of the manifest entry $1, with $3 appended, to a path in
# the file system, and print it -- or an empty line if there is no such file.
# $4 is the current lookup depth.
#
# Bazel copies the target of an unresolved symlink (ctx.actions.declare_symlink)
# into the manifest verbatim, so unlike every other target it may be relative.
# In a materialized runfiles directory the entry is a symlink with that very
# target, which the file system resolves against the directory containing the
# symlink. A relative target is therefore an rlocation path relative to the
# entry's directory, and is looked up in the manifest again.
__runfiles_resolve_manifest_target() {
  case "$2" in
    /*) _rf_rt_abs=1 ;;
    *) if __runfiles_is_abs "$2"; then _rf_rt_abs=1; else _rf_rt_abs=; fi ;;
  esac
  if [ -n "$_rf_rt_abs" ]; then
    _rf_rt_resolved="$2$3"
    if [ -e "$_rf_rt_resolved" ]; then
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1$3): found in manifest as ($_rf_rt_resolved)"
      printf '%s\n' "$_rf_rt_resolved"
    else
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1$3): found in manifest as ($_rf_rt_resolved), but file does not exist"
      printf '%s\n' ""
    fi
    return 0
  fi

  _rf_rt_dir="${1%/*}"
  [ "$_rf_rt_dir" = "$1" ] && _rf_rt_dir=
  if ! __runfiles_normalize_rlocation_path "${_rf_rt_dir:+$_rf_rt_dir/}$2$3"; then
    __runfiles_debug "ERROR[runfiles.sh]: rlocation($1$3): unresolved symlink target ($2) points outside the runfiles tree"
    printf '%s\n' ""
    return 0
  fi
  __runfiles_debug "INFO[runfiles.sh]: rlocation($1$3): unresolved symlink target ($2) resolves to ($_rf_np_out)"
  runfiles_rlocation_checked "$_rf_np_out" "$(($4 + 1))"
}

runfiles_rlocation_checked() {
  # FIXME: If the runfiles lookup fails, the exit code of this function is 0
  #  if and only if the runfiles manifest exists. In particular, the exit code
  #  behavior is not consistent across platforms.
  # The optional second argument is the current lookup depth, which only
  # differs from zero while following the target of an unresolved symlink.
  local depth="${2:-0}"
  if [ "$depth" -gt 32 ]; then
    __runfiles_debug "ERROR[runfiles.sh]: rlocation($1): too many levels of symbolic links"
    printf '%s\n' ""
    return 0
  fi
  # The manifest takes precedence over the runfiles directory: whether the
  # directory is populated is a property of the execution of the action or
  # test, which is not known at analysis time, so the directory may exist but
  # contain stale contents from a previous execution. If the manifest exists,
  # it is always authoritative.
  if [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    __runfiles_debug "INFO[runfiles.sh]: rlocation($1): looking in RUNFILES_MANIFEST_FILE ($RUNFILES_MANIFEST_FILE)"
    # If the rlocation path contains a space or newline, it is stored in the
    # manifest prefixed with a space and with spaces, newlines and backslashes
    # escaped as \s, \n and \b.
    local search_key escaped suffix
    case "$1" in
      *" "*|*"$_RULES_SHELL_RUNFILES_NL"*)
        # Backslashes first, so that the ones the other two escapes introduce
        # are left alone.
        __runfiles_gsub "$1" '\' '\b'
        __runfiles_gsub "$_rf_gs_out" ' ' '\s'
        __runfiles_gsub "$_rf_gs_out" "$_RULES_SHELL_RUNFILES_NL" '\n'
        search_key="$_rf_gs_out"
        escaped=1
        __runfiles_debug "INFO[runfiles.sh]: rlocation($1): using escaped search key ($search_key)"
        ;;
      *)
        search_key="$1"
        escaped=
        ;;
    esac

    # Look for $1 itself first: the overwhelmingly common case, served by the
    # index when there is one, else by awk or by a scan that rejects a line
    # with a single `case`.
    #
    # An entry with an empty value counts as absent, matching the historical
    # bash library, hence the test on _rf_fl_val rather than on the exit status.
    local result=
    if __runfiles_find_line "${escaped:+ }$search_key" "$RUNFILES_MANIFEST_FILE" &&
      [ -n "$_rf_fl_val" ]; then
      result="$_rf_fl_val"
      suffix=
    elif [ "${1%/*}" != "$1" ] &&
      __runfiles_find_prefix "$1" "$RUNFILES_MANIFEST_FILE" "$search_key" "$escaped"; then
      # $1 is not listed, but it may lie under a directory that is. One extra
      # scan resolves every path prefix at once; a path without a separator
      # skips the walk entirely, as the _repo_mapping lookup does.
      result="$_rf_fp_val"
      escaped="$_rf_fp_esc"
      suffix="$_rf_fp_suffix"
    else
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1): not found in manifest"
      printf '%s\n' ""
      return 0
    fi
    if [ -n "$escaped" ]; then
      __runfiles_gsub "$result" '\n' "$_RULES_SHELL_RUNFILES_NL"
      __runfiles_gsub "$_rf_gs_out" '\b' '\'
      result="$_rf_gs_out"
    fi
    # When a hit that came from a path prefix does not resolve, there is
    # deliberately no retry with a shorter one, for two reasons:
    # 1. Manifests generated by Bazel never contain a path that is a prefix
    #    of another path.
    # 2. Runfiles libraries for other languages do not check for file
    #    existence and would have returned the non-existent path. It seems
    #    better to return no path rather than a potentially different,
    #    non-empty path.
    __runfiles_resolve_manifest_target "${1%"$suffix"}" "$result" "$suffix" "$depth"
  elif [ -e "${RUNFILES_DIR:-/dev/null}/$1" ]; then
    __runfiles_debug "INFO[runfiles.sh]: rlocation($1): found under RUNFILES_DIR ($RUNFILES_DIR), return"
    printf '%s\n' "${RUNFILES_DIR}/$1"
  else
    __runfiles_debug "ERROR[runfiles.sh]: cannot look up runfile \"$1\" " \
      "(RUNFILES_DIR=\"${RUNFILES_DIR:-}\"," \
      "RUNFILES_MANIFEST_FILE=\"${RUNFILES_MANIFEST_FILE:-}\")"
    return 1
  fi
}

# When running under bash, export functions so they survive exec (used by the
# launcher). POSIX sh has no equivalent of `export -f`, so this block is
# skipped in pure POSIX shells.
if [ -n "${BASH_VERSION:-}" ]; then
  for _rf_fn in \
    __runfiles_debug \
    __runfiles_detect_platform \
    __runfiles_is_abs \
    __runfiles_tolower \
    __runfiles_line_starts_with_ci \
    __runfiles_normalize_backslashes \
    __runfiles_gsub \
    __runfiles_awk \
    __runfiles_compute_repo_prefix \
    __runfiles_cache_key \
    __runfiles_index_build \
    __runfiles_index_ready \
    __runfiles_find_line \
    __runfiles_find_line_awk \
    __runfiles_find_line_scan \
    __runfiles_find_prefix \
    __runfiles_find_prefix_indexed \
    __runfiles_find_prefix_awk \
    __runfiles_find_prefix_scan \
    __runfiles_find_by_target \
    __runfiles_find_repo_mapping \
    __runfiles_memo_caller_repository \
    __runfiles_parse_exec_path_repo \
    __runfiles_print_exec_path_repository \
    __runfiles_normalize_rlocation_path \
    __runfiles_resolve_manifest_target \
    rlocation \
    runfiles_export_envvars \
    runfiles_current_repository \
    runfiles_rlocation_checked; do
    # shellcheck disable=SC3045,SC2163  # export -f is the point; the name is variable
    export -f "$_rf_fn"
  done
  unset _rf_fn
fi

# --- Source-time caching ---
#
# Everything below runs in the shell that sourced this file, the only shell
# whose variables every later `$(rlocation ...)` subshell inherits, so it is
# done once for the whole script; the index needs RULES_SHELL_RUNFILES_CACHE=1.

# Parse the manifest into an index if asked to, so that lookups do not scan it.
# This also makes the _repo_mapping lookup below a constant-time one.
__runfiles_index_build "${RUNFILES_MANIFEST_FILE:-}"

# The repo mapping manifest may not exist with old versions of Bazel.
RUNFILES_REPO_MAPPING=$(runfiles_rlocation_checked _repo_mapping || echo "")
export RUNFILES_REPO_MAPPING

# With the index on, resolve the sourcing script's repository once and prime
# rlocation's memo with it. At the top level of a sourced file that script is
# BASH_SOURCE[1], or BASH_SOURCE[2] when this file is sourced through
# runfiles.bash, which sets _rf_bash_wrapped. Either is the frame rlocation
# later reads as its own BASH_SOURCE[1], which is what makes the key match.
_rf_src_caller=
if [ -n "${BASH_VERSION:-}" ]; then
  if [ -n "${_rf_bash_wrapped:-}" ]; then
    eval '_rf_src_caller="${BASH_SOURCE[2]:-}"'
  else
    eval '_rf_src_caller="${BASH_SOURCE[1]:-}"'
  fi
fi
__runfiles_memo_caller_repository "$_rf_src_caller"
_rf_src_caller=
