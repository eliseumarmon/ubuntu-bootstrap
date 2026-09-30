#!/usr/bin/env bash
set -u

# Read-only workstation audit.

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

ok()   { printf "${GREEN}[OK]${RESET}   %-22s %s\n" "$1" "${2:-}"; }
warn() { printf "${YELLOW}[WARN]${RESET} %-22s %s\n" "$1" "${2:-}"; }
fail() { printf "${RED}[FAIL]${RESET} %-22s %s\n" "$1" "${2:-}"; }

check_cmd() {
  local label="$1" cmd="$2" version_cmd="${3:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    local v=""
    [[ -n "$version_cmd" ]] && v="$(bash -lc "$version_cmd" 2>/dev/null | head -n1 || true)"
    ok "$label" "$v"
  else
    warn "$label" "not found"
  fi
}

echo "Ubuntu workstation check"
echo "========================"

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  ok "OS" "${PRETTY_NAME:-unknown}"
fi
ok "Kernel" "$(uname -r)"

check_cmd "Git" git 'git --version'
check_cmd "SSH client" ssh 'ssh -V 2>&1'
if systemctl is-active --quiet ssh 2>/dev/null; then ok "SSH server" "active"; else warn "SSH server" "inactive"; fi

check_cmd "Docker" docker 'docker --version'
if command -v docker >/dev/null 2>&1; then
  docker info >/dev/null 2>&1 && ok "Docker daemon" "accessible" || warn "Docker daemon" "not accessible (group/login?)"
  docker compose version >/dev/null 2>&1 && ok "Docker Compose" "$(docker compose version --short 2>/dev/null)" || warn "Docker Compose" "not found"
fi

check_cmd "VirtualBox" VBoxManage 'VBoxManage --version'

if lspci 2>/dev/null | grep -qi nvidia; then
  if command -v nvidia-smi >/dev/null 2>&1; then
    NVIDIA_VER="$(nvidia-smi --query-gpu=driver_version,name --format=csv,noheader 2>/dev/null | head -n1 || true)"
    ok "NVIDIA" "$NVIDIA_VER"
  else
    warn "NVIDIA" "GPU detected but nvidia-smi is unavailable"
  fi
fi

# NVM is a shell function, so load it explicitly.
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.nvm/nvm.sh"
  ok "NVM" "$(nvm --version)"
  command -v node >/dev/null 2>&1 && ok "Node" "$(node -v)" || warn "Node" "not installed"
else
  warn "NVM" "not found"
fi

if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  ok "SDKMAN" "$(sdk version 2>/dev/null | tail -n1)"
else
  warn "SDKMAN" "not found"
fi
check_cmd "Java" java 'java -version 2>&1'
check_cmd "uv" uv 'uv --version'
check_cmd "Python via uv" uv 'uv python list --only-installed 2>/dev/null | head -n1'

export PATH="$HOME/.pub-cache/bin:$HOME/.local/share/flutter-bootstrap/bin:$PATH"
check_cmd "FVM" fvm 'fvm --version'
if command -v fvm >/dev/null 2>&1; then
  fvm flutter --version >/dev/null 2>&1 && ok "Flutter (FVM)" "$(fvm flutter --version 2>/dev/null | head -n1)" || warn "Flutter (FVM)" "no project/default SDK selected"
fi

check_cmd "VS Code" code 'code --version | head -n1'
check_cmd "Brave" brave-browser 'brave-browser --version'

if [[ -x /opt/android-studio/bin/studio ]]; then
  ok "Android Studio" "/opt/android-studio"
else
  warn "Android Studio" "not installed at /opt/android-studio"
fi

if [[ -x "$HOME/.local/opt/jetbrains-toolbox/bin/jetbrains-toolbox" ]]; then
  ok "JetBrains Toolbox" "~/.local/opt/jetbrains-toolbox"
else
  warn "JetBrains Toolbox" "not installed by this kit"
fi

if command -v adb >/dev/null 2>&1; then
  ok "ADB" "$(adb version 2>/dev/null | head -n1)"
else
  warn "ADB" "not in PATH (usually configured by Android Studio)"
fi

if [[ -d "$HOME/dev/infrastructure" ]]; then
  ok "Dev infrastructure" "$HOME/dev/infrastructure"
else
  warn "Dev infrastructure" "run ./post-install.sh"
fi

echo
echo "Group membership (new memberships require log out/in):"
id -nG | tr ' ' '\n' | grep -E '^(docker|vboxusers)$' || true
