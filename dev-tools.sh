#!/usr/bin/env bash
set -Eeuo pipefail

# Developer tools for Ubuntu.
# Installs NVM/Node LTS, SDKMAN!/Java, uv, Flutter+FVM,
# VS Code, Brave, Android Studio dependencies.
# Android Studio and JetBrains Toolbox tarballs are installed automatically
# if found in ~/Downloads or ~/Descargas.

INSTALL_BRAVE=1
INSTALL_FLUTTER=1
INSTALL_ANDROID_STUDIO=1
INSTALL_JETBRAINS_TOOLBOX=1

for arg in "$@"; do
  case "$arg" in
    --no-brave) INSTALL_BRAVE=0 ;;
    --no-flutter) INSTALL_FLUTTER=0 ;;
    --no-android-studio) INSTALL_ANDROID_STUDIO=0 ;;
    --no-jetbrains-toolbox) INSTALL_JETBRAINS_TOOLBOX=0 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./dev-tools.sh [options]

Options:
  --no-brave
  --no-flutter
  --no-android-studio
  --no-jetbrains-toolbox
EOF
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as your normal user, not as root." >&2
  exit 1
fi

log "Installing development dependencies"
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
  curl wget git ca-certificates gnupg build-essential \
  clang cmake ninja-build pkg-config libgtk-3-dev libglu1-mesa \
  unzip zip xz-utils \
  libc6:i386 libncurses6:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386

# NVM + Node LTS
log "Installing NVM and Node LTS"
export NVM_DIR="$HOME/.nvm"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
fi
# shellcheck disable=SC1090
source "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'
ok "Node $(node -v) via NVM"

# SDKMAN + Java 21 Temurin
log "Installing SDKMAN and Java 21 (Temurin)"
if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  curl -s "https://get.sdkman.io" | bash
fi
# shellcheck disable=SC1090
source "$HOME/.sdkman/bin/sdkman-init.sh"
if ! sdk current java 2>/dev/null | grep -q '21.*tem'; then
  # Resolve the current Temurin 21 identifier dynamically from SDKMAN.
  JAVA_ID="$(sdk list java | awk '/21\..*-tem/ && /\|/ {gsub(/^[ \t]+|[ \t]+$/, "", $NF); print $NF; exit}')"
  if [[ -n "${JAVA_ID:-}" ]]; then
    sdk install java "$JAVA_ID" || true
    sdk default java "$JAVA_ID" || true
  else
    warn "Could not resolve a Temurin 21 identifier automatically. Run: sdk list java"
  fi
fi
java -version 2>&1 | head -n 1 || true

# uv
log "Installing uv"
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
uv --version

# VS Code - official Microsoft APT repository
log "Installing Visual Studio Code"
if ! command -v code >/dev/null 2>&1; then
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
  sudo DEBIAN_FRONTEND=noninteractive apt install -y code
fi
ok "VS Code installed"

# Brave - official Brave APT repository
if [[ "$INSTALL_BRAVE" -eq 1 ]]; then
  log "Installing Brave from its official APT repository"
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
    https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
  sudo apt update
  sudo DEBIAN_FRONTEND=noninteractive apt install -y brave-browser
  ok "Brave installed"
fi

# Flutter bootstrap + FVM
if [[ "$INSTALL_FLUTTER" -eq 1 ]]; then
  log "Installing Flutter bootstrap SDK and FVM"
  FLUTTER_BOOTSTRAP="$HOME/.local/share/flutter-bootstrap"
  if [[ ! -d "$FLUTTER_BOOTSTRAP/.git" ]]; then
    mkdir -p "$(dirname "$FLUTTER_BOOTSTRAP")"
    git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_BOOTSTRAP"
  else
    git -C "$FLUTTER_BOOTSTRAP" pull --ff-only || true
  fi

  export PATH="$FLUTTER_BOOTSTRAP/bin:$HOME/.pub-cache/bin:$PATH"
  flutter --version

  if ! command -v fvm >/dev/null 2>&1; then
    dart pub global activate fvm
  fi

  if ! grep -Fq 'flutter-bootstrap/bin' "$HOME/.bashrc"; then
    cat >>"$HOME/.bashrc" <<'EOF'

# Flutter bootstrap SDK (provides Dart for FVM)
export PATH="$HOME/.local/share/flutter-bootstrap/bin:$HOME/.pub-cache/bin:$PATH"
EOF
  fi

  fvm --version
  fvm install stable
  ok "FVM installed; use 'fvm use <version>' inside each Flutter project"
fi

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

# Android Studio official tarball
if [[ "$INSTALL_ANDROID_STUDIO" -eq 1 ]]; then
  log "Looking for Android Studio tarball"
  if ANDROID_TGZ="$(find_download 'android-studio-*-linux.tar.gz')"; then
    sudo rm -rf /opt/android-studio
    sudo tar -xzf "$ANDROID_TGZ" -C /opt
    ok "Android Studio installed at /opt/android-studio"
    echo "Start it with: /opt/android-studio/bin/studio"
  else
    warn "Android Studio tarball not found in ~/Downloads or ~/Descargas."
    warn "Download the current Linux .tar.gz from developer.android.com/studio and rerun this script."
  fi
fi

# JetBrains Toolbox official tarball
if [[ "$INSTALL_JETBRAINS_TOOLBOX" -eq 1 ]]; then
  log "Looking for JetBrains Toolbox tarball"
  if TOOLBOX_TGZ="$(find_download 'jetbrains-toolbox-*.tar.gz')"; then
    TMP_DIR="$(mktemp -d)"
    tar -xzf "$TOOLBOX_TGZ" -C "$TMP_DIR"
    TOOLBOX_BIN="$(find "$TMP_DIR" -type f -path '*/bin/jetbrains-toolbox' | head -n1 || true)"
    if [[ -n "$TOOLBOX_BIN" ]]; then
      mkdir -p "$HOME/.local/opt/jetbrains-toolbox"
      cp -a "$(dirname "$(dirname "$TOOLBOX_BIN")")/." "$HOME/.local/opt/jetbrains-toolbox/"
      ok "JetBrains Toolbox copied to ~/.local/opt/jetbrains-toolbox"
      echo "Start it with: ~/.local/opt/jetbrains-toolbox/bin/jetbrains-toolbox"
    else
      warn "Could not locate jetbrains-toolbox binary in the archive."
    fi
    rm -rf "$TMP_DIR"
  else
    warn "JetBrains Toolbox tarball not found in ~/Downloads or ~/Descargas."
    warn "Download it from jetbrains.com/toolbox-app and rerun this script."
  fi
fi

log "Developer tools stage finished"
cat <<'EOF'
Still intentionally interactive/manual:
  - Android Studio first-run wizard: Android SDK, Platform Tools, Emulator, Command-line Tools.
  - Android SDK licences: run 'fvm flutter doctor --android-licenses' after Studio setup.
  - JetBrains Toolbox first run, then install IntelliJ IDEA.
  - Git identity and SSH keys (post-install.sh helps with the non-secret parts).
EOF
