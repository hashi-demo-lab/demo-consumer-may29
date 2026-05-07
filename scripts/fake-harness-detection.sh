#!/usr/bin/env bash
# fake-harness-detection.sh — Create minimal config files so the kits CLI
# detects a given harness during CI (satisfies pathExists() checks).
#
# Usage: bash scripts/fake-harness-detection.sh <harness>
#   harness: claude-code | codex | github-copilot

set -euo pipefail

HARNESS="${1:?Usage: fake-harness-detection.sh <harness>}"

case "$HARNESS" in
  claude-code)
    mkdir -p "$HOME/.claude"
    echo '{}' > "$HOME/.claude/settings.json"
    echo "Created ~/.claude/settings.json"
    ;;
  codex)
    mkdir -p "$HOME/.codex"
    touch "$HOME/.codex/config.toml"
    echo "Created ~/.codex/config.toml"
    ;;
  github-copilot)
    mkdir -p "$HOME/.copilot"
    echo '{}' > "$HOME/.copilot/config.json"
    echo "Created ~/.copilot/config.json"
    ;;
  *)
    echo "Error: unknown harness '$HARNESS'" >&2
    echo "Valid harnesses: claude-code, codex, github-copilot" >&2
    exit 1
    ;;
esac
