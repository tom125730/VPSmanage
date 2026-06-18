#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.1.0"
LOG_FILE="${VPSMANAGE_LOG:-/var/log/vpsmanage.log}"

OS_ID="unknown"
OS_LIKE=""
OS_VERSION_ID=""
OS_VERSION_CODENAME=""
OS_PRETTY="Unknown Linux"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
PKG_MANAGER="unknown"
SERVICE_MANAGER="unknown"

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  C_RESET="$(tput sgr0)"
  C_RED="$(tput setaf 1)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"
else
  C_RESET=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
fi

log_line() {
  local level="$1"
  shift
  local line
  line="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$level] $*"
  if [[ "$(id -u)" -eq 0 ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
  fi
}

info() {
  printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"
  log_line INFO "$*"
}

success() {
  printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"
  log_line OK "$*"
}

warn() {
  printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
  log_line WARN "$*"
}

fail() {
  printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
  log_line FAIL "$*"
}

pause() {
  local ignored
  printf '\nPress Enter to continue...'
  read_input ignored || true
}

read_input() {
  local __var="$1"

  if [[ -r /dev/tty ]]; then
    IFS= read -r "$__var" </dev/tty
  else
    IFS= read -r "$__var"
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    fail "This action requires root privileges. Re-run with: sudo bash $0"
    exit 1
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local hint
  local answer

  if [[ "$default" =~ ^[Yy]$ ]]; then
    hint="Y/n"
  else
    hint="y/N"
  fi

  while true; do
    printf '%s [%s]: ' "$prompt" "$hint"
    read_input answer || answer=""
    answer="${answer:-$default}"
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) warn "Please answer yes or no." ;;
    esac
  done
}

prompt_value() {
  local prompt="$1"
  local default="${2:-}"
  local answer

  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi
  read_input answer || answer=""
  printf '%s' "${answer:-$default}"
}

detect_system() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_VERSION_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    OS_PRETTY="${PRETTY_NAME:-$OS_ID $OS_VERSION_ID}"
  fi

  if command_exists apt-get; then
    PKG_MANAGER="apt"
  elif command_exists dnf; then
    PKG_MANAGER="dnf"
  elif command_exists yum; then
    PKG_MANAGER="yum"
  elif command_exists apk; then
    PKG_MANAGER="apk"
  else
    PKG_MANAGER="unknown"
  fi

  if command_exists systemctl; then
    SERVICE_MANAGER="systemd"
  elif command_exists rc-service; then
    SERVICE_MANAGER="openrc"
  elif command_exists service; then
    SERVICE_MANAGER="sysv"
  else
    SERVICE_MANAGER="unknown"
  fi
}

show_system() {
  detect_system
  cat <<EOF

Detected system
---------------
OS:              $OS_PRETTY
ID:              $OS_ID
Like:            ${OS_LIKE:-none}
Version:         ${OS_VERSION_ID:-unknown}
Codename:        ${OS_VERSION_CODENAME:-unknown}
Architecture:    $ARCH
Package manager: $PKG_MANAGER
Service manager: $SERVICE_MANAGER

EOF
}

pkg_update() {
  detect_system
  case "$PKG_MANAGER" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get update
      ;;
    dnf)
      dnf makecache -y
      ;;
    yum)
      yum makecache -y
      ;;
    apk)
      apk update
      ;;
    *)
      return 1
      ;;
  esac
}

pkg_upgrade() {
  detect_system
  case "$PKG_MANAGER" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
      ;;
    dnf)
      dnf upgrade -y
      ;;
    yum)
      yum update -y
      ;;
    apk)
      apk upgrade
      ;;
    *)
      return 1
      ;;
  esac
}

pkg_install() {
  detect_system
  case "$PKG_MANAGER" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
      ;;
    dnf)
      dnf install -y "$@"
      ;;
    yum)
      yum install -y "$@"
      ;;
    apk)
      apk add --no-cache "$@"
      ;;
    *)
      fail "Unsupported package manager. Please install manually: $*"
      return 1
      ;;
  esac
}

backup_file() {
  local file="$1"
  local backup

  [[ -f "$file" ]] || return 0
  backup="${file}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a "$file" "$backup"
  success "Backup created: $backup"
}

