#!/bin/sh
#
# One-time per-clone developer setup.
#
# Git deliberately never runs hooks straight from a clone (that would be remote code
# execution on `git clone`), so the checked-in .githooks directory has to be opted
# into explicitly. This is the whole of that opt-in.

set -eu

cd "$(dirname "$0")/.."

git config core.hooksPath .githooks
echo "core.hooksPath -> .githooks (staged Swift files are now formatted on commit)"
