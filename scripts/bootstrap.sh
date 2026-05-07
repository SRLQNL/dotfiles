#!/bin/sh
# Thin wrapper — delegates to install.sh.
# Kept for backwards compatibility and quick invocation.
#
# Usage: scripts/bootstrap.sh [install.sh options...]
#
# To install with a specific host profile:
#   scripts/bootstrap.sh --host myhostname
#
# To skip interactive prompts:
#   scripts/bootstrap.sh --yes

set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
exec "$DOTFILES_DIR/install.sh" "$@"
