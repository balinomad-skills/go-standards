#!/usr/bin/env bash
set -euo pipefail

# Structural checks for this skill repository. Fails the build if any
# check finds a violation. Run locally before pushing:
#
#   bash scripts/structural-check.sh

readonly SCRIPT_VERSION="1.0"

if [[ "${1:-}" == "--version" ]]; then
  echo "structural-check.sh ${SCRIPT_VERSION}"
  exit 0
fi

if [[ $# -ne 0 ]]; then
  echo "usage: bash ${0##*/} [--version]" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# This repository stores the skill in exactly one top-level folder. Derive the
# name from the folder that contains SKILL.md, not from the checkout directory
# name, so a renamed checkout (for example a source archive) still works.
SKILL_MATCHES=()
while IFS= read -r candidate; do
  [[ -z "${candidate}" ]] && continue
  SKILL_MATCHES+=("${candidate}")
done < <(
  find "${REPO_ROOT}" -mindepth 1 -maxdepth 1 -type d \
    -exec test -f '{}/SKILL.md' \; -print | sort
)

if [[ ${#SKILL_MATCHES[@]} -ne 1 ]]; then
  echo "error: expected exactly one top-level skill folder containing SKILL.md under ${REPO_ROOT}, found ${#SKILL_MATCHES[@]}" >&2
  exit 1
fi

SKILL_NAME="$(basename "${SKILL_MATCHES[0]}")"
readonly SKILL_NAME
readonly SKILL_DIR="${REPO_ROOT}/${SKILL_NAME}"
readonly SKILL_MD="${SKILL_DIR}/SKILL.md"
FAILED=0

#######################################
# Record a structural failure and print its message.
# Globals:
#   FAILED
# Arguments:
#   $*  Failure message
# Outputs:
#   One failure line to STDERR
#######################################
err() {
  echo "FAIL: $*" >&2
  FAILED=1
}

#######################################
# Print a passing structural result to STDOUT.
# Arguments:
#   $*  Result message
# Outputs:
#   One result line to STDOUT
#######################################
info() {
  echo "OK: $*"
}

#######################################
# Check that the skill folder and SKILL.md exist.
# Globals:
#   SKILL_DIR, SKILL_MD
# Exits:
#   1 when either path is missing
#######################################
check_skill_md_exists() {
  if [[ ! -d "${SKILL_DIR}" ]]; then
    err "skill folder not found: ${SKILL_DIR}"
    exit 1
  fi
  if [[ ! -f "${SKILL_MD}" ]]; then
    err "SKILL.md not found in skill folder: ${SKILL_DIR}"
    exit 1
  fi
  info "SKILL.md present in skill folder"
}

#######################################
# Check that SKILL.md opens with usable frontmatter.
# Globals:
#   SKILL_MD, FAILED
# Outputs:
#   Failure lines to STDERR or result line to STDOUT
#######################################
check_frontmatter() {
  local first_line
  local frontmatter
  local missing=0

  first_line="$(head -n1 "${SKILL_MD}")"
  if [[ "${first_line}" != "---" ]]; then
    err "SKILL.md does not open with YAML frontmatter (---)"
    return
  fi

  if ! frontmatter="$(
    awk '
      NR == 1 && $0 == "---" {
        in_frontmatter = 1
        next
      }
      in_frontmatter && $0 == "---" {
        closed = 1
        exit
      }
      in_frontmatter {
        print
      }
      END {
        exit closed ? 0 : 1
      }
    ' "${SKILL_MD}"
  )"; then
    err "SKILL.md frontmatter has no closing (---)"
    return
  fi

  if ! grep -q "^name:" <<<"${frontmatter}"; then
    err "SKILL.md frontmatter is missing 'name:'"
    missing=1
  fi
  if ! grep -q "^description:" <<<"${frontmatter}"; then
    err "SKILL.md frontmatter is missing 'description:'"
    missing=1
  fi
  if [[ "${missing}" -eq 0 ]]; then
    info "frontmatter has name and description"
  fi
}

#######################################
# Compare SKILL.md routing references with reference files.
# Globals:
#   SKILL_DIR, SKILL_MD, FAILED
# Outputs:
#   Failure lines to STDERR or result line to STDOUT
#######################################
check_routing_table_matches_disk() {
  local routed_files disk_files
  local failed_before="${FAILED}"
  routed_files="$(
    grep -oE 'references/[a-zA-Z0-9_/-]+\.md' "${SKILL_MD}" | sort -u \
      || [[ $? -eq 1 ]]
  )"

  if [[ -d "${SKILL_DIR}/references" ]]; then
    disk_files="$(
      find "${SKILL_DIR}/references" \
        -type f \
        -name '*.md' \
        | sed "s|^${SKILL_DIR}/||" \
        | sort -u
    )"
  else
    disk_files=""
  fi

  # Every reference file on disk must appear in the routing table.
  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    if ! grep -qF "${f}" <<<"${routed_files}"; then
      err "references/*.md file with no routing table row: ${f}"
    fi
  done <<<"${disk_files}"

  # Every routing table reference must resolve to a real file.
  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    if [[ ! -f "${SKILL_DIR}/${f}" ]]; then
      err "SKILL.md routing table references a file that does not exist: ${f}"
    fi
  done <<<"${routed_files}"

  if [[ "${FAILED}" -eq "${failed_before}" ]]; then
    info "routing table checked against disk"
  fi
}

#######################################
# Check that reference links inside the skill resolve.
# Globals:
#   SKILL_DIR, FAILED
# Outputs:
#   Failure lines to STDERR or result line to STDOUT
#######################################
check_cross_references_resolve() {
  local all_refs
  local failed_before="${FAILED}"
  all_refs="$(
    grep -rohE 'references/[a-zA-Z0-9_/-]+\.md' \
      "${SKILL_DIR}" \
      --include='*.md' \
      | sort -u \
      || [[ $? -eq 1 ]]
  )"
  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    if [[ ! -f "${SKILL_DIR}/${f}" ]]; then
      err "cross-reference points to a file that does not exist: ${f}"
    fi
  done <<<"${all_refs}"
  if [[ "${FAILED}" -eq "${failed_before}" ]]; then
    info "cross-references checked"
  fi
}

#######################################
# Run all structural checks and report the result.
# Globals:
#   FAILED
# Exits:
#   1 when any structural check fails
#######################################
main() {
  check_skill_md_exists
  check_frontmatter
  check_routing_table_matches_disk
  check_cross_references_resolve

  if [[ "${FAILED}" -eq 1 ]]; then
    echo "" >&2
    echo "One or more structural checks failed." >&2
    exit 1
  fi
  echo ""
  echo "All structural checks passed."
}

main "$@"
