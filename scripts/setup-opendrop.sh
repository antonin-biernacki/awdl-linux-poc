#!/usr/bin/env bash
# Create the Python environment for OpenDrop and apply the local patches.
#
# Usage (from anywhere, without sudo):
#   bash scripts/setup-opendrop.sh
#
# Safe to run again: the environment is reused, OpenDrop is reinstalled
# unpatched, then every patch is applied in order. Checking each patch on its
# own is not reliable: a later patch can change the context of an earlier one.
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

# Start again from the original OpenDrop files.
"$VENV/bin/pip" install --quiet --disable-pip-version-check --force-reinstall --no-deps \
    "opendrop==$OPENDROP_VERSION"
rm -f "$SITE_PACKAGES"/opendrop/*.orig "$SITE_PACKAGES"/opendrop/*.rej

for patch_file in "$PATCH_DIR"/opendrop-*.patch; do
    patch --forward --silent --no-backup-if-mismatch -p1 -d "$SITE_PACKAGES" <"$patch_file"
    echo "applied: $(basename "$patch_file")"
done

echo "OpenDrop $OPENDROP_VERSION ready in $VENV"
