#!/bin/bash
# Apply patches/*.patch, in order, to a source tree.  The tree is a copy of the
# submodule made by build-gnumeric.sh; the submodule itself is never modified
# (HANDOFF.md §6).  Each patch starts with a comment header explaining itself.
set -euo pipefail
src="${1:?usage: apply-patches.sh <source-dir>}"
cd "$(dirname "$0")/.."
shopt -s nullglob
for p in patches/*.patch; do
	echo "applying $p"
	patch -d "$src" -p1 --forward --no-backup-if-mismatch -s < "$p"
done
