# Ubuntu 26.04 developer bootstrap

A small reinstall kit for a development laptop.

## Order

```bash
chmod +x *.sh

./bootstrap.sh
# Reboot/log out-in if requested.

./dev-tools.sh
./post-install.sh
./check.sh
```

## 1. bootstrap.sh

Installs:

- Ubuntu updates and base CLI packages
- OpenSSH
- recommended NVIDIA driver when an NVIDIA GPU is detected
- Docker Engine + Compose + Buildx from Docker's official repository
- VirtualBox
- Guest Additions ISO package when Ubuntu provides it
- required user groups (`docker`, `vboxusers`)

Options:

```bash
./bootstrap.sh --skip-nvidia
./bootstrap.sh --skip-docker
./bootstrap.sh --skip-virtualbox
```

### Windows Guest Additions

Guest Additions are installed **inside Windows**, not on the Ubuntu host:

1. Start the Windows VM.
2. VirtualBox → **Devices → Insert Guest Additions CD image…**
3. In Windows, open the virtual CD.
4. Run `VBoxWindowsAdditions.exe`.
5. Reboot Windows.

## 2. dev-tools.sh

Installs/configures:

- NVM + current Node LTS
- SDKMAN! + Java 21 Temurin
- uv
- VS Code from Microsoft's repository
- Brave from Brave's repository
- Flutter bootstrap SDK + FVM + stable Flutter
- Android Studio system dependencies
- Android Studio if its official `android-studio-*-linux.tar.gz` is in `~/Downloads` or `~/Descargas`
- JetBrains Toolbox if its official `jetbrains-toolbox-*.tar.gz` is in the same folder

Options:

```bash
./dev-tools.sh --no-brave
./dev-tools.sh --no-flutter
./dev-tools.sh --no-android-studio
./dev-tools.sh --no-jetbrains-toolbox
```

### Why there is a Flutter bootstrap SDK

FVM itself is a Dart application. The bootstrap Flutter SDK supplies Dart so FVM can run. Actual projects should select their Flutter version with:

```bash
cd project
fvm use <version>
fvm flutter doctor
```

## 3. post-install.sh

Creates:

```text
~/dev/
├── infrastructure/
└── projects/
```

The shared **local-only** infrastructure contains:

- MySQL 8.4
- PostgreSQL 17
- Redis 7
- Mailpit

It creates the external Docker network `dev-network`.

Start it with:

```bash
cd ~/dev/infrastructure
docker compose up -d
```

Projects running in Docker should join `dev-network` and connect to:

```text
mysql-dev:3306
postgres-dev:5432
redis-dev:6379
mailpit-dev:1025
```

Production infrastructure is intentionally separate.

## 4. check.sh

Read-only audit of the workstation:

```bash
./check.sh
```

It reports the state of Docker, VirtualBox, NVIDIA, NVM/Node, SDKMAN/Java, uv, FVM/Flutter, VS Code, Brave, Android Studio, ADB and the local development infrastructure.

## Secrets

This repository intentionally does **not** contain:

- SSH private keys
- GitHub tokens
- production `.env` files
- certificates
- database production passwords

`post-install.sh` generates random **local-development-only** database passwords in `~/dev/infrastructure/.env` and creates a `.gitignore` for it.

## PHP

PHP is intentionally not installed globally. Each PHP project should select its runtime in Docker, for example:

```dockerfile
FROM php:8.2-fpm
```

or:

```dockerfile
FROM php:8.5-fpm
```

Composer can likewise run in the application's PHP container or through the official Composer image.

## Node

Node is installed locally through NVM for CLIs, scripts and non-Docker projects. Dockerized applications keep their own Node version, e.g. Game Shelf can continue using `node:20`.

## Android Studio

After the tarball is installed, Android Studio's first-run wizard should install the Android SDK, Platform Tools, Command-line Tools and Emulator. Then run:

```bash
fvm flutter doctor
fvm flutter doctor --android-licenses
```

VirtualBox and Android Emulator should not run hardware-virtualized workloads at the same time if the host becomes resource constrained.