service_action() {
  local action="$1"
  local name="$2"

  detect_system
  case "$SERVICE_MANAGER" in
    systemd)
      systemctl "$action" "$name" 2>/dev/null || systemctl "$action" "${name}.service"
      ;;
    openrc)
      case "$action" in
        restart) rc-service "$name" restart ;;
        start) rc-service "$name" start ;;
        enable) rc-update add "$name" default ;;
        *) return 1 ;;
      esac
      ;;
    sysv)
      service "$name" "$action"
      ;;
    *)
      warn "Unknown service manager. Please run service action manually: $action $name"
      return 1
      ;;
  esac
}

enable_and_start_service() {
  local name="$1"
  detect_system
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl enable --now "$name" 2>/dev/null || systemctl enable --now "${name}.service"
  elif [[ "$SERVICE_MANAGER" == "openrc" ]]; then
    rc-update add "$name" default || true
    rc-service "$name" start
  else
    service "$name" start || true
  fi
}

find_sshd_bin() {
  if [[ -x /usr/sbin/sshd ]]; then
    printf '/usr/sbin/sshd'
  elif command_exists sshd; then
    command -v sshd
  else
    printf ''
  fi
}

find_ssh_service() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    if systemctl list-unit-files sshd.service >/dev/null 2>&1; then
      printf 'sshd'
      return
    fi
    if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
      printf 'ssh'
      return
    fi
  fi

  if [[ -e /etc/init.d/sshd ]]; then
    printf 'sshd'
  else
    printf 'ssh'
  fi
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

current_ssh_port() {
  local sshd_bin
  sshd_bin="$(find_sshd_bin)"
  if [[ -n "$sshd_bin" ]]; then
    "$sshd_bin" -T 2>/dev/null | awk '/^port / { print $2; exit }' || true
  fi
}

set_sshd_option() {
  local key="$1"
  local value="$2"
  local cfg="/etc/ssh/sshd_config"
  local tmp

  [[ -f "$cfg" ]] || {
    fail "SSH config not found: $cfg"
    return 1
  }

  backup_file "$cfg"
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    {
      line = $0
      stripped = line
      sub(/^[[:space:]]*/, "", stripped)
      if (stripped ~ "^#?[[:space:]]*" key "[[:space:]]+") {
        if (!done) {
          print key " " value
          done = 1
        }
        next
      }
      print line
    }
    END {
      if (!done) {
        print key " " value
      }
    }
  ' "$cfg" >"$tmp"
  install -m 600 "$tmp" "$cfg"
  rm -f "$tmp"
}

test_sshd_config() {
  local sshd_bin
  sshd_bin="$(find_sshd_bin)"
  if [[ -z "$sshd_bin" ]]; then
    warn "sshd binary not found; skipped config test."
    return 0
  fi
  "$sshd_bin" -t
}

restart_ssh_service() {
  local svc
  svc="$(find_ssh_service)"
  service_action restart "$svc"
}

open_firewall_port() {
  local port="$1"

  if command_exists ufw && ufw status 2>/dev/null | grep -qi 'Status: active'; then
    ufw allow "${port}/tcp"
    success "Allowed ${port}/tcp in ufw."
  fi

  if command_exists firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${port}/tcp"
    firewall-cmd --reload
    success "Allowed ${port}/tcp in firewalld."
  fi
}

configure_ssh_port() {
  require_root
  detect_system

  local port
  local detected
  detected="$(current_ssh_port)"
  detected="${detected:-22}"

  cat <<EOF

Change SSH port
---------------
This will edit /etc/ssh/sshd_config and restart SSH.
Keep your current SSH session open until a new login works.

EOF

  while true; do
    port="$(prompt_value "New SSH port" "$detected")"
    if is_valid_port "$port"; then
      break
    fi
    warn "Invalid port. Use a number from 1 to 65535."
  done

  warn "Make sure your VPS provider firewall/security group also allows TCP $port."
  ask_yes_no "Apply SSH port $port now?" n || return 0

  set_sshd_option "Port" "$port"

  if test_sshd_config; then
    if ask_yes_no "Open TCP $port in local firewall when ufw/firewalld is active?" y; then
      open_firewall_port "$port"
    fi
    restart_ssh_service
    success "SSH port changed to $port."
    warn "Do not close this session until you verify: ssh -p $port user@server_ip"
  else
    fail "SSH config test failed. Restore the generated backup before restarting SSH."
    return 1
  fi
}

