#!/bin/bash
set -euo pipefail

KIOSK_USER="kiosk"

ADMIN_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
[ -n "${ADMIN_USER:-}" ] || { echo "ERROR: No user with UID=1000 found"; exit 1; }

KIOSK_DIR="/opt/kiosk"
KIOSK_APP="$KIOSK_DIR/main.py"

SOURCE_APP_DIR="app"

die() { echo "ERROR: $*" >&2; exit 1; }

read_desktop_kv() {
  awk -F= -v k="$2" '
    $0 ~ "^[[:space:]]*"k"=" {sub(/^[^=]*=/,""); print; exit}
  ' "$1" 2>/dev/null || true
}

build_sessions_menu() {
  MENU_ITEMS=()
  local f key name comment label
  for f in /usr/share/xsessions/*.desktop; do
    [ -e "$f" ] || continue
    key="$(basename "$f" .desktop)"
    name="$(read_desktop_kv "$f" "Name")"
    comment="$(read_desktop_kv "$f" "Comment")"
    [ -n "$name" ] || name="$key"
    label="$name"
    [ -n "$comment" ] && label="$label — $comment"
    MENU_ITEMS+=("$key" "$label")
  done
}

choose_admin_session_whiptail() {
  build_sessions_menu
  [ "${#MENU_ITEMS[@]}" -gt 0 ] || die "No sessions found in /usr/share/xsessions/*.desktop"

  ADMIN_SESSION="$(
    whiptail --title "Session selection" \
      --menu "Choose the default graphical session for user '$ADMIN_USER':" \
      20 90 10 \
      "${MENU_ITEMS[@]}" \
      3>&1 1>&2 2>&3
  )" || die "Session selection cancelled."

  echo "Selected ADMIN_SESSION=$ADMIN_SESSION"
}

confirm_autologin_whiptail() {
  if whiptail --title "Kiosk autologin" \
    --yesno "Enable autologin for user '$KIOSK_USER' to Openbox (kiosk mode)?" 12 80; then
    ENABLE_AUTOLOGIN="yes"
  else
    ENABLE_AUTOLOGIN="no"
  fi
  echo "ENABLE_AUTOLOGIN=$ENABLE_AUTOLOGIN"
}

confirm_ctrlx_bind_whiptail() {
  if whiptail --title "Kiosk: Ctrl+X" \
    --yesno "Enable Ctrl+X global shortcut to log out the kiosk session?\n\nIf you choose NO, installer will REMOVE existing Ctrl+X bind from Openbox rc.xml." 14 80; then
    ENABLE_CTRLX_BIND="yes"
  else
    ENABLE_CTRLX_BIND="no"
  fi
  echo "ENABLE_CTRLX_BIND=$ENABLE_CTRLX_BIND"
}

require_session_exists() {
  local key="$1"
  [ -f "/usr/share/xsessions/${key}.desktop" ] || die "Session missing: /usr/share/xsessions/${key}.desktop"
}

confirm_lock_tty_whiptail() {
  if whiptail --title "Kiosk: TTY lock" \
    --yesno "Disable switching to TTY (Ctrl+Alt+F1..F12) and disable SysRq?\n\nRecommended for kiosk mode." 14 80; then
    LOCK_TTY="yes"
  else
    LOCK_TTY="no"
  fi
  echo "LOCK_TTY=$LOCK_TTY"
}

apply_lock_tty() {
  [ "${LOCK_TTY:-no}" = "yes" ] || return 0

  echo "[HARDEN] Locking TTY: logind + disable getty@tty1..tty6 + disable SysRq + Xorg DontVTSwitch..."

  if [ -f /etc/systemd/logind.conf ]; then
    sudo cp -a /etc/systemd/logind.conf "/etc/systemd/logind.conf.bak.$(date +%F-%H%M%S)"
  fi

  if ! grep -qE '^\s*\[Login\]\s*$' /etc/systemd/logind.conf 2>/dev/null; then
    echo -e "\n[Login]" | sudo tee -a /etc/systemd/logind.conf >/dev/null
  fi

  if grep -qE '^\s*NAutoVTs\s*=' /etc/systemd/logind.conf; then
    sudo sed -i 's/^\s*NAutoVTs\s*=.*/NAutoVTs=0/' /etc/systemd/logind.conf
  else
    sudo sed -i '/^\s*\[Login\]\s*$/a NAutoVTs=0' /etc/systemd/logind.conf
  fi

  if grep -qE '^\s*ReserveVT\s*=' /etc/systemd/logind.conf; then
    sudo sed -i 's/^\s*ReserveVT\s*=.*/ReserveVT=0/' /etc/systemd/logind.conf
  else
    sudo sed -i '/^\s*\[Login\]\s*$/a ReserveVT=0' /etc/systemd/logind.conf
  fi

  sudo systemctl restart systemd-logind || true

  for n in 1 2 3 4 5 6; do
    sudo systemctl disable --now "getty@tty${n}.service" 2>/dev/null || true
    sudo systemctl mask "getty@tty${n}.service" 2>/dev/null || true
  done

  echo 'kernel.sysrq = 0' | sudo tee /etc/sysctl.d/99-disable-sysrq.conf >/dev/null
  sudo sysctl --system >/dev/null || true

  sudo mkdir -p /etc/X11/xorg.conf.d
  sudo tee /etc/X11/xorg.conf.d/10-kiosk-novt.conf >/dev/null <<'EOF'
Section "ServerFlags"
  Option "DontVTSwitch" "true"
  Option "DontZap" "true"
EndSection
EOF

  sudo systemctl mask ctrl-alt-del.target 2>/dev/null || true
}

