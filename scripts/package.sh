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

SKILL_NAME="go-standards"
readonly SKILL_NAME
readonly SKILL_DIR="${REPO_ROOT}/${SKILL_NAME}"

if ! command -v zip &>/dev/null; then
  echo "error: zip is required but not installed" >&2
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