install_ookla_speedtest() {
  require_root
  detect_system
  pkg_install curl ca-certificates

  cat <<EOF

Ookla Speedtest CLI
-------------------
This option downloads and runs Ookla's package repository setup script,
then installs the official speedtest command.

EOF

  ask_yes_no "Continue with Ookla repository setup?" n || return 0

  case "$PKG_MANAGER" in
    apt)
      curl -fsSL https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
      DEBIAN_FRONTEND=noninteractive apt-get install -y speedtest
      ;;
    dnf|yum)
      curl -fsSL https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash
      pkg_install speedtest
      ;;
    *)
      fail "Official Ookla repository setup is not supported for $PKG_MANAGER."
      return 1
      ;;
  esac

  success "Speedtest CLI installed."
  if ask_yes_no "Run speedtest now?" y; then
    speedtest --accept-license --accept-gdpr || speedtest
  fi
}

install_package_speedtest() {
  require_root
  detect_system
  pkg_update || true
  if pkg_install speedtest-cli; then
    success "speedtest-cli installed."
    ask_yes_no "Run speedtest-cli now?" y && speedtest-cli
  else
    fail "Package install failed. Try the official Ookla option."
  fi
}

speedtest_menu() {
  while true; do
    cat <<EOF

Speed Test
----------
1) Install official Ookla Speedtest CLI
2) Install distro package speedtest-cli
3) Run installed speedtest command
0) Back

EOF
    local choice
    choice="$(prompt_value "Choose an option" "0")"
    case "$choice" in
      1) install_ookla_speedtest; pause ;;
      2) install_package_speedtest; pause ;;
      3)
        if command_exists speedtest; then
          speedtest --accept-license --accept-gdpr || speedtest
        elif command_exists speedtest-cli; then
          speedtest-cli
        else
          warn "No speedtest command found. Install one first."
        fi
        pause
        ;;
      0) return 0 ;;
      *) warn "Unknown option." ;;
    esac
  done
}

install_docker() {
  require_root
  detect_system

  show_system

  if command_exists docker; then
    docker --version || true
    ask_yes_no "Docker already exists. Continue anyway?" n || return 0
  fi

  cat <<EOF

Docker installation
-------------------
This uses Docker's official convenience installer from:
https://get.docker.com

The installer auto-detects supported Linux distributions and configures
the matching Docker package repository.

EOF

  ask_yes_no "Download and run Docker official installer?" n || return 0
  pkg_install curl ca-certificates

  local installer
  installer="$(mktemp)"
  curl -fsSL https://get.docker.com -o "$installer"
  sh "$installer"
  rm -f "$installer"

  enable_and_start_service docker || true

  if command_exists docker; then
    docker --version
    docker compose version || true
    success "Docker installation finished."
  else
    fail "Docker command was not found after installation."
    return 1
  fi

  local target_user
  target_user="${SUDO_USER:-}"
  if [[ -n "$target_user" ]] && id "$target_user" >/dev/null 2>&1; then
    if ask_yes_no "Add user '$target_user' to docker group?" y; then
      groupadd -f docker
      usermod -aG docker "$target_user"
      success "User '$target_user' added to docker group. Re-login is required."
    fi
  fi
}

install_acme_sh() {
  local email="$1"
  pkg_install curl socat openssl ca-certificates

  if [[ -x "$HOME/.acme.sh/acme.sh" ]]; then
    success "acme.sh already installed."
    return 0
  fi

  ask_yes_no "Install acme.sh for SSL certificate management?" y || return 1
  curl -fsSL https://get.acme.sh | sh -s email="$email"
}

acme_bin() {
  if [[ -x "$HOME/.acme.sh/acme.sh" ]]; then
    printf '%s/.acme.sh/acme.sh' "$HOME"
  elif [[ -x /root/.acme.sh/acme.sh ]]; then
    printf '/root/.acme.sh/acme.sh'
  else
    printf ''
  fi
}

issue_ssl_certificate() {
  require_root
  detect_system

  local domain
  local email
  local mode
  local webroot
  local cert_dir
  local acme

  cat <<EOF

SSL certificate
---------------
This feature uses acme.sh. You must point the domain DNS record to this VPS.
Standalone mode requires TCP port 80 to be reachable from the Internet.

EOF

  domain="$(prompt_value "Domain name")"
  if [[ -z "$domain" ]]; then
    warn "Domain is required."
    return 0
  fi

  email="$(prompt_value "Email for ACME account" "admin@$domain")"
  install_acme_sh "$email" || return 1

  acme="$(acme_bin)"
  if [[ -z "$acme" ]]; then
    fail "acme.sh not found after installation."
    return 1
  fi

  "$acme" --set-default-ca --server letsencrypt

  cat <<EOF

Issue mode
----------
1) Standalone HTTP-01 (temporary listener on port 80)
2) Webroot HTTP-01 (existing web server document root)

