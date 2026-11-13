#!/usr/bin/env bash
# Create the Python environment for OpenDrop and apply the local patches.
#
# Usage (from anywhere, without sudo):
#   bash scripts/setup-opendrop.sh
#
# Safe to run again: existing environment is reused, patches already applied
# are skipped.
set -eu

OPENDROP_VERSION=0.13.0

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VENV="$REPO/.venv"
PATCH_DIR="$REPO/patches"

[ -d "$VENV" ] || python3 -m venv "$VENV"
# setuptools<81 still ships pkg_resources, which OpenDrop imports.
"$VENV/bin/pip" install --quiet --disable-pip-version-check "opendrop==$OPENDROP_VERSION" "setuptools<81"

SITE_PACKAGES=$("$VENV/bin/python" -c \
    'import opendrop, os; print(os.path.dirname(os.path.dirname(opendrop.__file__)))')

for patch_file in "$PATCH_DIR"/opendrop-*.patch; do
    name=$(basename "$patch_file")
    if patch --dry-run --reverse --force --silent -p1 -d "$SITE_PACKAGES" <"$patch_file" >/dev/null; then
        echo "already applied: $name"
    else
        patch --forward --silent -p1 -d "$SITE_PACKAGES" <"$patch_file"
        echo "applied: $name"
    fi
done

echo "OpenDrop $OPENDROP_VERSION ready in $VENV"
