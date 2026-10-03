#!/usr/bin/env bash
set -u

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

ok()   { printf "${GREEN}[OK]${RESET}   %-22s %s\n" "$1" "${2:-}"; }
warn() { printf "${YELLOW}[WARN]${RESET} %-22s %s\n" "$1" "${2:-}"; }

check_cmd() {
  local label="$1" cmd="$2" version_cmd="${3:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    local v=""
    [[ -n "$version_cmd" ]] && v="$(bash -lc "$version_cmd" 2>/dev/null | head -n1 || true)"
    ok "$label" "$v"
  else
    warn "$label" "no encontrado"
  fi
}

echo "Ubuntu workstation check"
echo "========================"

if [[ -r /etc/os-release ]]; then . /etc/os-release; ok "OS" "${PRETTY_NAME:-unknown}"; fi
ok "Kernel" "$(uname -r)"

check_cmd "Git" git 'git --version'
check_cmd "SSH client" ssh 'ssh -V 2>&1'
systemctl is-active --quiet ssh 2>/dev/null && ok "SSH server" "activo" || warn "SSH server" "inactivo"

if [[ -f "$HOME/.ssh/id_ed25519_github" && -f "$HOME/.ssh/id_ed25519_github.pub" ]]; then
  ok "GitHub SSH key" "$(ssh-keygen -lf "$HOME/.ssh/id_ed25519_github.pub" 2>/dev/null | awk '{print $2, $4}')"
else
  warn "GitHub SSH key" "no existe ~/.ssh/id_ed25519_github"
fi

check_cmd "Tailscale" tailscale 'tailscale version | head -n1'
if command -v tailscale >/dev/null 2>&1; then
  if tailscale status >/dev/null 2>&1; then
    ok "Tailscale status" "$(tailscale ip -4 2>/dev/null | head -n1)"
  else
    warn "Tailscale status" "instalado pero no conectado/autenticado"
  fi
fi

check_cmd "Docker" docker 'docker --version'
if command -v docker >/dev/null 2>&1; then
  docker info >/dev/null 2>&1 && ok "Docker daemon" "accesible" || warn "Docker daemon" "sin acceso (grupo/login?)"
  docker compose version >/dev/null 2>&1 && ok "Docker Compose" "$(docker compose version --short 2>/dev/null)" || warn "Docker Compose" "no encontrado"
fi

check_cmd "VirtualBox" VBoxManage 'VBoxManage --version'

if lspci 2>/dev/null | grep -qi nvidia; then
  if command -v nvidia-smi >/dev/null 2>&1; then
    ok "NVIDIA" "$(nvidia-smi --query-gpu=driver_version,name --format=csv,noheader 2>/dev/null | head -n1)"
  else
    warn "NVIDIA" "GPU detectada pero nvidia-smi no disponible"
  fi
fi

if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.nvm/nvm.sh"
  ok "NVM" "$(nvm --version)"
  command -v node >/dev/null 2>&1 && ok "Node" "$(node -v)" || warn "Node" "no instalado"
else
  warn "NVM" "no encontrado"
fi

java_checked=0
if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  sdkman_version="$(
    set +u
    # shellcheck disable=SC1090
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    sdk version 2>/dev/null | tail -n1
  )"
  if [[ -n "$sdkman_version" ]]; then
    ok "SDKMAN" "$sdkman_version"
  else
    warn "SDKMAN" "instalado, pero no se pudo obtener la versión"
  fi

  sdkman_java_version="$(
    set +u
    # shellcheck disable=SC1090
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    java -version 2>&1 | head -n1 || true
  )"
  if [[ -n "$sdkman_java_version" ]]; then
    ok "Java (SDKMAN)" "$sdkman_java_version"
    java_checked=1
  fi
else
  warn "SDKMAN" "no encontrado"
fi

if [[ "$java_checked" -eq 0 ]]; then
  check_cmd "Java" java 'java -version 2>&1'
fi
check_cmd "uv" uv 'uv --version'

check_cmd "dig" dig 'dig -v 2>&1'
check_cmd "netcat" nc ''
check_cmd "traceroute" traceroute 'traceroute --version 2>&1'
check_cmd "whois" whois 'whois --version 2>&1'
check_cmd "iperf3" iperf3 'iperf3 --version 2>&1'

check_cmd "mkcert" mkcert 'mkcert --version 2>&1'
if command -v mkcert >/dev/null 2>&1; then
  mkcert_caroot="$(mkcert -CAROOT 2>/dev/null || true)"
  if [[ -n "$mkcert_caroot" && -f "$mkcert_caroot/rootCA.pem" && -f "$mkcert_caroot/rootCA-key.pem" ]]; then
    ok "mkcert local CA" "$mkcert_caroot"
  else
    warn "mkcert local CA" "mkcert instalado pero la CA local no está creada"
  fi