set_grub_hidden_instant() {
  echo "[BOOT] Setting GRUB_TIMEOUT=0 and GRUB_TIMEOUT_STYLE=hidden..."

  if [ ! -f /etc/default/grub ]; then
    echo "Missing /etc/default/grub — skipping."
    return 0
  fi

  sudo cp -a /etc/default/grub "/etc/default/grub.bak.$(date +%F-%H%M%S)"

  if grep -qE '^\s*GRUB_TIMEOUT=' /etc/default/grub; then
    sudo sed -i 's/^\s*GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
  else
    echo 'GRUB_TIMEOUT=0' | sudo tee -a /etc/default/grub >/dev/null
  fi

  if grep -qE '^\s*GRUB_TIMEOUT_STYLE=' /etc/default/grub; then
    sudo sed -i 's/^\s*GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
  else
    echo 'GRUB_TIMEOUT_STYLE=hidden' | sudo tee -a /etc/default/grub >/dev/null
  fi

  sudo update-grub
}

# ------------------ MAIN ------------------

echo "[0] Detected ADMIN_USER (UID 1000): $ADMIN_USER"

echo "[1/11] Installing: Openbox, LightDM, Python/Tk, xrdp, SSH, whiptail..."
sudo apt update
sudo apt install -y \
  openbox \
  lightdm lightdm-gtk-greeter \
  python3 python3-tk \
  xrdp xorgxrdp \
  openssh-server \
  whiptail \
  rsync

set_grub_hidden_instant

choose_admin_session_whiptail
confirm_autologin_whiptail
confirm_ctrlx_bind_whiptail

if [ "${ENABLE_AUTOLOGIN:-no}" = "yes" ]; then
  confirm_lock_tty_whiptail
else
  LOCK_TTY="no"
fi

require_session_exists "$ADMIN_SESSION"
require_session_exists "openbox"

echo "[2/11] Enabling services: LightDM, xrdp..."
sudo systemctl enable --now lightdm
sudo systemctl enable --now xrdp

echo "[3/11] Granting certificate permissions for xrdp (ssl-cert) and restarting..."
sudo adduser xrdp ssl-cert || true
sudo systemctl restart xrdp

echo "[4/11] Restricting RDP (xrdp): only user '$ADMIN_USER'..."
SESMAN="/etc/xrdp/sesman.ini"
if [ -f "$SESMAN" ]; then
  sudo cp -a "$SESMAN" "$SESMAN.bak.$(date +%F-%H%M%S)"

  if grep -qE '^\s*TerminalServerUsers\s*=' "$SESMAN"; then
    sudo sed -i "s|^\s*TerminalServerUsers\s*=.*|TerminalServerUsers=$ADMIN_USER|g" "$SESMAN"
  else
    sudo sed -i "/^\[Security\]/a TerminalServerUsers=$ADMIN_USER" "$SESMAN"
  fi

  if grep -qE '^\s*TerminalServerDeniedUsers\s*=' "$SESMAN"; then
    if ! grep -qE "^\s*TerminalServerDeniedUsers\s*=.*\b$KIOSK_USER\b" "$SESMAN"; then
      sudo sed -i "s|^\s*TerminalServerDeniedUsers\s*=\s*|TerminalServerDeniedUsers=$KIOSK_USER,|g" "$SESMAN"
    fi
  else
    sudo sed -i "/^\[Security\]/a TerminalServerDeniedUsers=$KIOSK_USER" "$SESMAN"
  fi
