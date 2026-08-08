#!/usr/bin/env bash
set -euo pipefail

# --- OS detection (먼저 수행) ---
OS="$(uname -s)"
if [ "$OS" != "Linux" ]; then
    echo "[!] This script targets Debian/Ubuntu Linux (detected: $OS)" >&2
    exit 1
fi

PACKAGES=(
    tree
    jq
    bat
    htop
    btop
    fd-find
    ripgrep
    fzf
    parallel
    whois
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
    sed -i "\#$MARKER_BEGIN#,\#$MARKER_END#d" "$BASHRC"
    echo "[*] Existing managed block removed"
fi

IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
    echo "[*] WSL detected"
fi

cat >> "$BASHRC" <<'EOF'
# >>> init.sh managed block >>>
# --- PATH ---
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# --- aliases ---
alias bat='batcat -p --no-paging'
alias fd='fdfind'
EOF

if $IS_WSL; then
    cat >> "$BASHRC" <<'EOF'

# --- WSL clipboard ---
pbcopy()  { iconv -f UTF-8 -t UTF-16LE | clip.exe; }
pbpaste() {
  powershell.exe -NoProfile -Command \
    '[Console]::OutputEncoding=[Text.Encoding]::UTF8; [Console]::Out.Write((Get-Clipboard -Raw))' \
  | sed 's/\r$//'
}
EOF
fi

printf '%s\n' "$MARKER_END" >> "$BASHRC"
echo "[*] ~/.bashrc managed block written"

# --- dotfiles setup ---
BASE="https://raw.githubusercontent.com/liliiillili/configurations/refs/heads/main"
VIM_URL="$BASE/.vimrc.wsl"
TMUX_URL="$BASE/.tmux.conf"
echo "[*] Linux detected -> .vimrc.wsl / .tmux.conf"

backup_if_exists() {
    local f="$1"
    if [ -f "$f" ]; then
        cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
        echo "[*] Existing $f backed up"
    fi
}

if [ -n "$VIM_URL" ] && [ -n "$TMUX_URL" ]; then
    backup_if_exists "$HOME/.vimrc"
    curl -LsSf -o "$HOME/.vimrc" "$VIM_URL"
    echo "[*] ~/.vimrc saved from $VIM_URL"

    backup_if_exists "$HOME/.tmux.conf"
    curl -LsSf -o "$HOME/.tmux.conf" "$TMUX_URL"
    echo "[*] ~/.tmux.conf saved from $TMUX_URL"
fi

# --- ip_whois script ---
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/ip_whois" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ip="${1:-}"
if [ -z "$ip" ]; then
    echo "usage: ${0##*/} <ip>" >&2
    exit 1
fi
whois -h whois.cymru.com " -v $ip" | tail -n 1
EOF
chmod +x "$HOME/.local/bin/ip_whois"
echo "[*] ip_whois installed to ~/.local/bin"

# --- uv & python tooling ---
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

if command -v uv >/dev/null 2>&1; then
    uv tool install basedpyright
    uv tool install ruff
else
    echo "[!] uv not found in PATH after install, skipping tool install" >&2
fi

echo "[*] Finish"
echo "[*] Run 'source ~/.bashrc' to apply changes"