fi

export PATH="$HOME/.local/bin:$PATH"
check_cmd "Oh My Posh" oh-my-posh 'oh-my-posh version'
if command -v fc-list >/dev/null 2>&1 && fc-list | grep -qi '0xProto.*Nerd'; then
  ok "0xProto Nerd Font" "instalada"
else
  warn "0xProto Nerd Font" "no encontrada"
fi

if command -v gsettings >/dev/null 2>&1 \
  && gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.Ptyxis'; then
  ptyxis_use_system_font="$(gsettings get org.gnome.Ptyxis use-system-font 2>/dev/null || true)"
  ptyxis_font="$(gsettings get org.gnome.Ptyxis font-name 2>/dev/null || true)"
  if [[ "$ptyxis_use_system_font" == "false" ]]; then
    ok "Ptyxis font" "$ptyxis_font"
  else
    warn "Ptyxis font" "usa la fuente monoespaciada del sistema"
  fi
fi

export PATH="$HOME/.pub-cache/bin:$HOME/.local/share/flutter-bootstrap/bin:$PATH"
check_cmd "FVM" fvm 'fvm --version'

if command -v code >/dev/null 2>&1; then
  ok "VS Code" "$(code --version 2>/dev/null | head -n1)"
elif snap list code >/dev/null 2>&1; then
  ok "VS Code (Snap)" "$(snap list code | awk 'NR==2 {print $2}')"
else
  warn "VS Code" "no encontrado"
fi

if command -v brave-browser >/dev/null 2>&1; then
  ok "Brave" "$(brave-browser --version 2>/dev/null | head -n1)"
elif command -v brave >/dev/null 2>&1; then
  ok "Brave (Snap)" "$(brave --version 2>/dev/null | head -n1)"
elif snap list brave >/dev/null 2>&1; then
  ok "Brave (Snap)" "$(snap list brave | awk 'NR==2 {print $2}')"
else
  warn "Brave" "no encontrado"
fi

if dpkg -s bruno >/dev/null 2>&1; then
  ok "Bruno (APT)" "$(dpkg-query -W -f='${Version}' bruno 2>/dev/null)"
elif snap list bruno >/dev/null 2>&1; then
  warn "Bruno (Snap)" "$(snap list bruno | awk 'NR==2 {print $2}') · puede sufrir el bug de fuentes/diálogos en Ubuntu"
elif command -v bruno >/dev/null 2>&1; then
  ok "Bruno" "$(bruno --version 2>/dev/null | head -n1)"
else
  warn "Bruno" "no encontrado"
fi

if command -v intellij-idea >/dev/null 2>&1; then
  ok "IntelliJ IDEA" "Snap/CLI disponible"
elif snap list intellij-idea >/dev/null 2>&1; then
  ok "IntelliJ IDEA (Snap)" "$(snap list intellij-idea | awk 'NR==2 {print $2}')"
elif [[ -x "$HOME/.local/opt/jetbrains-toolbox/bin/jetbrains-toolbox" ]]; then
  ok "JetBrains Toolbox" "~/.local/opt/jetbrains-toolbox"
else
  warn "IntelliJ IDEA" "no encontrado"
fi

[[ -x /opt/android-studio/bin/studio ]] && ok "Android Studio" "/opt/android-studio" || warn "Android Studio" "no instalado en /opt/android-studio"
command -v studio >/dev/null 2>&1 && ok "Android Studio CLI" "$(command -v studio)" || warn "Android Studio CLI" "comando studio no encontrado"
[[ -f /usr/local/share/applications/android-studio.desktop ]] && ok "Android Studio menu" "lanzador instalado" || warn "Android Studio menu" "lanzador no encontrado"

android_sdk="${ANDROID_HOME:-$HOME/Android/Sdk}"
if command -v adb >/dev/null 2>&1; then
  ok "ADB" "$(adb version 2>/dev/null | head -n1)"
elif [[ -x "$android_sdk/platform-tools/adb" ]]; then
  warn "ADB" "instalado en $android_sdk/platform-tools pero no está en el PATH de esta sesión"
else
  warn "ADB" "Platform-Tools no instalado todavía en $android_sdk"
fi

[[ -d "$HOME/dev/infrastructure" ]] && ok "Dev infrastructure" "$HOME/dev/infrastructure" || warn "Dev infrastructure" "ejecuta post-install.sh"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo
  echo "Imágenes Docker locales:"
  docker image ls --format '  {{.Repository}}:{{.Tag}}' | sort
fi

echo
echo "Grupos (los nuevos requieren cerrar sesión y entrar):"
id -nG | tr ' ' '\n' | grep -E '^(docker|vboxusers)$' || true
