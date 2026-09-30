#!/usr/bin/env bash
set -Eeuo pipefail

# Interactive developer tool installer.
# Safe to re-run. Installs only what the user selects.

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }

if [[ "${EUID}" -eq 0 ]]; then
  echo "Ejecuta este script con tu usuario normal, no como root." >&2
  exit 1
fi

ensure_snap() {
  if ! command -v snap >/dev/null 2>&1; then
    log "Instalando snapd"
    sudo apt update
    sudo apt install -y snapd
  fi
}

ask_yes_no() {
  local prompt="$1" default="${2:-n}" answer
  local hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"
  read -r -p "$prompt $hint " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[YySs]$ ]]
}

choose_method() {
  local app="$1" primary="$2"
  printf "\n${CYAN}%s${RESET}\n" "$app" >&2
  printf "  1) %s\n" "$primary" >&2
  printf "  2) Snap\n" >&2
  printf "  0) No instalar\n" >&2
  while true; do
    read -r -p "Método: " method
    case "$method" in
      1|2|0) printf '%s\n' "$method"; return 0 ;;
      *) warn "Opción no válida" ;;
    esac
  done
}

# Toggle menu. Usage: toggle_menu "Title" names_array selected_array
toggle_menu() {
  local title="$1"
  local -n _names="$2"
  local -n _selected="$3"
  local input i

  while true; do
    printf "\n${CYAN}%s${RESET}\n" "$title"
    for i in "${!_names[@]}"; do
      if [[ "${_selected[$i]}" -eq 1 ]]; then
        printf "  %d) [x] %s\n" "$((i+1))" "${_names[$i]}"
      else
        printf "  %d) [ ] %s\n" "$((i+1))" "${_names[$i]}"
      fi
    done
    printf "  a) Marcar todo\n"
    printf "  n) Desmarcar todo\n"
    printf "  c) Continuar\n"
    read -r -p "Alterna una opción: " input

    case "$input" in
      a|A) for i in "${!_selected[@]}"; do _selected[$i]=1; done ;;
      n|N) for i in "${!_selected[@]}"; do _selected[$i]=0; done ;;
      c|C|"") return 0 ;;
      *)
        if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#_names[@]} )); then
          i=$((input-1))
          _selected[$i]=$((1 - _selected[$i]))
        else
          warn "Opción no válida"
        fi
        ;;
    esac
  done
}

install_git() {
  log "Instalando Git"
  sudo apt update
  sudo apt install -y git
  ok "$(git --version)"
}

install_nvm_node() {
  log "Instalando NVM y Node LTS"
  sudo apt install -y curl ca-certificates
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
  fi
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
  ok "Node $(node -v) mediante NVM $(nvm --version)"
}

install_sdkman_java() {
  log "Instalando SDKMAN! y Java 21 Temurin"
  sudo apt install -y curl zip unzip
  if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    curl -s "https://get.sdkman.io" | bash
  fi
  # shellcheck disable=SC1090
  source "$HOME/.sdkman/bin/sdkman-init.sh"

  local java_id
  java_id="$(sdk list java | awk -F'|' '/21\..*-tem/ {gsub(/^[ \t]+|[ \t]+$/, "", $NF); if ($NF != "") {print $NF; exit}}')"
  if [[ -n "$java_id" ]]; then
    if ! sdk current java 2>/dev/null | grep -q "$java_id"; then
      sdk install java "$java_id" || true
    fi
    sdk default java "$java_id" || true
    java -version 2>&1 | head -n1
  else
    warn "No he podido resolver automáticamente Java 21 Temurin. Ejecuta: sdk list java"
  fi
}

install_uv() {
  log "Instalando uv"
  sudo apt install -y curl ca-certificates
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  export PATH="$HOME/.local/bin:$PATH"
  ok "$(uv --version)"
}

install_flutter_fvm() {
  log "Instalando dependencias Flutter, SDK bootstrap y FVM"
  sudo apt update
  sudo apt install -y \
    curl git unzip xz-utils zip libglu1-mesa \
    clang cmake ninja-build pkg-config libgtk-3-dev

  local flutter_bootstrap="$HOME/.local/share/flutter-bootstrap"
  if [[ ! -d "$flutter_bootstrap/.git" ]]; then
    mkdir -p "$(dirname "$flutter_bootstrap")"
    git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$flutter_bootstrap"
  else
    git -C "$flutter_bootstrap" pull --ff-only || true
  fi

  export PATH="$flutter_bootstrap/bin:$HOME/.pub-cache/bin:$PATH"
  flutter --version

  if ! command -v fvm >/dev/null 2>&1; then
    dart pub global activate fvm
  fi

  if ! grep -Fq 'flutter-bootstrap/bin' "$HOME/.bashrc"; then
    cat >>"$HOME/.bashrc" <<'EOF'

# Flutter bootstrap SDK (Dart para FVM)
export PATH="$HOME/.local/share/flutter-bootstrap/bin:$HOME/.pub-cache/bin:$PATH"
EOF
  fi

  fvm install stable
  ok "FVM $(fvm --version)"
}

