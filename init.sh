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
    sed -i "/$MARKER_BEGIN/,/$MARKER_END/d" "$BASHRC"
fi

IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
    echo "[*] WSL detected"
fi

cat >> "$BASHRC" <<'EOF'
# >>> init.sh managed block >>>
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

echo "# <<< init.sh managed block <<<" >> "$BASHRC"

# --- vimrc setup (OS detection) ---
VIMRC_BASE="https://raw.githubusercontent.com/liliiillili/configurations/refs/heads/main"

case "$(uname -s)" in
    Darwin)
        VIMRC_URL="$VIMRC_BASE/.vimrc.mac"
        echo "[*] macOS detected -> .vimrc.mac"
        ;;
    Linux)
        VIMRC_URL="$VIMRC_BASE/.vimrc.wsl"
        echo "[*] Linux detected -> .vimrc.wsl"
        ;;
    *)
        echo "[!] Unknown OS: $(uname -s), skip vimrc setup" >&2
        VIMRC_URL=""
        ;;
esac

if [ -n "$VIMRC_URL" ]; then
    if [ -f "$HOME/.vimrc" ]; then
        cp "$HOME/.vimrc" "$HOME/.vimrc.bak.$(date +%Y%m%d%H%M%S)"
        echo "[*] Existing ~/.vimrc backed up"
    fi
    curl -LsSf -o "$HOME/.vimrc" "$VIMRC_URL"
    echo "[*] ~/.vimrc saved from $VIMRC_URL"
fi

# --- ip_whois script ---
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/ip_whois" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ip="${1:-}"
[[ -z "$ip" ]] && { echo "usage: $0 <ip>" >&2; exit 1; }
whois -h whois.cymru.com " -v $ip" | tail -n 1
EOF
chmod +x "$HOME/.local/bin/ip_whois"
echo "[*] ip_whois installed to ~/.local/bin"

curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

uv tool install basedpyright
uv tool install ruff

echo "[*] Finish"
