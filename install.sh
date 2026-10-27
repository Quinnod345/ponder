#!/bin/sh
# Install ponder: one canonical repo, symlinked into every agent harness that can use it.
#
# One-line install from anywhere:
#   curl -fsSL https://raw.githubusercontent.com/Quinnod345/ponder/main/install.sh | sh
#
# Or from a local checkout:
#   git clone https://github.com/Quinnod345/ponder.git ~/code/ponder
#   ~/code/ponder/install.sh
#
# Symlinks (never copies) so that editing or pulling the repo updates Claude Code, Codex,
# OpenClaw, and your shell at once. Re-running is safe: existing ponder symlinks are replaced,
# real directories are never clobbered.

set -eu

REPO_URL="${PONDER_REPO:-https://github.com/Quinnod345/ponder.git}"
CLAUDE_SKILLS="$HOME/.claude/skills"
AGENTS_SKILLS="$HOME/.agents/skills"
CODEX_SKILLS="$HOME/.codex/skills"
BIN_DIR="$HOME/.local/bin"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
die()  { printf '  \033[31mfail\033[0m  %s\n' "$*" >&2; exit 1; }

link() {
  target="$1"; dest="$2"; label="$3"
  if [ -L "$dest" ]; then
    rm "$dest"
  elif [ -e "$dest" ]; then
    warn "$label: $dest exists and is not a symlink — leaving it alone."
    warn "      move it aside and re-run if you want ponder linked there."
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$target" "$dest"
  ok "$label -> $dest"
}

# Resolve checkout directory (local checkout or clone via curl | sh)
SCRIPT_DIR=""
if [ -n "${0:-}" ] && [ -f "$0" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/lib/cli.js" ]; then
  REPO="$SCRIPT_DIR"
else
  REPO="${PONDER_CHECKOUT:-$HOME/code/ponder}"
  command -v git >/dev/null 2>&1 || die "git is not installed. Install git and re-run."
  if [ -d "$REPO/.git" ]; then
    say "Updating existing checkout at $REPO"
    git -C "$REPO" pull --ff-only || warn "git pull --ff-only skipped (working tree has local changes)"
  elif [ -e "$REPO" ] && [ -f "$REPO/lib/cli.js" ]; then
    say "Using existing ponder directory at $REPO"
  else
    say "Cloning $REPO_URL -> $REPO"
    mkdir -p "$(dirname "$REPO")"
    git clone "$REPO_URL" "$REPO"
  fi
fi

say ""
say "Installing ponder from $REPO"
say ""

[ -f "$REPO/lib/cli.js" ] || die "no lib/cli.js — is $REPO a ponder checkout?"
chmod +x "$REPO/bin/ponder" 2>/dev/null || true
chmod +x "$REPO/test/conformance.sh" 2>/dev/null || true

say "Skills"
link "$REPO/skill/ponder" "$CLAUDE_SKILLS/ponder" "claude code (~/.claude/skills)"
link "$REPO/skill/ponder" "$AGENTS_SKILLS/ponder" "agents (~/.agents/skills)"
if [ -d "$HOME/.codex" ]; then
  link "$REPO/skill/ponder" "$CODEX_SKILLS/ponder" "codex (~/.codex/skills)"
fi

say ""
say "Binary"
link "$REPO/bin/ponder" "$BIN_DIR/ponder" "ponder"
case ":$PATH:" in
  *":$BIN_DIR:"*) ok "$BIN_DIR is on PATH" ;;
  *) warn "$BIN_DIR is NOT on PATH — add it to your shell profile:"
     warn "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

say ""
say "Checks"
if "$REPO/bin/ponder" --help >/dev/null 2>&1; then
  ok "bin/ponder runs"
else
  die "bin/ponder failed to run — check node (>=18) is installed (node -v)"
fi
"$REPO/bin/ponder" doctor || true

say ""
say "Done. In Claude Code, Codex, or OpenClaw:  /ponder"
say "From a shell:                              ponder start \"the UI\" --lens ui"
say ""