find_download() {
  local pattern="$1"
  local dir file
  for dir in "$HOME/Downloads" "$HOME/Descargas"; do
    [[ -d "$dir" ]] || continue
    file="$(find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
      | sort -nr | head -n1 | cut -d' ' -f2- || true)"
    [[ -n "$file" ]] && { printf '%s\n' "$file"; return 0; }
  done
  return 1
}

install_android_studio() {
  log "Preparando Android Studio desde la página oficial"
  sudo dpkg --add-architecture i386
  sudo apt update
  sudo apt install -y \
    libc6:i386 libncurses6:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386 \
    curl ca-certificates libxml2-utils

  local archive=""
  local page_html dialog_html accepted_html license_txt
  local studio_url filename download_dir

  # Reuse a previously downloaded archive if it exists.
  if archive="$(find_download 'android-studio-*-linux.tar.gz')"; then
    ok "Archivo local encontrado: $archive"
  else
    page_html="$(mktemp)"
    dialog_html="$(mktemp)"
    accepted_html="$(mktemp)"
    license_txt="$(mktemp)"

    log "Descargando el nodo de descarga Linux desde developer.android.com"
    curl -fsSL --compressed "https://developer.android.com/studio" -o "$page_html"

    # Keep only the dialog that owns the Linux Studio licence checkbox.
    if ! xmllint --html --recover --xpath \
      '//input[@id="agree_studio_linux_bundle_download"]/ancestor::div[contains(concat(" ", normalize-space(@class), " "), " devsite-dialog-contents ")][1]' \
      "$page_html" 2>/dev/null >"$dialog_html" || [[ ! -s "$dialog_html" ]]; then
      warn "No he podido localizar el diálogo Linux de Android Studio en la página oficial."
      rm -f "$page_html" "$dialog_html" "$accepted_html" "$license_txt"
      return 1
    fi

    # Extract the licence text from that downloaded node. Nothing is copied into this repository.
    xmllint --html --recover --xpath \
      'string(//div[contains(concat(" ", normalize-space(@class), " "), " sdk-terms ")])' \
      "$dialog_html" 2>/dev/null >"$license_txt" || true

    printf "\n${CYAN}Términos y condiciones descargados de Android Developers${RESET}\n\n"
    if [[ -s "$license_txt" ]]; then
      if command -v less >/dev/null 2>&1 && [[ -t 1 ]]; then
        less "$license_txt"
      else
        cat "$license_txt"
      fi
    else
      warn "El nodo existe, pero no he podido extraer el texto de la licencia."
    fi

    printf "\n"
    if ! ask_yes_no "¿Has leído y aceptas estos términos y condiciones?" n; then
      warn "No se descargará Android Studio."
      rm -f "$page_html" "$dialog_html" "$accepted_html" "$license_txt"
      return 0
    fi

    # Represent the user's acceptance only in our local copy of the downloaded dialog.
    # This does not modify or submit anything to Google's server.
    sed -E \
      's/(<input[^>]*id="agree_studio_linux_bundle_download"[^>]*)(>)/\1 checked="checked"\2/' \
      "$dialog_html" >"$accepted_html"

    # Extract the direct Linux tar.gz URL from the accepted dialog.
    studio_url="$(
      grep -oE 'https://edgedl\.me\.gvt1\.com/android/studio/ide-zips/[^"[:space:]<>]+/android-studio-[^"[:space:]<>]+-linux\.tar\.gz' \
        "$accepted_html" | head -n1 || true
    )"

    if [[ -z "$studio_url" ]]; then
      warn "No he encontrado el enlace Linux esperado dentro del diálogo."
      rm -f "$page_html" "$dialog_html" "$accepted_html" "$license_txt"
      return 1
    fi

    filename="${studio_url##*/}"
    if [[ -d "$HOME/Descargas" ]]; then
      download_dir="$HOME/Descargas"
    else
      download_dir="$HOME/Downloads"
      mkdir -p "$download_dir"
    fi
    archive="$download_dir/$filename"

    printf "\nEnlace detectado:\n  %s\n" "$studio_url"
    log "Descargando $filename"
    curl -fL --retry 3 --retry-delay 2 --progress-bar "$studio_url" -o "$archive"

    rm -f "$page_html" "$dialog_html" "$accepted_html" "$license_txt"
  fi

  if [[ -n "$archive" && -f "$archive" ]]; then
    log "Validando el archivo descargado"
    if ! tar -tzf "$archive" >/dev/null; then
      warn "El archivo no parece ser un tar.gz válido: $archive"
      return 1
    fi

    sudo rm -rf /opt/android-studio
    sudo tar -xzf "$archive" -C /opt
    ok "Android Studio instalado en /opt/android-studio"
    printf "Archivo:  %s\n" "$archive"
    printf "Arranque: /opt/android-studio/bin/studio\n"
  fi
}

install_vscode_apt() {
  log "Instalando VS Code desde el repositorio oficial de Microsoft"
  sudo apt install -y wget gpg
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/packages.microsoft.gpg >/dev/null
  sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/packages.microsoft.gpg
EOF
  sudo apt update
  sudo apt install -y code
}

