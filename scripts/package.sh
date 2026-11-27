#!/usr/bin/env bash
set -euo pipefail

# Packages this repository's skill folder into a ZIP for use as a GitHub
# release asset.
#
# This repository stores skill files under go-standards/ and project files
# at the root. The ZIP root must be the skill folder, so this script stages
# a copy of that folder in a temp directory before zipping.
#
# Usage:
#   bash scripts/package.sh --output-dir <dir>
#
# Output:
#   <output-dir>/go-standards.zip

if [[ $# -ne 2 || "${1:-}" != "--output-dir" ]]; then
  echo "usage: bash ${0##*/} --output-dir <dir>" >&2
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

if ! command -v zip &>/dev/null; then
  echo "error: zip is required but not installed" >&2
  exit 1
fi

if [[ ! -d "${SKILL_DIR}" ]]; then
  echo "error: skill folder not found (${SKILL_DIR})" >&2
  exit 1
fi

if [[ ! -f "${SKILL_DIR}/SKILL.md" ]]; then
  echo "error: SKILL.md not found in skill folder (${SKILL_DIR})" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d)"
readonly STAGE_DIR
trap 'rm -rf "${STAGE_DIR}"' EXIT

readonly STAGE_SKILL_DIR="${STAGE_DIR}/${SKILL_NAME}"
mkdir -p "${STAGE_SKILL_DIR}"

cp -R "${SKILL_DIR}/." "${STAGE_SKILL_DIR}/"

if ! mkdir -p "${ASSET_DIR}"; then
  echo "error: cannot create output directory (${ASSET_DIR})" >&2
  exit 1
fi
readonly OUT_ZIP="${ASSET_DIR}/${SKILL_NAME}.zip"
rm -f "${OUT_ZIP}"

(cd "${STAGE_DIR}" && zip -r "${OUT_ZIP}" "${SKILL_NAME}/" --quiet)

echo "Release asset: ${OUT_ZIP}"
echo "ZIP root: ${SKILL_NAME}/SKILL.md"
