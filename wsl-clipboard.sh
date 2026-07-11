#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/pbcopy" <<'EOF'
#!/usr/bin/env bash
exec powershell.exe -NoProfile -Command '
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$in = [Console]::In.ReadToEnd()
Set-Clipboard -Value $in
'
EOF

cat > "$HOME/.local/bin/pbpaste" <<'EOF'
#!/usr/bin/env bash
exec powershell.exe -NoProfile -Command '
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Get-Clipboard
' | sed 's/\r$//'
EOF

chmod +x "$HOME/.local/bin/pbcopy" "$HOME/.local/bin/pbpaste"

case "$(basename "${SHELL:-bash}")" in
    zsh) RC="$HOME/.zshrc" ;;
    *)   RC="$HOME/.bashrc" ;;
esac

if ! grep -q 'HOME/.local/bin' "$RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
    echo "PATH added to $RC"
fi

echo "Done. Run: source $RC"
