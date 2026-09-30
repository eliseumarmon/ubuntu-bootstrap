#!/usr/bin/env bash
set -Eeuo pipefail

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }

ask_yes_no() {
  local prompt="$1" default="${2:-n}" answer hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"
  read -r -p "$prompt $hint " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[YySs]$ ]]
}

ask_tag() {
  local image="$1" tag
  read -r -p "Tag para $image [latest]: " tag
  printf '%s\n' "${tag:-latest}"
}

DEV_ROOT="${DEV_ROOT:-$HOME/dev}"
INFRA_DIR="$DEV_ROOT/infrastructure"
PROJECTS_DIR="$DEV_ROOT/projects"

mkdir -p "$INFRA_DIR" "$PROJECTS_DIR"

log "Configuración Git"
if command -v git >/dev/null 2>&1; then
  git config --global init.defaultBranch main
  git config --global pull.ff only
  git config --global fetch.prune true

  if [[ -z "$(git config --global user.name || true)" ]]; then
    read -r -p "Nombre para Git (Enter para dejar pendiente): " git_name
    [[ -n "${git_name:-}" ]] && git config --global user.name "$git_name"
  fi
  if [[ -z "$(git config --global user.email || true)" ]]; then
    read -r -p "Email para Git (Enter para dejar pendiente): " git_email
    [[ -n "${git_email:-}" ]] && git config --global user.email "$git_email"
  fi
else
  warn "Git no está instalado. Ejecútalo desde dev-tools.sh."
fi

log "SSH"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
  if ask_yes_no "No existe ~/.ssh/id_ed25519. ¿Generarla ahora?" n; then
    read -r -p "Email/comentario para la clave: " ssh_comment
    ssh-keygen -t ed25519 -C "$ssh_comment"
  else
    warn "Clave SSH pendiente."
  fi
else
  ok "Clave SSH Ed25519 existente"
fi

log "Terminal / Oh My Posh"
if ask_yes_no "¿Instalar o actualizar Oh My Posh?" y; then
  sudo apt update
  sudo apt install -y curl unzip fontconfig
  mkdir -p "$HOME/.local/bin"

  curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"

  if command -v oh-my-posh >/dev/null 2>&1; then
    ok "Oh My Posh $(oh-my-posh version)"

    if ask_yes_no "¿Instalar 0xProto Nerd Font?" y; then
      oh-my-posh font install 0xProto
      command -v fc-cache >/dev/null 2>&1 && fc-cache -f
      ok "0xProto Nerd Font instalada para el usuario"
      printf "Selecciona '0xProto Nerd Font' en el perfil de tu terminal y, si quieres, en la terminal integrada de VS Code.\n"
    fi

    if ask_yes_no "¿Activar Oh My Posh automáticamente en Bash?" y; then
      if ! grep -Fq '# Ubuntu Developer Center - Oh My Posh' "$HOME/.bashrc"; then
        cat >>"$HOME/.bashrc" <<'EOF'

# Ubuntu Developer Center - Oh My Posh
export PATH="$HOME/.local/bin:$PATH"
eval "$(oh-my-posh init bash)"
EOF
      fi
      ok "Oh My Posh activado en ~/.bashrc; abre una terminal nueva para verlo"
    fi
  else
    warn "La instalación de Oh My Posh no dejó el binario disponible."
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  warn "Docker no está instalado. Se crean las carpetas, pero se omite la sección Docker."
  exit 0
fi

docker_cmd=(docker)
if ! docker info >/dev/null 2>&1; then
  if sudo docker info >/dev/null 2>&1; then
    docker_cmd=(sudo docker)
    warn "Tu sesión todavía no tiene activo el grupo docker; usaré sudo en esta ejecución."
  else
    warn "No puedo acceder al daemon Docker."
    exit 0
  fi
fi

log "Red Docker compartida"
if ! "${docker_cmd[@]}" network inspect dev-network >/dev/null 2>&1; then
  "${docker_cmd[@]}" network create dev-network
fi

printf "\n${CYAN}Imágenes Docker para desarrollo local${RESET}\n"
printf "MySQL viene seleccionado por defecto; el resto no.\n\n"

mysql=0 postgres=0 redis=0 mailpit=0
mysql_tag="" postgres_tag="" redis_tag="" mailpit_tag=""

