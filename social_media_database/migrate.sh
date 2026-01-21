#!/bin/bash
# Simple migration runner that reuses sql_init.sh for initial setup.
# Creates a marker file after first successful run.

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
MARKER="${BASE_DIR}/.migrations_applied"

if [ -f "${MARKER}" ]; then
  echo "Migrations already applied. Nothing to do."
  exit 0
fi

bash "${BASE_DIR}/sql_init.sh"

touch "${MARKER}"
echo "Migrations applied and marker created at ${MARKER}"
