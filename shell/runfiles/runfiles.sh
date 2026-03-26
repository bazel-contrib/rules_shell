# shellcheck disable=SC2148,SC3043
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

# Runfiles lookup library for Bazel-built shell binaries and tests.
# Pure POSIX shell implementation — no external binary dependencies.
#
# This is a POSIX shell port of runfiles.bash. All string processing is done
# with shell builtins and parameter expansion; no grep, sed, awk, cut, tr,
# dirname, basename, wc, tail, or uname calls.
#
# DIFFERENCES FROM runfiles.bash:
# - runfiles_current_repository() requires the caller's script path as its
#   first argument instead of using BASH_SOURCE (no POSIX equivalent).
# - rlocation() without a second argument defaults to the main repository
#   instead of auto-detecting via BASH_SOURCE. Pass the source repo name
#   explicitly when calling from a non-main repository.
# - Functions are not exported (no POSIX equivalent of export -f). Each
#   script that needs runfiles must source this library directly.
#
# ENVIRONMENT:
# - If RUNFILES_LIB_DEBUG=1 is set, the script will print diagnostic messages
#   to stderr.
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
#     The runfiles library itself defines rlocation which you would need to
#     look up the library's runtime location, thus we have a chicken-and-egg
#     problem. Insert the following code snippet to the top of your main
#     script:
#
#       # --- begin runfiles.sh initialization v1 ---
#       # Copy-pasted from the Bazel POSIX shell runfiles library v1.
#       set +e; f=shell/runfiles/runfiles.sh
#       _rf_s() { [ -f "$1" ] || return 1; while IFS= read -r _rf_l; do \
#         case "$_rf_l" in "$f "*) . "${_rf_l#"$f "}"; return $?;; esac; \
#         done < "$1"; return 1; }
#       # shellcheck disable=SC1090
#       . "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
#         _rf_s "${RUNFILES_MANIFEST_FILE:-/dev/null}" 2>/dev/null || \
#         . "$0.runfiles/$f" 2>/dev/null || \
#         _rf_s "$0.runfiles_manifest" 2>/dev/null || \
#         _rf_s "$0.exe.runfiles_manifest" 2>/dev/null || \
#         { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
#       unset -f _rf_s 2>/dev/null; unset _rf_l 2>/dev/null
#       # --- end runfiles.sh initialization v1 ---
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
  elif [ -f "$0.runfiles/bazel_tools/tools/sh/runfiles/runfiles.sh" ]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi

# Platform detection: try uname, default to unix if unavailable.
_rf_os="$(uname -s 2>/dev/null)" || _rf_os="unknown"
case "$_rf_os" in
  MSYS*|MINGW*|CYGWIN*|msys*|mingw*|cygwin*)
    export _RLOCATION_ISABS_WINDOWS=1
    export _RLOCATION_CASE_INSENSITIVE=1
    ;;
  *)
    export _RLOCATION_ISABS_WINDOWS=
    export _RLOCATION_CASE_INSENSITIVE=
    ;;
esac

# Literal newline for use in case patterns and string comparisons.
_RUNFILES_NL='
'
export _RUNFILES_NL

# --- Internal helper functions ---

# Returns 0 if $1 is an absolute path, 1 otherwise.
__runfiles_is_abs() {
  case "$1" in
    /[!/]*) return 0 ;;
  esac
  if [ -n "$_RLOCATION_ISABS_WINDOWS" ]; then
    case "$1" in
      [a-zA-Z]:[/\\]*) return 0 ;;
    esac
  fi
  return 1
}

# Convert ASCII uppercase to lowercase (pure shell, no tr).
# Only called on Windows for case-insensitive path comparison.
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
  printf '%s' "$_rf_tl_out"
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

# Replace all occurrences of $2 in $1 with $3.
# Equivalent to: ${1//$2/$3} (bash-only).
__runfiles_gsub() {
  _rf_gs_in="$1"
  _rf_gs_old="$2"
  _rf_gs_new="$3"
  _rf_gs_out=""
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
  printf '%s' "$_rf_gs_out"
}

