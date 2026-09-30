#!/usr/bin/env bash
set -Eeuo pipefail

# Local development layout and shared Docker infrastructure.

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }

DEV_ROOT="${DEV_ROOT:-$HOME/dev}"
INFRA_DIR="$DEV_ROOT/infrastructure"
PROJECTS_DIR="$DEV_ROOT/projects"

mkdir -p "$INFRA_DIR" "$PROJECTS_DIR"

log "Creating shared Docker network"
if command -v docker >/dev/null 2>&1; then
  if ! docker network inspect dev-network >/dev/null 2>&1; then
    docker network create dev-network
  fi
else
  warn "Docker is not available in this shell yet. Log out/in and rerun this script."
fi

log "Writing shared infrastructure compose.yaml"
cat >"$INFRA_DIR/compose.yaml" <<'EOF'
name: dev-infrastructure

services:
  mysql:
    image: mysql:8.4
    container_name: mysql-dev
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    ports:
      - "127.0.0.1:3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - dev-network

  postgres:
    image: postgres:17
    container_name: postgres-dev
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - dev-network

  redis:
    image: redis:7-alpine
    container_name: redis-dev
    restart: unless-stopped
    ports:
      - "127.0.0.1:6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - dev-network

  mailpit:
    image: axllent/mailpit:latest
    container_name: mailpit-dev
    restart: unless-stopped
    ports:
      - "127.0.0.1:8025:8025"
      - "127.0.0.1:1025:1025"
    networks:
      - dev-network

volumes:
  mysql_data:
  postgres_data:
  redis_data:

networks:
  dev-network:
    external: true
EOF

if [[ ! -f "$INFRA_DIR/.env" ]]; then
  # Local-development credentials only. This file is gitignored.
  MYSQL_PASS="$(openssl rand -hex 18)"
  POSTGRES_PASS="$(openssl rand -hex 18)"
  cat >"$INFRA_DIR/.env" <<EOF
MYSQL_ROOT_PASSWORD=$MYSQL_PASS
POSTGRES_USER=dev
POSTGRES_PASSWORD=$POSTGRES_PASS
EOF
  chmod 600 "$INFRA_DIR/.env"
fi

cat >"$INFRA_DIR/.env.example" <<'EOF'
MYSQL_ROOT_PASSWORD=change-me
POSTGRES_USER=dev
POSTGRES_PASSWORD=change-me
EOF

cat >"$INFRA_DIR/.gitignore" <<'EOF'
.env
EOF

cat >"$INFRA_DIR/README.md" <<'EOF'
# Shared local development infrastructure

Start:

```bash
docker compose up -d
```

Stop containers:

```bash
docker compose stop
```

Remove containers but keep volumes:

```bash
docker compose down
```

The external Docker network is `dev-network`.

Applications running in Docker and attached to `dev-network` can use:

- `mysql-dev:3306`
- `postgres-dev:5432`
- `redis-dev:6379`
- `mailpit-dev:1025`

Applications running directly on Ubuntu can use `127.0.0.1` and the published ports.

This infrastructure is for local development only. Production databases should be deployed independently per project.
EOF

log "Git defaults"
git config --global init.defaultBranch main
git config --global pull.ff only
git config --global fetch.prune true

if [[ -z "$(git config --global user.name || true)" ]]; then
  warn "Git user.name is not configured."
  echo "Run: git config --global user.name \"Your Name\""
fi
if [[ -z "$(git config --global user.email || true)" ]]; then
  warn "Git user.email is not configured."
  echo "Run: git config --global user.email \"you@example.com\""
fi

log "SSH"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
  warn "No ~/.ssh/id_ed25519 found. It was NOT generated automatically."
  echo "Create one when ready with:"
  echo '  ssh-keygen -t ed25519 -C "your-email@example.com"'
else
  ok "Existing Ed25519 SSH key found"
fi

ok "Created:"
echo "  $INFRA_DIR"
echo "  $PROJECTS_DIR"
echo
echo "To start local databases/services:"
echo "  cd \"$INFRA_DIR\" && docker compose up -d"
