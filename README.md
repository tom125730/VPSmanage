# VPSmanage

VPSmanage is an interactive VPS management script collection.

It is designed for fresh or existing Linux VPS servers where each action should be optional and confirmed before it changes the system.

VPSmanage supports Chinese and English interaction. It auto-detects the system locale, and you can also switch language in the main menu.

VPSmanage 支持中文和英文交互。脚本会自动识别系统语言，也可以在主菜单中手动切换语言。

## Features

- Detect Linux distribution, version, architecture, package manager, and service manager.
- Set the SSH port safely with config backup and `sshd -t` validation.
- Install or run Speedtest tools.
- Install Docker using Docker's official auto-detect installer.
- Request SSL certificates with `acme.sh`.
- Apply optional security measures such as package upgrades, fail2ban, firewall baseline, SSH password login hardening, root SSH login hardening, and automatic security updates.
- Run basic IP information checks or optional third-party IP quality scripts.

## Quick Start

Run from a VPS shell:

```bash
curl -fsSL https://raw.githubusercontent.com/tom125730/VPSmanage/main/vpsmanage.sh -o vpsmanage.sh
sudo bash vpsmanage.sh
```

Or run directly:

```bash
curl -fsSL https://raw.githubusercontent.com/tom125730/VPSmanage/main/vpsmanage.sh | sudo bash
```

Force Chinese:

```bash
curl -fsSL https://raw.githubusercontent.com/tom125730/VPSmanage/main/vpsmanage.sh | sudo VPSMANAGE_LANG=zh bash
```

Force English:

```bash
curl -fsSL https://raw.githubusercontent.com/tom125730/VPSmanage/main/vpsmanage.sh | sudo VPSMANAGE_LANG=en bash
```

Or run a single command:

```bash
sudo bash vpsmanage.sh detect
sudo bash vpsmanage.sh ssh-port
sudo bash vpsmanage.sh speedtest
sudo bash vpsmanage.sh docker
sudo bash vpsmanage.sh ssl
sudo bash vpsmanage.sh security
sudo bash vpsmanage.sh ip-quality
sudo bash vpsmanage.sh language
```

Chinese examples:

```bash
sudo VPSMANAGE_LANG=zh bash vpsmanage.sh
sudo VPSMANAGE_LANG=zh bash vpsmanage.sh security
```

## Supported Systems

The script currently targets common Linux VPS distributions:

- Debian and Ubuntu with `apt`
- RHEL-like systems, AlmaLinux, Rocky Linux, CentOS, and Fedora with `dnf` or `yum`
- Alpine Linux with `apk` for basic package operations

Some features depend on system services such as `systemd`, `ufw`, `firewalld`, `sshd`, Docker, or external ACME/network APIs.

## Safety Notes

- Keep your current SSH session open after changing the SSH port.
- Make sure the provider firewall/security group allows the new SSH port.
- Confirm SSH key login before disabling SSH password authentication.
- Confirm a sudo-capable non-root account before disabling root SSH login.
- Third-party test scripts are downloaded only after interactive confirmation.

## Project Structure

```text
vpsmanage.sh     Main interactive VPS management script
docs/            Project notes and design documents
```
