#!/bin/bash
# Keep local `main` in lock-step with `origin/main` at session start so
# `git checkout main` later in the session doesn't surface 50+ stale local
# commits that came along with an old container snapshot. Best-effort: if
# the fetch or fast-forward fails, log a warning but never block the
# session.
#
# See PR #50 for the issue this prevents.

set -uo pipefail

# Cloud-only. Local Claude Code sessions don't have the stale-snapshot
# problem because the user controls their own working tree.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

if [ "$current_branch" = "main" ]; then
  # main is checked out — fast-forward in place. If local main has diverging
  # commits (someone committed locally without pushing), --ff-only refuses
  # and we leave it for the user to resolve consciously.
  if ! git pull --ff-only origin main 2>&1; then
    echo "[session-start] could not fast-forward local main; leaving as-is" >&2
  fi
else
  # main is not checked out — update the ref directly. The colon syntax
  # ("origin main:main") only fast-forwards; it refuses with non-zero
  # status if local main isn't a strict ancestor, which is what we want.
  if ! git fetch origin main:main 2>&1; then
    # At least refresh the remote-tracking ref so the user sees the
    # divergence the next time they touch main.
    git fetch origin main 2>/dev/null || true
    echo "[session-start] could not fast-forward local main; remote-tracking ref refreshed only" >&2
  fi
fi

# Install the caseyWebb/elm-claude-plugin into the per-container plugin
# directory so its `elm-packages` skill is available to Claude. The cloud
# container wipes ~/.claude/plugins/ between sessions, so we re-clone every
# session if missing. Pairs with `@caseywebb/elmq` in devDependencies, which
# provides the `elmq` CLI the skill drives. Best-effort: never block the
# session if the network call fails.
PLUGIN_DIR="$HOME/.claude/plugins/elm"
if [ ! -d "$PLUGIN_DIR/.git" ]; then
  mkdir -p "$HOME/.claude/plugins"
  if ! git clone --depth 1 https://github.com/caseyWebb/elm-claude-plugin.git "$PLUGIN_DIR" >&2 2>/dev/null; then
    echo "[session-start] could not install elm-claude-plugin" >&2
  fi
fi

exit 0
