#!/usr/bin/env bash
set -euo pipefail

# Combines this repository's skill folder into one flat text document for use
# as a GitHub release asset. The document uses boundaries and an instruction
# header an LLM can parse without file-upload or skill-execution support.
#
# Usage:
#   bash scripts/single-page.sh --output-dir <dir>
#   bash scripts/single-page.sh --version
#
# Output:
#   <output-dir>/go-standards.txt

readonly SCRIPT_VERSION="1.0"

if [[ "${1:-}" == "--version" ]]; then
  if [[ $# -ne 1 ]]; then
    echo "usage: bash ${0##*/} --output-dir <dir>" >&2
    echo "       bash ${0##*/} --version" >&2
    exit 2
  fi
  echo "single-page.sh ${SCRIPT_VERSION}"
  exit 0
fi

if [[ $# -ne 2 || "${1:-}" != "--output-dir" ]]; then
  echo "usage: bash ${0##*/} --output-dir <dir>" >&2
  echo "       bash ${0##*/} --version" >&2
  exit 2
fi

ASSET_ARG="${2%/}"
if [[ "${ASSET_ARG}" == /* ]]; then
  ASSET_DIR="${ASSET_ARG}"
else
  ASSET_DIR="${PWD}/${ASSET_ARG}"
fi
readonly ASSET_DIR

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

if [[ ! -d "${SKILL_DIR}" ]]; then
  echo "error: skill folder not found (${SKILL_DIR})" >&2
  exit 1
fi

if [[ ! -f "${SKILL_DIR}/SKILL.md" ]]; then
  echo "error: SKILL.md not found in skill folder (${SKILL_DIR})" >&2
  exit 1
fi

if ! mkdir -p "${ASSET_DIR}"; then
  echo "error: cannot create output directory (${ASSET_DIR})" >&2
  exit 1
fi
readonly OUT_FILE="${ASSET_DIR}/${SKILL_NAME}.txt"

#######################################
# Append one source file to the single-page output.
# Globals:
#   BOUNDARY, OUT_FILE
# Arguments:
#   $1  Source file path
#   $2  Relative path printed in the boundary
# Outputs:
#   None
#######################################
write_file_block() {
  local file="$1"
  local rel_path="$2"

  echo "--- BEGIN_FILE: ${BOUNDARY} : ${rel_path} ---" >>"${OUT_FILE}"
  cat "${file}" >>"${OUT_FILE}"
  if [[ -n "$(tail -c 1 "${file}")" ]]; then
    echo "" >>"${OUT_FILE}"
  fi
  echo "--- END_FILE: ${BOUNDARY} ---" >>"${OUT_FILE}"
  echo "" >>"${OUT_FILE}"
}

BOUNDARY_SOURCE="$(git -C "${REPO_ROOT}" describe --tags --always 2>/dev/null || true)"
if [[ -z "${BOUNDARY_SOURCE}" ]]; then
  BOUNDARY_SOURCE="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || true)"
fi
if [[ -z "${BOUNDARY_SOURCE}" ]]; then
  BOUNDARY_SOURCE="unversioned"
fi
BOUNDARY="BNDRY-${BOUNDARY_SOURCE}"
readonly BOUNDARY

cat <<EOF >"${OUT_FILE}"
[INSTRUCTION]
This document contains a consolidated context for the '${SKILL_NAME}' skill.
The following text contains one or more files, encapsulated by custom
boundaries.

File begin: --- BEGIN_FILE: ${BOUNDARY} : [filepath] ---
File end:   --- END_FILE: ${BOUNDARY} ---

1. Parse these boundaries to reconstruct the file structure in your context.
2. Do not output these boundaries in your responses.
3. Execution priority: scan SKILL.md for any defined starting protocol,
   preflight check, or initialization sequence. If found, execute that
   sequence immediately as your first output. If it asks a question,
   stop and wait for the answer.
[/INSTRUCTION]

EOF

write_file_block "${SKILL_DIR}/SKILL.md" "SKILL.md"

if [[ -d "${SKILL_DIR}/references" ]]; then
  while IFS= read -r file; do
    rel_path="${file#"${SKILL_DIR}"/}"
    write_file_block "${file}" "${rel_path}"
  done < <(find "${SKILL_DIR}/references" -type f -name '*.md' | sort)
fi

echo "Release asset: ${OUT_FILE}"