# Encode a runfiles path for manifest lookup: \ -> \b, space -> \s.
# Newlines must be handled separately by the caller (\n).
# Equivalent to: sed 's/\\/\\b/g; s/ /\\s/g'
__runfiles_encode_manifest_path() {
  _rf_em_in="$1"
  _rf_em_out=""
  while [ -n "$_rf_em_in" ]; do
    _rf_em_c="${_rf_em_in%"${_rf_em_in#?}"}"
    _rf_em_in="${_rf_em_in#?}"
    case "$_rf_em_c" in
      "\\") _rf_em_out="${_rf_em_out}\\b" ;;
      " ")  _rf_em_out="${_rf_em_out}\\s" ;;
      *)    _rf_em_out="${_rf_em_out}${_rf_em_c}" ;;
    esac
  done
  printf '%s' "$_rf_em_out"
}

# Compute the wildcard prefix for repo mapping lookups.
# For repo names like "my_module++ext+repo1", replaces the trailing segment
# of safe chars ([-a-zA-Z0-9_.]) after the last separator with *.
# Returns the input unchanged if no separator is found.
# Equivalent to: sed 's/\(.*[^-a-zA-Z0-9_.]\)[-a-zA-Z0-9_.]\{1,\}/\1*/'
__runfiles_compute_repo_prefix() {
  _rf_cp_repo="$1"
  _rf_cp_trim="$_rf_cp_repo"
  while [ -n "$_rf_cp_trim" ]; do
    _rf_cp_last="${_rf_cp_trim#"${_rf_cp_trim%?}"}"
    case "$_rf_cp_last" in
      [-a-zA-Z0-9_.]) _rf_cp_trim="${_rf_cp_trim%?}" ;;
      *)
        printf '%s*' "$_rf_cp_trim"
        return 0
        ;;
    esac
  done
  printf '%s' "$_rf_cp_repo"
}

# Find the first line in $2 starting with "$1 " and print the value
# (everything after the prefix and the separating space).
# On Windows (_RLOCATION_CASE_INSENSITIVE=1), matching is case-insensitive
# but the value is returned with its original casing.
__runfiles_find_line() {
  _rf_fl_pfx="$1"
  _rf_fl_file="$2"
  _rf_fl_pfx_sp="${_rf_fl_pfx} "

  if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
    _rf_fl_lpfx="$(__runfiles_tolower "$_rf_fl_pfx_sp")"
    _rf_fl_plen=${#_rf_fl_pfx_sp}
    while IFS= read -r _rf_fl_line || [ -n "$_rf_fl_line" ]; do
      _rf_fl_lline="$(__runfiles_tolower "$_rf_fl_line")"
      case "$_rf_fl_lline" in
        "${_rf_fl_lpfx}"*)
          _rf_fl_val="$_rf_fl_line"
          _rf_fl_i=0
          while [ "$_rf_fl_i" -lt "$_rf_fl_plen" ]; do
            _rf_fl_val="${_rf_fl_val#?}"
            _rf_fl_i=$((_rf_fl_i + 1))
          done
          printf '%s\n' "$_rf_fl_val"
          return 0
          ;;
      esac
    done < "$_rf_fl_file"
  else
    while IFS= read -r _rf_fl_line || [ -n "$_rf_fl_line" ]; do
      case "$_rf_fl_line" in
        "${_rf_fl_pfx_sp}"*)
          printf '%s\n' "${_rf_fl_line#"${_rf_fl_pfx_sp}"}"
          return 0
          ;;
      esac
    done < "$_rf_fl_file"
  fi
  return 1
}