EOF
  mode="$(prompt_value "Choose issue mode" "1")"

  case "$mode" in
    1)
      warn "Stop services using port 80 before issuing in standalone mode."
      ask_yes_no "Issue certificate for $domain using standalone mode?" n || return 0
      "$acme" --issue --standalone -d "$domain" --keylength ec-256
      ;;
    2)
      webroot="$(prompt_value "Webroot path" "/var/www/html")"
      ask_yes_no "Issue certificate for $domain using webroot $webroot?" n || return 0
      "$acme" --issue --webroot "$webroot" -d "$domain" --keylength ec-256
      ;;
    *)
      warn "Unknown issue mode."
      return 0
      ;;
  esac

  cert_dir="$(prompt_value "Install cert directory" "/etc/ssl/vpsmanage/$domain")"
  mkdir -p "$cert_dir"
  "$acme" --install-cert -d "$domain" --ecc \
    --fullchain-file "$cert_dir/fullchain.pem" \
    --key-file "$cert_dir/privkey.pem"
  chmod 600 "$cert_dir/privkey.pem"
  success "Certificate installed under: $cert_dir"
}

install_fail2ban() {
  require_root
  local jail="/etc/fail2ban/jail.local"
  local ssh_port

  pkg_update || true
  pkg_install fail2ban

  ssh_port="$(current_ssh_port)"
  ssh_port="${ssh_port:-ssh}"

  if [[ ! -f "$jail" ]]; then
    cat >"$jail" <<EOF
[sshd]
enabled = true
port = $ssh_port
maxretry = 5
findtime = 600
bantime = 3600
EOF
    success "Created $jail"
  else
    warn "$jail already exists; leaving it unchanged."
  fi

  enable_and_start_service fail2ban || service_action restart fail2ban || true
  success "fail2ban is installed."
}

configure_firewall_baseline() {
  require_root
  detect_system

  local ssh_port
  ssh_port="$(current_ssh_port)"
  ssh_port="${ssh_port:-22}"

  cat <<EOF

Firewall baseline
-----------------
This allows SSH ($ssh_port/tcp), HTTP (80/tcp), and HTTPS (443/tcp).
It enables ufw on Debian/Ubuntu or firewalld on RHEL-like systems.

EOF

  ask_yes_no "Apply firewall baseline?" n || return 0

  if [[ "$PKG_MANAGER" == "apt" ]]; then
    pkg_install ufw
    ufw allow "${ssh_port}/tcp"
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    ufw status verbose
  elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
    pkg_install firewalld
    enable_and_start_service firewalld
    firewall-cmd --permanent --add-port="${ssh_port}/tcp"
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
    firewall-cmd --list-all
  elif [[ "$PKG_MANAGER" == "apk" ]]; then
    warn "Alpine firewall setup is not automated yet. Configure nftables/iptables manually."
  else
    fail "Unsupported package manager."
    return 1
  fi
}

disable_ssh_password_login() {
  require_root
  warn "Make sure SSH key login works before disabling password authentication."
  ask_yes_no "Disable SSH password authentication now?" n || return 0

  set_sshd_option "PasswordAuthentication" "no"
  set_sshd_option "KbdInteractiveAuthentication" "no"
  set_sshd_option "ChallengeResponseAuthentication" "no"
  test_sshd_config
  restart_ssh_service
  success "SSH password authentication disabled."
}

disable_root_ssh_login() {
  require_root
  warn "Make sure a sudo-capable non-root user can log in before disabling root SSH."
  ask_yes_no "Disable root SSH login now?" n || return 0

  set_sshd_option "PermitRootLogin" "no"
  test_sshd_config
  restart_ssh_service
  success "Root SSH login disabled."
}

enable_auto_security_updates() {
  require_root
  detect_system

  ask_yes_no "Enable automatic security updates?" n || return 0

  if [[ "$PKG_MANAGER" == "apt" ]]; then
    pkg_install unattended-upgrades apt-listchanges
    cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    systemctl enable --now unattended-upgrades 2>/dev/null || true
    success "Automatic security updates enabled for apt."
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    pkg_install dnf-automatic
    sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
    systemctl enable --now dnf-automatic.timer
    success "Automatic updates enabled for dnf."
  else
    warn "Automatic security updates are not automated for $PKG_MANAGER."
  fi
}

