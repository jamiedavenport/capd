#!/bin/sh
# Prepares a checkout for development. Safe to re-run.

set -eu

cd "$(dirname "$0")/.."

# Git never runs hooks straight from a clone, so this opt-in is per clone.
git config core.hooksPath .githooks

swift package resolve