# Find the first non-escaped manifest line whose value (target path) matches
# $1. Prints the key (rlocation path) on stdout.
# On Windows, matching is case-insensitive.
__runfiles_find_by_target() {
  _rf_ft_target="$1"
  _rf_ft_file="$2"

  if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
    _rf_ft_ltgt="$(__runfiles_tolower "$_rf_ft_target")"
    while IFS= read -r _rf_ft_line || [ -n "$_rf_ft_line" ]; do
      case "$_rf_ft_line" in " "*) continue ;; esac
      _rf_ft_key="${_rf_ft_line%% *}"
      _rf_ft_val="${_rf_ft_line#* }"
      if [ "$(__runfiles_tolower "$_rf_ft_val")" = "$_rf_ft_ltgt" ]; then
        printf '%s' "$_rf_ft_key"
        return 0
      fi
    done < "$_rf_ft_file"
  else
    while IFS= read -r _rf_ft_line || [ -n "$_rf_ft_line" ]; do
      case "$_rf_ft_line" in " "*) continue ;; esac
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
# Prints the canonical target repo name.
# On Windows, matching is case-insensitive.
__runfiles_find_repo_mapping() {
  _rf_rm_src="$1"
  _rf_rm_pfx="$2"
  _rf_rm_tgt="$3"
  _rf_rm_file="$4"

  if [ -n "$_RLOCATION_CASE_INSENSITIVE" ]; then
    _rf_rm_ls="$(__runfiles_tolower "$_rf_rm_src")"
    _rf_rm_lp="$(__runfiles_tolower "$_rf_rm_pfx")"
    _rf_rm_lt="$(__runfiles_tolower "$_rf_rm_tgt")"
    while IFS= read -r _rf_rm_line || [ -n "$_rf_rm_line" ]; do
      _rf_rm_ll="$(__runfiles_tolower "$_rf_rm_line")"
      case "$_rf_rm_ll" in
        "${_rf_rm_ls},${_rf_rm_lt},"*|"${_rf_rm_lp},${_rf_rm_lt},"*)
          _rf_rm_rest="${_rf_rm_line#*,}"
          printf '%s' "${_rf_rm_rest#*,}"
          return 0
          ;;
      esac
    done < "$_rf_rm_file"
  else
    while IFS= read -r _rf_rm_line || [ -n "$_rf_rm_line" ]; do
      case "$_rf_rm_line" in
        "${_rf_rm_src},${_rf_rm_tgt},"*|"${_rf_rm_pfx},${_rf_rm_tgt},"*)
          _rf_rm_rest="${_rf_rm_line#*,}"
          printf '%s' "${_rf_rm_rest#*,}"
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
# the provided path. If not specified, the main repository is assumed.
# (In runfiles.bash, auto-detection via BASH_SOURCE is used instead.)
rlocation() {
  if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
    echo >&2 "INFO[runfiles.sh]: rlocation($1): start"
  fi
  if __runfiles_is_abs "$1"; then
    if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
      echo >&2 "INFO[runfiles.sh]: rlocation($1): absolute path, return"
    fi
    printf '%s\n' "$1"
    return 0
  fi
  case "$1" in
    ../*|*/..|./*|*/./*|*/.|*//*) # shellcheck disable=SC2254
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "ERROR[runfiles.sh]: rlocation($1): path is not normalized"
      fi
      return 1
      ;;
    \\*)
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "ERROR[runfiles.sh]: rlocation($1): absolute path without" \
                 "drive name"
      fi
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
      if [ -z "${2+x}" ]; then
        local source_repo=""
      else
        local source_repo="$2"
      fi
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "INFO[runfiles.sh]: rlocation($1): looking up canonical name for ($target_repo_apparent_name) from ($source_repo) in ($RUNFILES_REPO_MAPPING)"
      fi
      local source_repo_prefix
      source_repo_prefix="$(__runfiles_compute_repo_prefix "$source_repo")"
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "INFO[runfiles.sh]: rlocation($1): matching source_repo ($source_repo) or prefix ($source_repo_prefix) with target ($target_repo_apparent_name)"
      fi
      local target_repo
      target_repo="$(__runfiles_find_repo_mapping "$source_repo" "$source_repo_prefix" "$target_repo_apparent_name" "$RUNFILES_REPO_MAPPING")" || true
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "INFO[runfiles.sh]: rlocation($1): canonical name of target repo is ($target_repo)"
      fi
      if [ -n "$target_repo" ]; then
        local rlocation_path="$target_repo/$remainder"
      else
        local rlocation_path="$1"
      fi
    else
      local rlocation_path="$1"
    fi
  else
    if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
      echo >&2 "INFO[runfiles.sh]: rlocation($1): not using repository mapping (${RUNFILES_REPO_MAPPING:-}) since it does not exist"
    fi
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
}

