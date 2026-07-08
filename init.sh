#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(
    tree
    jq
    bat
    htop
    btop
    fd-find
    ripgrep
    fzf
)

echo "[*] apt update & upgrade"
sudo apt-get update -y
sudo apt-get upgrade -y

echo "[*] Package install: ${PACKAGES[*]}"
sudo apt-get install -y "${PACKAGES[@]}"

BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> init.sh managed block >>>"
MARKER_END="# <<< init.sh managed block <<<"

if grep -qF "$MARKER_BEGIN" "$BASHRC" 2>/dev/null; then
    sed -i "/$MARKER_BEGIN/,/$MARKER_END/d" "$BASHRC"
fi

cat >> "$BASHRC" <<'EOF'
# >>> init.sh managed block >>>
# --- aliases ---
alias bat='batcat -p --no-paging'
alias fd='fdfind'
EOF

curl -LsSf https://astral.sh/uv/install.sh | sh
source "$BASHRC"

uv tool install basedpyright
uv tool install ruff

echo "[*] Finish"
