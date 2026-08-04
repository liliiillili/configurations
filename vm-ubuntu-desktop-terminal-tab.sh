# 탭
gsettings set org.gnome.Ptyxis.Shortcuts move-next-tab '<Control>Tab'
gsettings set org.gnome.Ptyxis.Shortcuts move-previous-tab '<Control><Shift>Tab'

# 독바
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
gsettings set org.gnome.shell.extensions.dash-to-dock autohide true

# 최대화
gsettings set org.gnome.desktop.wm.keybindings maximize "['<Super>Up']"
gsettings set org.gnome.desktop.wm.keybindings unmaximize "['<Super>Down']"

# 배경
gsettings set org.gnome.desktop.background primary-color '#1b1b1b'

# 우커맨드 이슈
gsettings set org.gnome.desktop.input-sources xkb-options "['korean:ralt_hangul']"
sudo setkeycodes 72 100     # 100 = KEY_RIGHTALT

sudo tee /etc/udev/hwdb.d/70-hangul.hwdb << 'EOF'
evdev:atkbd:dmi:*
 KEYBOARD_KEY_72=rightalt
EOF
sudo systemd-hwdb update && sudo udevadm trigger