# Returns the canonical name of the Bazel repository containing the given
# script path.
#
# Unlike runfiles.bash which uses BASH_SOURCE to auto-detect the caller,
# this function requires the caller's script path as the first argument:
#
#   runfiles_current_repository "$0"
#
# Note: This function only works correctly with Bzlmod enabled. Without
# Bzlmod, its return value is ignored if passed to rlocation.
runfiles_current_repository() {
  local raw_caller_path="$1"
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
  if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
    echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): caller's path is ($caller_path)"
  fi

  local rlocation_path=

  # If the runfiles manifest exists, search for an entry with target the
  # caller's path.
  if [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    local normalized_caller_path
    normalized_caller_path="$(__runfiles_normalize_backslashes "$caller_path")"
    local escaped_caller_path="$normalized_caller_path"
    rlocation_path="$(__runfiles_find_by_target "$escaped_caller_path" "$RUNFILES_MANIFEST_FILE")" || true
    if [ -z "$rlocation_path" ]; then
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "ERROR[runfiles.sh]: runfiles_current_repository($1): ($normalized_caller_path) is not the target of an entry in the runfiles manifest ($RUNFILES_MANIFEST_FILE)"
      fi
      local repository
      repository="$(__runfiles_parse_exec_path_repo "$normalized_caller_path")" || true
      if [ -n "$repository" ]; then
        if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
          echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($normalized_caller_path) lies in repository ($repository) (parsed exec path)"
        fi
        printf '%s\n' "$repository"
      else
        if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
          echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($normalized_caller_path) lies in the main repository (parsed exec path)"
        fi
        printf '%s\n' ""
      fi
      return 1
    else
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($normalized_caller_path) is the target of ($rlocation_path) in the runfiles manifest"
      fi
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
      normalized_caller_path="$(__runfiles_tolower "$normalized_caller_path")"
      normalized_dir="$(__runfiles_tolower "$normalized_dir")"
    fi
    case "$normalized_caller_path" in
      "$normalized_dir"/*)
        rlocation_path="${normalized_caller_path#"$normalized_dir"}"
        rlocation_path="${rlocation_path#/}"
        ;;
    esac
    if [ -z "$rlocation_path" ]; then
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($normalized_caller_path) does not lie under the runfiles directory ($normalized_dir)"
      fi
      local repository
      repository="$(__runfiles_parse_exec_path_repo "$normalized_caller_path")" || true
      if [ -n "$repository" ]; then
        if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
          echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($normalized_caller_path) lies in repository ($repository) (parsed exec path)"
        fi
        printf '%s\n' "$repository"
      else
        if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
          echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($normalized_caller_path) lies in the main repository (parsed exec path)"
        fi
        printf '%s\n' ""
      fi
      return 0
    else
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($caller_path) has path ($rlocation_path) relative to the runfiles directory ($RUNFILES_DIR)"
      fi
    fi
  fi

  if [ -z "$rlocation_path" ]; then
    if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
      echo >&2 "ERROR[runfiles.sh]: runfiles_current_repository($1): cannot determine repository for ($caller_path) since neither the runfiles directory (${RUNFILES_DIR:-}) nor the runfiles manifest (${RUNFILES_MANIFEST_FILE:-}) exist"
    fi
    return 1
  fi

  if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
    echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($caller_path) corresponds to rlocation path ($rlocation_path)"
  fi
  # Normalize the rlocation path to be of the form repo/pkg/file.
  rlocation_path="${rlocation_path#_main/external/}"
  rlocation_path="${rlocation_path#_main/../}"
  local repository="${rlocation_path%%/*}"
  if [ "$repository" = "_main" ]; then
    if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
      echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($rlocation_path) lies in the main repository"
    fi
    printf '%s\n' ""
  else
    if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
      echo >&2 "INFO[runfiles.sh]: runfiles_current_repository($1): ($rlocation_path) lies in repository ($repository)"
    fi
    printf '%s\n' "$repository"
  fi
}

runfiles_rlocation_checked() {
  # FIXME: If the runfiles lookup fails, the exit code of this function is 0
  #  if and only if the runfiles manifest exists. In particular, the exit code
  #  behavior is not consistent across platforms.
  if [ -e "${RUNFILES_DIR:-/dev/null}/$1" ]; then
    if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
      echo >&2 "INFO[runfiles.sh]: rlocation($1): found under RUNFILES_DIR ($RUNFILES_DIR), return"
    fi
    printf '%s\n' "${RUNFILES_DIR}/$1"
  elif [ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]; then
    if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
      echo >&2 "INFO[runfiles.sh]: rlocation($1): looking in RUNFILES_MANIFEST_FILE ($RUNFILES_MANIFEST_FILE)"
    fi
    # If the rlocation path contains a space or newline, it needs to be
    # prefixed with a space and spaces, newlines, and backslashes have to be
    # escaped as \s, \n, and \b.
    local search_prefix escaped
    case "$1" in
      *" "*|*"$_RUNFILES_NL"*)
        search_prefix=" $(__runfiles_encode_manifest_path "$1")"
        search_prefix="$(__runfiles_gsub "$search_prefix" "$_RUNFILES_NL" '\n')"
        escaped=true
        if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
          echo >&2 "INFO[runfiles.sh]: rlocation($1): using escaped search prefix ($search_prefix)"
        fi
        ;;
      *)
        search_prefix="$1"
        escaped=false
        ;;
    esac
    local result
    result="$(__runfiles_find_line "$search_prefix" "$RUNFILES_MANIFEST_FILE")" || true
    if [ -z "$result" ]; then
      # If path references a runfile that lies under a directory that itself
      # is a runfile, then only the directory is listed in the manifest. Look
      # up all prefixes of path in the manifest and append the relative path
      # from the prefix if there is a match.
      local prefix="$1"
      local prefix_result=
      local new_prefix=
      while true; do
        new_prefix="${prefix%/*}"
        [ "$new_prefix" = "$prefix" ] && break
        prefix="$new_prefix"
        if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
          echo >&2 "INFO[runfiles.sh]: rlocation($1): looking for prefix ($prefix)"
        fi
        case "$prefix" in
          *" "*|*"$_RUNFILES_NL"*)
            search_prefix=" $(__runfiles_encode_manifest_path "$prefix")"
            search_prefix="$(__runfiles_gsub "$search_prefix" "$_RUNFILES_NL" '\n')"
            escaped=true
            if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
              echo >&2 "INFO[runfiles.sh]: rlocation($1): using escaped search prefix ($search_prefix)"
            fi
            ;;
          *)
            search_prefix="$prefix"
            escaped=false
            ;;
        esac
        prefix_result="$(__runfiles_find_line "$search_prefix" "$RUNFILES_MANIFEST_FILE")" || true
        if [ "$escaped" = true ] && [ -n "$prefix_result" ]; then
          prefix_result="$(__runfiles_gsub "$prefix_result" '\n' "$_RUNFILES_NL")"
          prefix_result="$(__runfiles_gsub "$prefix_result" '\b' '\')"
        fi
        [ -z "$prefix_result" ] && continue
        local candidate="${prefix_result}${1#"${prefix}"}"
        if [ -e "$candidate" ]; then
          if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
            echo >&2 "INFO[runfiles.sh]: rlocation($1): found in manifest as ($candidate) via prefix ($prefix)"
          fi
          printf '%s\n' "$candidate"
          return 0
        fi
        # At this point, the manifest lookup of prefix has been successful,
        # but the file at the relative path given by the suffix does not
        # exist. We do not continue the lookup with a shorter prefix for two
        # reasons:
        # 1. Manifests generated by Bazel never contain a path that is a
        #    prefix of another path.
        # 2. Runfiles libraries for other languages do not check for file
        #    existence and would have returned the non-existent path. It
        #    seems better to return no path rather than a potentially
        #    different, non-empty path.
        if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
          echo >&2 "INFO[runfiles.sh]: rlocation($1): found in manifest as ($candidate) via prefix ($prefix), but file does not exist"
        fi
        break
      done
      if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
        echo >&2 "INFO[runfiles.sh]: rlocation($1): not found in manifest"
      fi
      printf '%s\n' ""
    else
      if [ "$escaped" = true ]; then
        result="$(__runfiles_gsub "$result" '\n' "$_RUNFILES_NL")"
        result="$(__runfiles_gsub "$result" '\b' '\')"
      fi
      if [ -e "$result" ]; then
        if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
          echo >&2 "INFO[runfiles.sh]: rlocation($1): found in manifest as ($result)"
        fi
        printf '%s\n' "$result"
      else
        if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
          echo >&2 "INFO[runfiles.sh]: rlocation($1): found in manifest as ($result), but file does not exist"
        fi
        printf '%s\n' ""
      fi
    fi
  else
    if [ "${RUNFILES_LIB_DEBUG:-}" = 1 ]; then
      echo >&2 "ERROR[runfiles.sh]: cannot look up runfile \"$1\" " \
               "(RUNFILES_DIR=\"${RUNFILES_DIR:-}\"," \
               "RUNFILES_MANIFEST_FILE=\"${RUNFILES_MANIFEST_FILE:-}\")"
    fi
    return 1
  fi
}

# The repo mapping manifest may not exist with old versions of Bazel.
RUNFILES_REPO_MAPPING=$(runfiles_rlocation_checked _repo_mapping || echo "")
export RUNFILES_REPO_MAPPING
