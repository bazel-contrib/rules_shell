# shellcheck shell=sh
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
# shell.
#
# This file is the implementation behind both @rules_shell//shell/runfiles
# entry points. Sourced directly, it is the POSIX library; runfiles.bash, next
# to it, is the bash entry point and sources it. The public API is
# rlocation, runfiles_export_envvars, runfiles_current_repository and
# runfiles_rlocation_checked. Under bash the caller's repository is detected
# from BASH_SOURCE and the functions are exported with `export -f`. Under any
# other shell, runfiles_current_repository needs the caller's script path as
# its argument, rlocation without a second argument assumes the main
# repository, and every script has to source the library itself.
#
# README.md in this directory covers what a lookup costs, with measurements.
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
# - AWK: the awk program that searches manifests, one process per lookup;
#   `awk` from PATH by default. Expanded unquoted, so `busybox awk` works. A
#   program that cannot be found leaves the shell loops in place.
# - RULES_SHELL_RUNFILES_USE_AWK=0: search manifests with shell loops rather
#   than awk, so that nothing is forked. Has no effect when AWK is set.
#
# Exported for child processes: RUNFILES_DIR, RUNFILES_MANIFEST_FILE and
# JAVA_RUNFILES (by runfiles_export_envvars), and RUNFILES_REPO_MAPPING, the
# path of the repository mapping manifest.
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
#       # --- begin runfiles.sh initialization v4 ---
#       # Copy-pasted from the Bazel POSIX shell runfiles library v4.
#       set -u; set +e; f=rules_shell/shell/runfiles/runfiles.sh; _rf_p=; _rf_a=
#       if [ -n "${AWK:-}" ] || [ "${RULES_SHELL_RUNFILES_USE_AWK:-}" != 0 ]; then _rf_a=1; fi
#       _rf_d() { [ -f "$1/$f" ] && _rf_p="$1/$f"; }
#       _rf_m() { [ -f "$1" ] || return 1; if [ -n "$_rf_a" ]; then \
#         _rf_p=$(${AWK:-awk} -v k="$f " 'index($0,k)==1{print substr($0,length(k)+1);m=1;exit}END{exit !m}' < "$1" 2>/dev/null); case $? in 0) return;; 1) return 1;; esac; fi; \
#         while IFS= read -r _rf_l || [ -n "$_rf_l" ]; do \
#         case "$_rf_l" in "$f "*) _rf_p="${_rf_l#"$f "}"; return;; esac; done < "$1"; return 1; }
#       _rf_d "${RUNFILES_DIR:-/dev/null}" || _rf_m "${RUNFILES_MANIFEST_FILE:-/dev/null}" || \
#         _rf_d "$0.runfiles" || _rf_m "$0.runfiles_manifest" || _rf_m "$0.exe.runfiles_manifest" || \
#         { echo>&2 "ERROR: cannot find $f"; exit 1; }
#       # shellcheck disable=SC1090
#       . "$_rf_p" || { echo>&2 "ERROR: cannot source $_rf_p"; exit 1; }; f=; unset -f _rf_d _rf_m; unset _rf_l _rf_p _rf_a; set -e
#       # --- end runfiles.sh initialization v4 ---
#
#     `.` on a missing file is fatal in a POSIX shell, so the snippet resolves
#     each candidate location to an existing path before sourcing it: `_rf_d`
#     checks a runfiles directory, `_rf_m` searches a manifest, with awk unless
#     RULES_SHELL_RUNFILES_USE_AWK=0 and a shell loop otherwise. It is the
#     runfiles.bash snippet of the same version, with this file's path and
#     without `pipefail`, which not every shell has.
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
  # The library under either name //shell/runfiles installs it as: a tree
  # that only has the legacy bazel_tools one, as Bazel's own runfiles target
  # builds it, is a runfiles directory all the same.
  elif [ -f "$0.runfiles/rules_shell/shell/runfiles/runfiles.sh" ] \
    || [ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi

# Detects whether we are running in a Windows shell environment (MSYS2, MinGW
# or Cygwin) and sets _RLOCATION_ISABS_WINDOWS / _RLOCATION_CASE_INSENSITIVE
# accordingly, from the environment and shell builtins.
#
# Signals, in order of reliability:
#   1. MSYSTEM is set by every MSYS2, MinGW and Git-for-Windows shell.
#   2. OSTYPE is set by bash to "cygwin" / "msys" (absent under dash).
#   3. /proc/version names the runtime on Cygwin and MSYS2 ("CYGWIN_NT-...",
#      "MSYS_NT-...", "MINGW64_NT-..."). If the file exists and does not name
#      one of those, we are on a Unix-like system and must not consult the
#      Windows environment variables below; WSL, for instance, can inherit
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

# Replace one or more consecutive backslashes with a single forward slash, into
# _rf_nb_out. Stored rather than printed so that finding the caller's
# repository, which rlocation does on every lookup under bash, forks nothing.
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

# --- Manifest search ---

# Convert ASCII uppercase to lowercase, into _rf_tl_out. Stored rather than
# printed so that no caller forks for it: the case-insensitive manifest scans
# call it once per line.
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

# Return 0 iff the first ${#2} characters of $1, lowercased, equal $2, which
# must already be lowercase: a prefix test that stops at the first mismatch
# rather than folding the whole line.
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

# Manifests are searched with awk rather than a shell `read` loop whenever awk
# can be found: a fork per lookup, but one that reads the file in bulk, so the
# cost stops growing with the manifest. AWK names the program, `awk` on PATH
# otherwise, and is expanded unquoted where it runs.
# RULES_SHELL_RUNFILES_USE_AWK=0 keeps the shell loops, which fork nothing.
_RULES_SHELL_RUNFILES_AWK=
if [ -n "${AWK:-}" ] || [ "${RULES_SHELL_RUNFILES_USE_AWK:-}" != 0 ]; then
  _RULES_SHELL_RUNFILES_AWK="${AWK:-awk}"
  if ! command -v "${_RULES_SHELL_RUNFILES_AWK%% *}" >/dev/null 2>&1; then
    __runfiles_debug "WARNING[runfiles.sh]: '$_RULES_SHELL_RUNFILES_AWK' cannot be found; searching manifests with shell loops"
    _RULES_SHELL_RUNFILES_AWK=
  fi
fi
export _RULES_SHELL_RUNFILES_AWK

# Run the awk program $1 over the file $2. Every further argument is a
# parameter, which the program reads from ARGV[1], ARGV[2], ... in its BEGIN
# block and blanks, so that awk reads the file from stdin instead. The file is
# redirected rather than passed as an operand because awk takes an operand of
# the form name=value as an assignment. Parameters travel as arguments rather
# than through `-v`, which would process the backslashes of an escaped key.
#
# awk runs in the C locale: a path is a byte string, gawk warns on stderr about
# bytes that are not valid in a UTF-8 locale, and ASCII-only case folding is
# what the shell loops do too.
__runfiles_awk() {
  _rf_aw_prog="$1"
  _rf_aw_file="$2"
  shift 2
  LC_ALL=C $_RULES_SHELL_RUNFILES_AWK "$_rf_aw_prog" "$@" < "$_rf_aw_file"
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

  if [ -n "${_RULES_SHELL_RUNFILES_AWK:-}" ]; then
    __runfiles_find_line_awk "$1" "$2"
  else
    __runfiles_find_line_scan "$1" "$2"
  fi
}

# The awk search behind __runfiles_find_line.
__runfiles_find_line_awk() {
  _rf_fl_val=$(__runfiles_awk '
    BEGIN { k = ARGV[1]; c = ARGV[2]; ARGV[1] = ARGV[2] = ""
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
# Resolving every prefix in one pass matters: a scan is a `read` loop costing
# microseconds per line, and one pass per candidate prefix would multiply that
# by the depth of the path.
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

# The awk search behind __runfiles_find_prefix: one pass applies the same rules
# as the scan and reports the escaped flag, key and value on three lines.
__runfiles_find_prefix_awk() {
  _rf_fp_out=$(__runfiles_awk '
    BEGIN { p = ARGV[1]; e = ARGV[2]; c = ARGV[3]; ARGV[1] = ARGV[2] = ARGV[3] = ""
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
# deferred, in particular the value, which is never copied out of a line that
# does not match. The reject is a single quoted `case`: a manifest key can only
# be a prefix of the path if the path starts with it.
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
    # An entry with an empty value is treated as absent: it does not stop the
    # walk up the path prefixes.
    [ -n "$_rf_fp_v" ] || continue
    _rf_fp_key="$_rf_fp_k"
    _rf_fp_klen=${#_rf_fp_k}
    _rf_fp_val="$_rf_fp_v"
    _rf_fp_esc="$_rf_fp_this_esc"
  done < "$1"
  [ -n "$_rf_fp_key" ]
}

# Find the first non-escaped manifest line whose value (target path) matches
# $1 and store its key (rlocation path) in _rf_ft_out; returns 1 if there is
# none. On Windows, matching is case-insensitive.
__runfiles_find_by_target() {
  _rf_ft_target="$1"
  _rf_ft_file="$2"
  _rf_ft_out=

  if [ -n "${_RULES_SHELL_RUNFILES_AWK:-}" ]; then
    _rf_ft_out=$(__runfiles_awk '
      BEGIN { t = ARGV[1]; c = ARGV[2]; ARGV[1] = ARGV[2] = ""; if (c) t = tolower(t) }
      substr($0, 1, 1) == " " { next }
      { i = index($0, " "); if (i == 0) next
        v = substr($0, i + 1); if (c) v = tolower(v)
        if (v == t) { printf "%s", substr($0, 1, i - 1); f = 1; exit } }
      END { exit !f }' "$_rf_ft_file" "$_rf_ft_target" "$_RLOCATION_CASE_INSENSITIVE") || return 1
    return 0
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
        _rf_ft_out="$_rf_ft_key"
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
        _rf_ft_out="$_rf_ft_key"
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
# is searched by awk like the manifest.
__runfiles_find_repo_mapping() {
  _rf_rm_src="$1"
  _rf_rm_pfx="$2"
  _rf_rm_tgt="$3"
  _rf_rm_file="$4"
  _rf_rm_out=

  if [ -n "${_RULES_SHELL_RUNFILES_AWK:-}" ]; then
    _rf_rm_out=$(__runfiles_awk '
      BEGIN { a = ARGV[1]; b = ARGV[2]; c = ARGV[3]; ARGV[1] = ARGV[2] = ARGV[3] = ""
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

# Parse the repository name from an exec path, into _rf_pe_out.
# Scans path segments for /bazel-out/<config>/bin/external/<repo>/ or
# /bazel-bin/external/<repo>/ and keeps the last matching <repo>; returns 1 if
# there is none.
# Equivalent to: grep -E -o '...' | tail -1 | awk -F/ '{print $(NF-1)}'
__runfiles_parse_exec_path_repo() {
  _rf_pe_path="$1"
  _rf_pe_out=""
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
      _rf_pe_out="$_rf_pe_seg"
    fi
    # Pattern: bazel-out/<config>/bin/external/<repo>
    if [ "$_rf_pe_p4" = "bazel-out" ] && [ "$_rf_pe_p2" = "bin" ] \
       && [ "$_rf_pe_p1" = "external" ] && [ -n "$_rf_pe_seg" ]; then
      _rf_pe_out="$_rf_pe_seg"
    fi

    _rf_pe_p4="$_rf_pe_p3"
    _rf_pe_p3="$_rf_pe_p2"
    _rf_pe_p2="$_rf_pe_p1"
    _rf_pe_p1="$_rf_pe_seg"

    [ -z "$_rf_pe_rest" ] && break
  done

  [ -n "$_rf_pe_out" ]
}

# --- Public API ---

# Prints to stdout the runtime location of a data-dependency.
# The optional second argument specifies the canonical name of the repository
# whose repository mapping should be used to resolve the repository part of
# the provided path. If not specified:
#   * Under bash, the caller's repository is auto-detected via BASH_SOURCE.
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
    _rf_rl_target_apparent="${1%%/*}"
    _rf_rl_remainder=
    case "$1" in
      */*) _rf_rl_remainder="${1#*/}" ;;
    esac
    if [ -n "$_rf_rl_remainder" ]; then
      _rf_rl_source_repo=
      if [ -n "${2+x}" ]; then
        _rf_rl_source_repo="$2"
      elif [ -n "${BASH_VERSION:-}" ]; then
        # Idx 1 is rlocation's caller. The status is ignored: a script outside
        # the runfiles tree still yields the repository parsed from its exec
        # path, and one that cannot be resolved at all yields the main one.
        __runfiles_current_repository 1 || true
        _rf_rl_source_repo="$_rf_cr_out"
      fi
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1): looking up canonical name for ($_rf_rl_target_apparent) from ($_rf_rl_source_repo) in ($RUNFILES_REPO_MAPPING)"
      __runfiles_compute_repo_prefix "$_rf_rl_source_repo"
      _rf_rl_source_prefix="$_rf_cp_out"
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1): matching source_repo ($_rf_rl_source_repo) or prefix ($_rf_rl_source_prefix) with target ($_rf_rl_target_apparent)"
      __runfiles_find_repo_mapping "$_rf_rl_source_repo" "$_rf_rl_source_prefix" "$_rf_rl_target_apparent" "$RUNFILES_REPO_MAPPING" || true
      _rf_rl_target_repo="$_rf_rm_out"
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1): canonical name of target repo is ($_rf_rl_target_repo)"
      if [ -n "$_rf_rl_target_repo" ]; then
        _rf_rl_path="$_rf_rl_target_repo/$_rf_rl_remainder"
      else
        _rf_rl_path="$1"
      fi
    else
      _rf_rl_path="$1"
    fi
  else
    __runfiles_debug "INFO[runfiles.sh]: rlocation($1): not using repository mapping (${RUNFILES_REPO_MAPPING:-}) since it does not exist"
    _rf_rl_path="$1"
  fi

  runfiles_rlocation_checked "$_rf_rl_path"
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

}

# The repository of a script that is not in the runfiles tree (the sh_binary
# entrypoint, or a binary run directly from bazel-bin), parsed from its path
# under the execroot, into _rf_cr_out: empty for the main repository. $1 is the
# normalized path, $2 the argument runfiles_current_repository was called
# with, for the diagnostic.
__runfiles_exec_path_repository() {
  __runfiles_parse_exec_path_repo "$1" || true
  _rf_cr_out="$_rf_pe_out"
  _rf_cr_have=1
  if [ -n "$_rf_cr_out" ]; then
    __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository($2): ($1) lies in repository ($_rf_cr_out) (parsed exec path)"
  else
    __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository($2): ($1) lies in the main repository (parsed exec path)"
  fi
}

# Prints the canonical name of the Bazel repository containing the calling
# script.
#
# Calling convention:
#   * Under bash, the optional first argument is a numeric index N (default
#     1) selecting the N-th caller via BASH_SOURCE, so bash consumers can call
#     runfiles_current_repository with no arguments.
#   * Under a POSIX shell there is no BASH_SOURCE, so the caller must supply
#     its own script path as the first argument:
#
#       runfiles_current_repository "$0"
#
# Note: This function only works correctly with Bzlmod enabled. Without
# Bzlmod, its return value is ignored if passed to rlocation.
runfiles_current_repository() {
  if __runfiles_current_repository "$@"; then
    _rf_cr_status=0
  else
    _rf_cr_status=$?
  fi
  if [ -n "$_rf_cr_have" ]; then
    printf '%s\n' "$_rf_cr_out"
  fi
  return $_rf_cr_status
}

# The lookup behind runfiles_current_repository, with the same arguments and
# return status, into _rf_cr_out; _rf_cr_have is non-empty when there is a
# result, which there is not when no caller could be resolved. Stored rather
# than printed so that rlocation, which needs the caller's repository on every
# lookup under bash, does not fork for it. A numeric index counts callers from
# the function that called this one, so the wrapper passes it through as is.
__runfiles_current_repository() {
  _rf_cr_out=
  _rf_cr_have=
  _rf_cr_raw=
  _rf_arg="${1:-}"
  # Non-numeric arg: caller passed a script path (POSIX calling convention).
  # Accepted under both bash and POSIX so portable scripts work.
  case "$_rf_arg" in
    *[!0123456789]*) _rf_cr_raw="$_rf_arg" ;;
  esac
  if [ -z "$_rf_cr_raw" ]; then
    if [ -n "${BASH_VERSION:-}" ]; then
      # Empty arg defaults to idx=1 (bash convention, N-th caller); BASH_SOURCE
      # counts from this function, one frame deeper, hence the + 1.
      # BASH_SOURCE array indexing is bash-only syntax; hide it from POSIX
      # shells via eval so parsing succeeds. `:-` guards against out-of-bounds
      # indices under `set -u`.
      eval '_rf_cr_raw="${BASH_SOURCE[$((${_rf_arg:-1} + 1))]:-}"'
      if [ -z "$_rf_cr_raw" ]; then
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
  if __runfiles_is_abs "$_rf_cr_raw"; then
    _rf_cr_caller="$_rf_cr_raw"
  else
    # dirname/basename without external binaries
    case "$_rf_cr_raw" in
      */*) _rf_dir="${_rf_cr_raw%/*}"; [ -z "$_rf_dir" ] && _rf_dir="/" ;;
      *)   _rf_dir="." ;;
    esac
    _rf_base="${_rf_cr_raw##*/}"
    _rf_cr_caller="$(cd "$_rf_dir" || return 1; pwd)/$_rf_base"
  fi
  __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): caller's path is ($_rf_cr_caller)"

  _rf_cr_path=

  # If the runfiles manifest exists, search for an entry with target the
  # caller's path.
  if [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    __runfiles_normalize_backslashes "$_rf_cr_caller"
    _rf_cr_norm="$_rf_nb_out"
    _rf_cr_escaped="$_rf_cr_norm"
    __runfiles_find_by_target "$_rf_cr_escaped" "$RUNFILES_MANIFEST_FILE" || true
    _rf_cr_path="$_rf_ft_out"
    if [ -z "$_rf_cr_path" ]; then
      __runfiles_debug "ERROR[runfiles.sh]: runfiles_current_repository(${1:-}): ($_rf_cr_norm) is not the target of an entry in the runfiles manifest ($RUNFILES_MANIFEST_FILE)"
      __runfiles_exec_path_repository "$_rf_cr_norm" "${1:-}"
      return 1
    else
      __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($_rf_cr_norm) is the target of ($_rf_cr_path) in the runfiles manifest"
    fi
  fi

  # If the runfiles directory exists, check if the caller's path is of the
  # form $RUNFILES_DIR/rlocation_path and if so, set $_rf_cr_path.
  if [ -z "$_rf_cr_path" ] && [ -d "${RUNFILES_DIR:-/dev/null}" ]; then
    __runfiles_normalize_backslashes "$_rf_cr_caller"
    _rf_cr_norm="$_rf_nb_out"
    _rf_rd="${RUNFILES_DIR%/}"
    _rf_rd="${_rf_rd%\\}"
    __runfiles_normalize_backslashes "$_rf_rd"
    _rf_cr_norm_dir="$_rf_nb_out"
    if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
      __runfiles_tolower "$_rf_cr_norm"
      _rf_cr_norm="$_rf_tl_out"
      __runfiles_tolower "$_rf_cr_norm_dir"
      _rf_cr_norm_dir="$_rf_tl_out"
    fi
    case "$_rf_cr_norm" in
      "$_rf_cr_norm_dir"/*)
        _rf_cr_path="${_rf_cr_norm#"$_rf_cr_norm_dir"}"
        _rf_cr_path="${_rf_cr_path#/}"
        ;;
    esac
    if [ -z "$_rf_cr_path" ]; then
      __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($_rf_cr_norm) does not lie under the runfiles directory ($_rf_cr_norm_dir)"
      __runfiles_exec_path_repository "$_rf_cr_norm" "${1:-}"
      return 0
    else
      __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($_rf_cr_caller) has path ($_rf_cr_path) relative to the runfiles directory ($RUNFILES_DIR)"
    fi
  fi

  if [ -z "$_rf_cr_path" ]; then
    __runfiles_debug "ERROR[runfiles.sh]: runfiles_current_repository(${1:-}): cannot determine repository for ($_rf_cr_caller) since neither the runfiles directory (${RUNFILES_DIR:-}) nor the runfiles manifest (${RUNFILES_MANIFEST_FILE:-}) exist"
    return 1
  fi

  __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($_rf_cr_caller) corresponds to rlocation path ($_rf_cr_path)"
  # Normalize the rlocation path to be of the form repo/pkg/file.
  _rf_cr_path="${_rf_cr_path#_main/external/}"
  _rf_cr_path="${_rf_cr_path#_main/../}"
  _rf_cr_repo="${_rf_cr_path%%/*}"
  _rf_cr_have=1
  if [ "$_rf_cr_repo" = "_main" ]; then
    __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($_rf_cr_path) lies in the main repository"
    _rf_cr_out=
  else
    __runfiles_debug "INFO[runfiles.sh]: runfiles_current_repository(${1:-}): ($_rf_cr_path) lies in repository ($_rf_cr_repo)"
    _rf_cr_out="$_rf_cr_repo"
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
# the file system, and print it, or an empty line if there is no such file.
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
  _rf_rc_depth="${2:-0}"
  if [ "$_rf_rc_depth" -gt 32 ]; then
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
    _rf_rc_key=; _rf_rc_escaped=; _rf_rc_suffix=
    case "$1" in
      *" "*|*"$_RULES_SHELL_RUNFILES_NL"*)
        # Backslashes first, so that the ones the other two escapes introduce
        # are left alone.
        __runfiles_gsub "$1" '\' '\b'
        __runfiles_gsub "$_rf_gs_out" ' ' '\s'
        __runfiles_gsub "$_rf_gs_out" "$_RULES_SHELL_RUNFILES_NL" '\n'
        _rf_rc_key="$_rf_gs_out"
        _rf_rc_escaped=1
        __runfiles_debug "INFO[runfiles.sh]: rlocation($1): using escaped search key ($_rf_rc_key)"
        ;;
      *)
        _rf_rc_key="$1"
        _rf_rc_escaped=
        ;;
    esac

    # Look for $1 itself first: the overwhelmingly common case, served by awk
    # or by a scan that rejects a line with a single `case`.
    #
    # An entry with an empty value counts as absent, hence the test on
    # _rf_fl_val rather than on the exit status.
    _rf_rc_result=
    if __runfiles_find_line "${_rf_rc_escaped:+ }$_rf_rc_key" "$RUNFILES_MANIFEST_FILE" &&
      [ -n "$_rf_fl_val" ]; then
      _rf_rc_result="$_rf_fl_val"
      _rf_rc_suffix=
    elif [ "${1%/*}" != "$1" ] &&
      __runfiles_find_prefix "$1" "$RUNFILES_MANIFEST_FILE" "$_rf_rc_key" "$_rf_rc_escaped"; then
      # $1 is not listed, but it may lie under a directory that is. One extra
      # scan resolves every path prefix at once; a path without a separator
      # skips the walk entirely, as the _repo_mapping lookup does.
      _rf_rc_result="$_rf_fp_val"
      _rf_rc_escaped="$_rf_fp_esc"
      _rf_rc_suffix="$_rf_fp_suffix"
    else
      __runfiles_debug "INFO[runfiles.sh]: rlocation($1): not found in manifest"
      printf '%s\n' ""
      return 0
    fi
    if [ -n "$_rf_rc_escaped" ]; then
      __runfiles_gsub "$_rf_rc_result" '\n' "$_RULES_SHELL_RUNFILES_NL"
      __runfiles_gsub "$_rf_gs_out" '\b' '\'
      _rf_rc_result="$_rf_gs_out"
    fi
    # When a hit that came from a path prefix does not resolve, there is
    # deliberately no retry with a shorter one, for two reasons:
    # 1. Manifests generated by Bazel never contain a path that is a prefix
    #    of another path.
    # 2. Runfiles libraries for other languages do not check for file
    #    existence and would have returned the non-existent path. It seems
    #    better to return no path rather than a potentially different,
    #    non-empty path.
    __runfiles_resolve_manifest_target "${1%"$_rf_rc_suffix"}" "$_rf_rc_result" "$_rf_rc_suffix" "$_rf_rc_depth"
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
    __runfiles_find_line \
    __runfiles_find_line_awk \
    __runfiles_find_line_scan \
    __runfiles_find_prefix \
    __runfiles_find_prefix_awk \
    __runfiles_find_prefix_scan \
    __runfiles_find_by_target \
    __runfiles_find_repo_mapping \
    __runfiles_parse_exec_path_repo \
    __runfiles_exec_path_repository \
    __runfiles_current_repository \
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

# The repo mapping manifest may not exist with old versions of Bazel.
RUNFILES_REPO_MAPPING=$(runfiles_rlocation_checked _repo_mapping || echo "")
export RUNFILES_REPO_MAPPING