security_menu() {
  while true; do
    cat <<EOF

Security
--------
1) Update system packages
2) Install and enable fail2ban
3) Configure firewall baseline
4) Disable SSH password authentication
5) Disable root SSH login
6) Enable automatic security updates
0) Back

EOF
    local choice
    choice="$(prompt_value "Choose an option" "0")"
    case "$choice" in
      1) require_root; pkg_update; pkg_upgrade; pause ;;
      2) install_fail2ban; pause ;;
      3) configure_firewall_baseline; pause ;;
      4) disable_ssh_password_login; pause ;;
      5) disable_root_ssh_login; pause ;;
      6) enable_auto_security_updates; pause ;;
      0) return 0 ;;
      *) warn "Unknown option." ;;
    esac
  done
}

basic_ip_quality() {
  require_root
  pkg_install curl ca-certificates

  cat <<EOF

Basic IP information
--------------------
This queries public HTTP APIs and prints their raw responses.

EOF

  echo "Public IP:"
  curl -fsSL https://api64.ipify.org || true
  printf '\n\nipinfo.io:\n'
  curl -fsSL https://ipinfo.io/json || true
  printf '\n\nip-api.com:\n'
  curl -fsSL "http://ip-api.com/json/?fields=status,message,country,regionName,city,isp,org,as,asname,proxy,hosting,query" || true
  printf '\n'
}

run_remote_script_url() {
  require_root
  local url="$1"
  local tmp

  if [[ ! "$url" =~ ^https?:// ]]; then
    fail "Only http/https URLs are allowed."
    return 1
  fi

  pkg_install curl ca-certificates
  tmp="$(mktemp)"
  curl -fsSL "$url" -o "$tmp"

  warn "Downloaded remote script: $url"
  warn "Reviewing third-party scripts is recommended before running them."
  ask_yes_no "Run this remote script now?" n || {
    rm -f "$tmp"
    return 0
  }

  bash "$tmp"
  rm -f "$tmp"
}

ip_quality_menu() {
  while true; do
    cat <<EOF

IP Quality
----------
1) Basic public IP information
2) Run IP.Check.Place advanced script
3) Run custom remote quality-test script URL
0) Back

EOF
    local choice
    local url
    choice="$(prompt_value "Choose an option" "0")"
    case "$choice" in
      1) basic_ip_quality; pause ;;
      2) run_remote_script_url "https://IP.Check.Place"; pause ;;
      3)
        url="$(prompt_value "Remote script URL")"
        [[ -n "$url" ]] && run_remote_script_url "$url"
        pause
        ;;
      0) return 0 ;;
      *) warn "Unknown option." ;;
    esac
  done
}

main_menu() {
  detect_system

  while true; do
    cat <<EOF

VPSmanage $VERSION
==================
OS: $OS_PRETTY

1) Show detected system environment
2) Set VPS SSH port
3) Install or run Speedtest
4) Install Docker
5) Issue SSL certificate
6) Security measures
7) IP quality test
0) Exit

EOF
    local choice
    choice="$(prompt_value "Choose an option" "0")"
    case "$choice" in
      1) show_system; pause ;;
      2) configure_ssh_port; pause ;;
      3) speedtest_menu ;;
      4) install_docker; pause ;;
      5) issue_ssl_certificate; pause ;;
      6) security_menu ;;
      7) ip_quality_menu ;;
      0) success "Bye."; exit 0 ;;
      *) warn "Unknown option." ;;
    esac
  done
}

usage() {
  cat <<EOF
VPSmanage $VERSION

Usage:
  sudo bash vpsmanage.sh [command]

Commands:
  menu        Open interactive menu (default)
  detect      Show detected system environment
  ssh-port    Set SSH port interactively
  speedtest   Open speedtest menu
  docker      Install Docker interactively
  ssl         Issue SSL certificate interactively
  security    Open security menu
  ip-quality  Open IP quality menu
  help        Show this help
EOF
}

main() {
  case "${1:-menu}" in
    menu) main_menu ;;
    detect) show_system ;;
    ssh-port) configure_ssh_port ;;
    speedtest) speedtest_menu ;;
    docker) install_docker ;;
    ssl) issue_ssl_certificate ;;
    security) security_menu ;;
    ip-quality) ip_quality_menu ;;
    help|-h|--help) usage ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
