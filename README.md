# Kiosk installer (`install.sh`)

## What the script does

`install.sh` automates kiosk environment setup on clean Debian 13 with SSH server and XFCE already installed:

It is intended for Python kiosk applications that use `pip` packages and a `tkinter` (`python3-tk`) GUI.

- installs packages: Openbox, LightDM, Python/Tk, xrdp, SSH, whiptail, rsync,
- sets `GRUB_TIMEOUT=0` and `GRUB_TIMEOUT_STYLE=hidden`,
- lets you choose the default GUI session for the user with UID 1000,
- optionally enables autologin for the `kiosk` user into Openbox,
- restricts RDP (xrdp) to the admin user only,
- blocks SSH login for the `kiosk` user,
- copies `app/` contents to `/opt/kiosk/`,
- configures LightDM and `.dmrc` for users,
- sets Openbox autostart and `Ctrl+X` shortcut to log out kiosk,
- optionally blocks TTY switching and SysRq (kiosk hardening).

## Requirements

- clean Debian 13 installation,
- installed SSH server and XFCE desktop environment.
- target application is Python-based and uses `pip` dependencies with `tkinter` (`python3-tk`).

## Expected project structure

The project directory should include at least:

- `install.sh`
- `app/` (all application files must be placed here)
- `app/main.py` (the main application file must be named `main.py`)

## How to run

```bash
chmod +x install.sh
./install.sh
```

The script is interactive (`whiptail`) and prompts for:

1. default graphical session for admin user,
2. enabling/disabling `kiosk` autologin,
3. (optional) TTY/SysRq lock,
4. system reboot at the end.

## After installation

- To modify the installed application code, edit files in `/opt/kiosk/`.

## Openbox customization

- You can change the startup command/file in `/home/kiosk/.config/openbox/autostart`.
- You can change the logout keyboard shortcut in `/home/kiosk/.config/openbox/rc.xml` (the `<keybind>` entry).

## Building an app compatible with logout

To ensure your app works correctly with kiosk logout:

- run the app in a graphical session (Openbox/LightDM), not from TTY/SSH,
- keep `XDG_SESSION_ID` available in the process environment,
- implement logout by calling `loginctl terminate-session "$XDG_SESSION_ID"`,
- optionally provide a UI button labeled **Logout** that triggers this action.

Example Python function:

```python
import os
import subprocess

def logout():
	sid = os.environ.get("XDG_SESSION_ID")
	if not sid:
		raise RuntimeError("Missing XDG_SESSION_ID")
	subprocess.run(["loginctl", "terminate-session", sid], check=True)
```

## What gets modified

The script may modify or create, among others:

- `/etc/default/grub`
- `/etc/lightdm/lightdm.conf`
- `/etc/lightdm/lightdm-gtk-greeter.conf.d/50-kiosk.conf`
- `/etc/xrdp/sesman.ini`
- `/etc/ssh/sshd_config`
- `/etc/systemd/logind.conf` (if TTY lock is enabled)
- `/etc/sysctl.d/99-disable-sysrq.conf` (if TTY lock is enabled)
- `/etc/X11/xorg.conf.d/10-kiosk-novt.conf` (if TTY lock is enabled)
- `/usr/local/bin/kiosk-logout`
- `/opt/kiosk/`
- `~/.dmrc` for admin and kiosk users
- `~/.config/openbox/autostart` and `~/.config/openbox/rc.xml` for `kiosk`

Important configuration files are backed up by the script (`*.bak.<timestamp>`).

## Security and operational notes

- When autologin is enabled, the `kiosk` user password is locked (`passwd -l`).
- The `kiosk` user is added to SSH deny list (`DenyUsers`).
- RDP (xrdp) access is restricted to the admin user.
- TTY lock is recommended for kiosk mode, but it makes local console maintenance harder.

## Re-run / re-install

You can run the script again. Some operations are idempotent (e.g. creating user only if missing), but it still modifies system configs and services — run it intentionally.

## Quick rollback (manual)

1. Restore backup files `*.bak.<timestamp>` from `/etc`.
2. Check/unmask `getty@tty*` services if TTY lock was enabled.
3. Remove kiosk-related entries from LightDM/xrdp/SSH if no longer needed.
4. Restart services and reboot the system.