fi
sudo systemctl restart xrdp

echo "[5/11] Kiosk user (if it does not exist)..."
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  sudo adduser --disabled-password --gecos "" "$KIOSK_USER"
fi

if [ "$ENABLE_AUTOLOGIN" = "yes" ]; then
  echo "[6/11] Locking kiosk user password (autologin only)..."
  sudo passwd -l "$KIOSK_USER" || true
else
  echo "[6/11] Autologin disabled: NOT locking kiosk password (set it manually if you want to log in as kiosk)."
fi

echo "[7/11] SSH: block kiosk login..."
SSHD="/etc/ssh/sshd_config"
if [ -f "$SSHD" ]; then
  sudo cp -a "$SSHD" "$SSHD.bak.$(date +%F-%H%M%S)"

  if ! grep -qE "^\s*DenyUsers\b" "$SSHD"; then
    echo "DenyUsers $KIOSK_USER" | sudo tee -a "$SSHD" >/dev/null
  else
    if ! grep -qE "^\s*DenyUsers\b.*\b$KIOSK_USER\b" "$SSHD"; then
      sudo sed -i "s/^\(\s*DenyUsers.*\)$/\1 $KIOSK_USER/" "$SSHD"
    fi
  fi
fi
sudo systemctl restart ssh || sudo systemctl restart sshd

echo "[8/11] Copying kiosk app (directory '$SOURCE_APP_DIR/') to $KIOSK_DIR/ ..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -d "$SCRIPT_DIR/$SOURCE_APP_DIR" ] || die "Directory not found: $SCRIPT_DIR/$SOURCE_APP_DIR"

sudo mkdir -p "$KIOSK_DIR"
sudo rsync -a --delete "$SCRIPT_DIR/$SOURCE_APP_DIR"/ "$KIOSK_DIR"/

[ -f "$KIOSK_APP" ] || die "Missing $KIOSK_APP. Make sure app/main.py exists"

sudo chown -R "$ADMIN_USER:$ADMIN_USER" "$KIOSK_DIR"
sudo find "$KIOSK_DIR" -type d -exec chmod 0755 {} \;
sudo find "$KIOSK_DIR" -type f -exec chmod 0644 {} \;
sudo chmod 0755 "$KIOSK_APP"

echo "[9/11] LightDM: session settings + (optional) kiosk autologin..."
sudo mkdir -p /etc/lightdm
if [ -f /etc/lightdm/lightdm.conf ]; then
  sudo cp -a /etc/lightdm/lightdm.conf "/etc/lightdm/lightdm.conf.bak.$(date +%F-%H%M%S)"
fi

if [ "$ENABLE_AUTOLOGIN" = "yes" ]; then
  sudo tee /etc/lightdm/lightdm.conf >/dev/null <<EOF
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=$ADMIN_SESSION

autologin-user=$KIOSK_USER
autologin-user-timeout=0
autologin-session=openbox
EOF
else
  sudo tee /etc/lightdm/lightdm.conf >/dev/null <<EOF
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=$ADMIN_SESSION
EOF
fi

sudo mkdir -p /etc/lightdm/lightdm-gtk-greeter.conf.d
sudo tee /etc/lightdm/lightdm-gtk-greeter.conf.d/50-kiosk.conf >/dev/null <<EOF
[greeter]
greeter-hide-users=true
hidden-users=$KIOSK_USER
EOF

echo "[10/11] Per-user sessions (.dmrc)..."
sudo tee "/home/$ADMIN_USER/.dmrc" >/dev/null <<EOF
[Desktop]
Session=$ADMIN_SESSION
EOF
sudo chown "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.dmrc"
sudo chmod 0644 "/home/$ADMIN_USER/.dmrc"

sudo tee "/home/$KIOSK_USER/.dmrc" >/dev/null <<'EOF'
[Desktop]
Session=openbox
EOF
sudo chown "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/.dmrc"
sudo chmod 0644 "/home/$KIOSK_USER/.dmrc"

echo "[11/11] Openbox (kiosk): autostart + keyblocks + optional Ctrl+X..."
sudo -u "$KIOSK_USER" mkdir -p "/home/$KIOSK_USER/.config/openbox"

sudo tee /usr/local/bin/kiosk-logout >/dev/null <<'EOF'
#!/bin/sh
set -eu
if [ -n "${XDG_SESSION_ID:-}" ]; then
  exec loginctl terminate-session "$XDG_SESSION_ID"