if ask_yes_no "¿Preparar MySQL?" y; then
  mysql=1
  mysql_tag="$(ask_tag mysql)"
fi
if ask_yes_no "¿Preparar PostgreSQL?" n; then
  postgres=1
  postgres_tag="$(ask_tag postgres)"
fi
if ask_yes_no "¿Preparar Redis?" n; then
  redis=1
  redis_tag="$(ask_tag redis)"
fi
if ask_yes_no "¿Preparar Mailpit?" n; then
  mailpit=1
  mailpit_tag="$(ask_tag axllent/mailpit)"
fi

custom_images=()
while ask_yes_no "¿Hacer pull de otra imagen personalizada?" n; do
  read -r -p "Imagen completa (ej. nginx:latest): " custom
  [[ -n "${custom:-}" ]] && custom_images+=("$custom")
done

selected_count=$((mysql + postgres + redis + mailpit))

if (( mysql )); then "${docker_cmd[@]}" pull "mysql:$mysql_tag"; fi
if (( postgres )); then "${docker_cmd[@]}" pull "postgres:$postgres_tag"; fi
if (( redis )); then "${docker_cmd[@]}" pull "redis:$redis_tag"; fi
if (( mailpit )); then "${docker_cmd[@]}" pull "axllent/mailpit:$mailpit_tag"; fi
for image in "${custom_images[@]}"; do "${docker_cmd[@]}" pull "$image"; done

if (( selected_count == 0 )); then
  warn "No se seleccionó ningún servicio gestionado. No modificaré compose.yaml."
else
  log "Generando compose.yaml solo con los servicios seleccionados"

  {
    echo "name: dev-infrastructure"
    echo
    echo "services:"

    if (( mysql )); then
      cat <<EOF
  mysql:
    image: mysql:$mysql_tag
    container_name: mysql-dev
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD}
    ports:
      - "127.0.0.1:3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - dev-network

EOF
    fi

    if (( postgres )); then
      cat <<EOF
  postgres:
    image: postgres:$postgres_tag
    container_name: postgres-dev
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - dev-network

EOF
    fi

    if (( redis )); then
      cat <<EOF
  redis:
    image: redis:$redis_tag
    container_name: redis-dev
    restart: unless-stopped
    ports:
      - "127.0.0.1:6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - dev-network

EOF
    fi

    if (( mailpit )); then
      cat <<EOF
  mailpit:
    image: axllent/mailpit:$mailpit_tag
    container_name: mailpit-dev
    restart: unless-stopped
    ports:
      - "127.0.0.1:8025:8025"
      - "127.0.0.1:1025:1025"
    networks:
      - dev-network

EOF
    fi

    if (( mysql || postgres || redis )); then
      echo "volumes:"
      (( mysql )) && echo "  mysql_data:"
      (( postgres )) && echo "  postgres_data:"
      (( redis )) && echo "  redis_data:"
    else
      echo "volumes: {}"
    fi
    echo
    cat <<'EOF'
networks:
  dev-network:
    external: true
EOF
  } >"$INFRA_DIR/compose.yaml"

  touch "$INFRA_DIR/.env"
  chmod 600 "$INFRA_DIR/.env"

  if (( mysql )) && ! grep -q '^MYSQL_ROOT_PASSWORD=' "$INFRA_DIR/.env"; then
    printf 'MYSQL_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 18)" >>"$INFRA_DIR/.env"
  fi
  if (( postgres )); then
    grep -q '^POSTGRES_USER=' "$INFRA_DIR/.env" || echo 'POSTGRES_USER=dev' >>"$INFRA_DIR/.env"
    grep -q '^POSTGRES_PASSWORD=' "$INFRA_DIR/.env" || printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 18)" >>"$INFRA_DIR/.env"
  fi

  printf '.env\n' >"$INFRA_DIR/.gitignore"

  ok "compose.yaml generado en $INFRA_DIR"
fi

printf "\n${GREEN}Post-install completado.${RESET}\n"
printf "Proyectos:      %s\n" "$PROJECTS_DIR"
printf "Infraestructura: %s\n" "$INFRA_DIR"
if (( selected_count > 0 )); then
  printf "\nPara arrancar lo seleccionado:\n  cd \"%s\" && docker compose up -d\n" "$INFRA_DIR"
fi