install_vscode_snap() {
  ensure_snap
  sudo snap install code --classic
}

install_brave_apt() {
  log "Instalando Brave desde su repositorio oficial"
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
    https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
  sudo apt update
  sudo apt install -y brave-browser
}

install_brave_snap() {
  ensure_snap
  sudo snap install brave
}

install_intellij_toolbox() {
  log "Instalando JetBrains Toolbox"
  sudo apt update
  sudo apt install -y \
    libxi6 libxrender1 libxtst6 mesa-utils libfontconfig1 \
    libgtk-3-bin dbus-user-session libxcb-keysyms1
  local archive tmp toolbox_bin
  if archive="$(find_download 'jetbrains-toolbox-*.tar.gz')"; then
    tmp="$(mktemp -d)"
    tar -xzf "$archive" -C "$tmp"
    toolbox_bin="$(find "$tmp" -type f -path '*/bin/jetbrains-toolbox' | head -n1 || true)"
    if [[ -n "$toolbox_bin" ]]; then
      mkdir -p "$HOME/.local/opt/jetbrains-toolbox"
      cp -a "$(dirname "$(dirname "$toolbox_bin")")/." "$HOME/.local/opt/jetbrains-toolbox/"
      ok "Toolbox instalado en ~/.local/opt/jetbrains-toolbox"
      printf "Ábrelo e instala IntelliJ IDEA desde allí.\n"
    else
      warn "No encuentro el ejecutable de Toolbox dentro del archivo."
    fi
    rm -rf "$tmp"
  else
    warn "No encuentro jetbrains-toolbox-*.tar.gz en ~/Downloads o ~/Descargas."
    warn "Descárgalo desde JetBrains Toolbox y vuelve a ejecutar esta opción."
  fi
}

install_intellij_snap() {
  ensure_snap
  sudo snap install intellij-idea --classic
}

core_names=("Git" "NVM + Node LTS" "SDKMAN! + Java 21" "uv")
core_selected=(1 1 1 1)
mobile_names=("Flutter + FVM" "Android Studio")
mobile_selected=(1 1)
apps_names=("VS Code" "IntelliJ IDEA" "Brave")
apps_selected=(1 1 1)

printf "${CYAN}Configuración de herramientas de desarrollo${RESET}\n"
toggle_menu "1/3 · Herramientas base" core_names core_selected
toggle_menu "2/3 · Desarrollo móvil" mobile_names mobile_selected
toggle_menu "3/3 · IDEs y navegador" apps_names apps_selected

printf "\n${BLUE}Resumen de selección${RESET}\n"
for i in "${!core_names[@]}"; do [[ "${core_selected[$i]}" -eq 1 ]] && printf "  + %s\n" "${core_names[$i]}"; done
for i in "${!mobile_names[@]}"; do [[ "${mobile_selected[$i]}" -eq 1 ]] && printf "  + %s\n" "${mobile_names[$i]}"; done
for i in "${!apps_names[@]}"; do [[ "${apps_selected[$i]}" -eq 1 ]] && printf "  + %s\n" "${apps_names[$i]}"; done

if ! ask_yes_no "¿Continuar con la instalación?" y; then
  echo "Cancelado."
  exit 0
fi

[[ "${core_selected[0]}" -eq 1 ]] && install_git
[[ "${core_selected[1]}" -eq 1 ]] && install_nvm_node
[[ "${core_selected[2]}" -eq 1 ]] && install_sdkman_java
[[ "${core_selected[3]}" -eq 1 ]] && install_uv

[[ "${mobile_selected[0]}" -eq 1 ]] && install_flutter_fvm
[[ "${mobile_selected[1]}" -eq 1 ]] && install_android_studio

if [[ "${apps_selected[0]}" -eq 1 ]]; then
  method="$(choose_method "VS Code" "Repositorio APT oficial de Microsoft")"
  case "$method" in
    1) install_vscode_apt ;;
    2) install_vscode_snap ;;
  esac
fi

if [[ "${apps_selected[1]}" -eq 1 ]]; then
  method="$(choose_method "IntelliJ IDEA" "JetBrains Toolbox")"
  case "$method" in
    1) install_intellij_toolbox ;;
    2) install_intellij_snap ;;
  esac
fi

if [[ "${apps_selected[2]}" -eq 1 ]]; then
  method="$(choose_method "Brave" "Repositorio APT oficial de Brave")"
  case "$method" in
    1) install_brave_apt ;;
    2) install_brave_snap ;;
  esac
fi

log "Herramientas de desarrollo terminadas"
cat <<'EOF'
Pendiente de forma intencionadamente interactiva:
  - Android Studio: completar el asistente de SDK/Emulator/Command-line Tools.
  - Flutter: fvm flutter doctor --android-licenses
  - JetBrains Toolbox: abrir Toolbox e instalar IntelliJ si elegiste ese método.
  - Git/SSH: identidad y claves se revisan en post-install.sh.
EOF