fi
exec loginctl kill-user "$(id -u)"
EOF
sudo chmod 0755 /usr/local/bin/kiosk-logout

sudo tee "/home/$KIOSK_USER/.config/openbox/autostart" >/dev/null <<EOF
python3 $KIOSK_APP &
EOF
sudo chown "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/.config/openbox/autostart"
sudo chmod 0755 "/home/$KIOSK_USER/.config/openbox/autostart"

if [ ! -f "/home/$KIOSK_USER/.config/openbox/rc.xml" ]; then
  sudo cp /etc/xdg/openbox/rc.xml "/home/$KIOSK_USER/.config/openbox/rc.xml"
  sudo chown "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/.config/openbox/rc.xml"
fi

# Remove existing binds that may override our kiosk ones (best-effort).
sudo perl -0777 -i -pe '
  s#\s*<keybind[^>]*key="A-Tab"[^>]*>.*?</keybind>\s*##sg;
  s#\s*<keybind[^>]*key="A-S-Tab"[^>]*>.*?</keybind>\s*##sg;
  s#\s*<keybind[^>]*key="A-F4"[^>]*>.*?</keybind>\s*##sg;
  s#\s*<keybind[^>]*key="A-space"[^>]*>.*?</keybind>\s*##sg;
' "/home/$KIOSK_USER/.config/openbox/rc.xml" || true

# --- KIOSK: Openbox global key blocks (idempotent) ---
if ! grep -q "KIOSK_KEYBLOCKS_BEGIN" "/home/$KIOSK_USER/.config/openbox/rc.xml"; then
  sudo perl -0777 -i -pe 's#</keyboard>#  <!-- KIOSK_KEYBLOCKS_BEGIN -->\n  <!-- Block common WM shortcuts (capture keys) -->\n  <keybind key="A-Tab">\n    <action name="Focus"/>\n  </keybind>\n  <keybind key="A-S-Tab">\n    <action name="Focus"/>\n  </keybind>\n  <keybind key="A-F4">\n    <action name="Focus"/>\n  </keybind>\n  <keybind key="A-space">\n    <action name="Focus"/>\n  </keybind>\n  <!-- KIOSK_KEYBLOCKS_END -->\n</keyboard>#s' \
    "/home/$KIOSK_USER/.config/openbox/rc.xml"
fi
# --- /KIOSK: Openbox global key blocks ---

# Ctrl+X bind: add/update OR remove
if [ "${ENABLE_CTRLX_BIND:-yes}" = "yes" ]; then
  if ! grep -q 'key="C-X"' "/home/$KIOSK_USER/.config/openbox/rc.xml"; then
    sudo perl -0777 -i -pe 's#</keyboard>#  <keybind key="C-X">\n    <action name="Execute">\n      <command>/usr/local/bin/kiosk-logout</command>\n    </action>\n  </keybind>\n</keyboard>#s' \
      "/home/$KIOSK_USER/.config/openbox/rc.xml"
  else
    sudo perl -0777 -i -pe 's#(<keybind key="C-X">.*?<command>)(.*?)(</command>)#${1}/usr/local/bin/kiosk-logout${3}#s' \
      "/home/$KIOSK_USER/.config/openbox/rc.xml" || true
  fi
else
  sudo perl -0777 -i -pe 's#\s*<keybind key="C-X">.*?</keybind>\s*##sg' \
    "/home/$KIOSK_USER/.config/openbox/rc.xml" || true
  echo "[INFO] Ctrl+X bind removed from Openbox rc.xml."
fi

apply_lock_tty

echo
echo "Done."
echo "- ADMIN_USER (UID 1000): '$ADMIN_USER' | session: '$ADMIN_SESSION'."
echo "- kiosk: Openbox session; autologin: $ENABLE_AUTOLOGIN."
echo "- RDP: only '$ADMIN_USER'."
echo "- SSH: kiosk blocked."
echo "- GRUB: timeout=0, hidden."
if [ "${ENABLE_CTRLX_BIND:-yes}" = "yes" ]; then
  echo "- Ctrl+X: logs out kiosk session."
else
  echo "- Ctrl+X: disabled (removed from rc.xml)."
fi
echo "- TTY switch: blocked (if selected)."

if whiptail --title "Restart" --yesno "Changes have been applied. Restart the computer now?" 10 70; then
  sudo reboot
else
  echo "OK. Restart later with: sudo reboot"
fi
