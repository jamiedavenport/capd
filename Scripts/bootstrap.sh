#!/bin/sh
# Git never runs hooks straight from a clone, so this opt-in is per clone.

set -eu

cd "$(dirname "$0")/.."

git config core.hooksPath .githooks
echo "core.hooksPath -> .githooks"
