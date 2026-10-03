#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

BLUE='\033[1;34m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

header() {
  clear 2>/dev/null || true
  printf "${CYAN}"
  cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║                   UBUNTU DEVELOPER CENTER                    ║
║                 workstation bootstrap 26.04                  ║
╚══════════════════════════════════════════════════════════════╝
EOF
  printf "${RESET}\n"
}

run_script() {
  local script="$1"
  if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
    printf "${YELLOW}No encuentro %s en %s${RESET}\n" "$script" "$SCRIPT_DIR"
    return 1
  fi
  printf "${BLUE}Ejecutando %s...${RESET}\n\n" "$script"
  bash "$SCRIPT_DIR/$script"
}

pause() {
  printf "\n${GREEN}Pulsa Enter para volver al centro de inicio...${RESET}"
  read -r _
}

while true; do
  header
  cat <<'EOF'
  1) Sistema base, NVIDIA, Docker, Tailscale y VirtualBox
  2) Herramientas de desarrollo y aplicaciones
  3) Post-install: carpetas, Git/SSH e imágenes Docker
  4) Comprobar estado del equipo
  5) Ver README
  0) Salir
EOF
  printf "\nSelecciona una opción: "
  read -r choice

  case "$choice" in
    1) run_script "bootstrap.sh"; pause ;;
    2) run_script "dev-tools.sh"; pause ;;
    3) run_script "post-install.sh"; pause ;;
    4) run_script "check.sh"; pause ;;
    5)
      if command -v less >/dev/null 2>&1; then
        less "$SCRIPT_DIR/README.md"
      else
        cat "$SCRIPT_DIR/README.md"
        pause
      fi
      ;;
    0) exit 0 ;;
    *) printf "${YELLOW}Opción no válida.${RESET}\n"; sleep 1 ;;
  esac
done
