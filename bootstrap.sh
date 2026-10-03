#!/usr/bin/env bash
set -Eeuo pipefail

# Ubuntu workstation bootstrap
# System packages, NVIDIA, Docker Engine and VirtualBox.
# Safe to re-run.

SKIP_NVIDIA=0
SKIP_VIRTUALBOX=0
SKIP_DOCKER=0
SKIP_TAILSCALE=0

for arg in "$@"; do
  case "$arg" in
    --skip-nvidia) SKIP_NVIDIA=1 ;;
    --skip-virtualbox) SKIP_VIRTUALBOX=1 ;;
    --skip-docker) SKIP_DOCKER=1 ;;
    --skip-tailscale) SKIP_TAILSCALE=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./bootstrap.sh [options]

Options:
  --skip-nvidia      Do not install the recommended NVIDIA driver
  --skip-virtualbox  Do not install VirtualBox
  --skip-docker      Do not install Docker Engine
  --skip-tailscale   Do not install Tailscale
EOF
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }

ask_yes_no() {
  local prompt="$1" default="${2:-n}" answer hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"
  read -r -p "$prompt $hint " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[YySs]$ ]]
}

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as your normal user, not as root." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the operating system." >&2
  exit 1
fi
. /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script is intended for Ubuntu. Detected: ${PRETTY_NAME:-unknown}" >&2
  exit 1
fi

if [[ "${VERSION_ID:-}" != "26.04" ]]; then
  warn "Designed/tested for Ubuntu 26.04. Detected ${VERSION_ID:-unknown}."
  warn "Continuing, but review third-party repositories before using this on another release."
fi

log "Updating Ubuntu"
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt full-upgrade -y

log "Installing base packages"
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
  ca-certificates curl wget gnupg git openssh-client openssh-server \
  build-essential dkms linux-headers-"$(uname -r)" \
  jq tree btop unzip zip xz-utils rsync \
  software-properties-common apt-transport-https \
  pciutils usbutils lm-sensors

sudo systemctl enable --now ssh
ok "Base packages and SSH installed"


if [[ "$SKIP_TAILSCALE" -eq 0 ]]; then
  log "Instalando Tailscale"

  if ! command -v tailscale >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh
  else
    ok "Tailscale ya está instalado: $(tailscale version | head -n1)"
  fi

  if systemctl list-unit-files tailscaled.service >/dev/null 2>&1; then
    sudo systemctl enable --now tailscaled
  fi

  if command -v tailscale >/dev/null 2>&1; then
    ok "Tailscale $(tailscale version | head -n1)"

    if ask_yes_no "¿Conectar y autenticar este equipo en Tailscale ahora?" y; then
      sudo tailscale up
    else
      warn "Tailscale instalado pero no autenticado. Después puedes ejecutar: sudo tailscale up"
    fi
  else
    warn "La instalación de Tailscale no dejó el comando disponible."
  fi
else
  warn "Skipping Tailscale"
fi

if [[ "$SKIP_NVIDIA" -eq 0 ]] && lspci 2>/dev/null | grep -qi nvidia; then
  log "Installing Ubuntu's recommended NVIDIA driver"
  sudo apt install -y ubuntu-drivers-common
  sudo ubuntu-drivers install || warn "NVIDIA automatic installation returned an error; inspect with: ubuntu-drivers devices"
else
  warn "Skipping NVIDIA driver installation"
fi

if [[ "$SKIP_DOCKER" -eq 0 ]]; then
  log "Installing Docker Engine from Docker's official APT repository"

  # Remove packages that conflict with Docker CE. Ignore if absent.
  for pkg in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
    sudo apt remove -y "$pkg" >/dev/null 2>&1 || true
  done

  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  . /etc/os-release
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  sudo apt update
  sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  sudo systemctl enable --now docker

  if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    ok "El usuario $USER ya pertenece al grupo docker"
  elif ask_yes_no "¿Añadir $USER al grupo docker para usar Docker sin sudo?" y; then
    sudo usermod -aG docker "$USER"
    ok "Usuario añadido al grupo docker; cierra sesión y vuelve a entrar para aplicarlo"
  else
    warn "No se modificó el grupo docker; usarás sudo con Docker"
  fi

  ok "Docker Engine instalado"
else
  warn "Skipping Docker"
fi

if [[ "$SKIP_VIRTUALBOX" -eq 0 ]]; then
  log "Installing VirtualBox"
  sudo apt update
  sudo DEBIAN_FRONTEND=noninteractive apt install -y virtualbox

  # Ubuntu may package the Guest Additions ISO separately.
  if apt-cache show virtualbox-guest-additions-iso >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y virtualbox-guest-additions-iso
    ok "Guest Additions ISO package installed"
  else
    warn "virtualbox-guest-additions-iso is not available in this Ubuntu repository."
    warn "VirtualBox can still insert/download its Guest Additions ISO from the VM menu."
  fi

  sudo usermod -aG vboxusers "$USER" || true
  ok "VirtualBox installed; log out/in for vboxusers membership to take effect"
else
  warn "Skipping VirtualBox"
fi

log "Finished"
cat <<'EOF'
Recommended next steps:
  1. Reboot if the NVIDIA driver or kernel packages changed.
  2. Log out/in so docker and vboxusers group membership is refreshed.
  3. If Tailscale was installed but not authenticated, run: sudo tailscale up
  4. Run ./dev-tools.sh
  5. Run ./post-install.sh
  6. Run ./check.sh

For a Windows guest:
  VirtualBox -> Devices -> Insert Guest Additions CD image...
  Then run VBoxWindowsAdditions.exe inside Windows.
EOF
