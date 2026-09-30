# Ubuntu Developer Center

Kit interactivo para reconstruir una estación de desarrollo Ubuntu 26.04.

## Inicio rápido

```bash
git clone https://github.com/eliseumarmon/ubuntu-bootstrap.git
cd ubuntu-bootstrap
chmod +x *.sh
./install.sh
```

`install.sh` es el centro de inicio y permite lanzar cada fase por separado.

## Scripts

### `install.sh`

Menú maestro:

1. `bootstrap.sh` — sistema base, NVIDIA, Docker, Tailscale y VirtualBox.
2. `dev-tools.sh` — herramientas, runtimes, IDEs y navegador.
3. `post-install.sh` — Git/SSH, estructura `~/dev` e imágenes Docker.
4. `check.sh` — auditoría sin modificar el sistema.

### `bootstrap.sh`

Instala y configura:

- actualizaciones de Ubuntu
- OpenSSH
- driver NVIDIA recomendado si detecta NVIDIA
- Docker Engine + Compose + Buildx
- pregunta si quieres añadir tu usuario al grupo `docker` para ejecutar Docker sin `sudo`
- Tailscale
  - usa el instalador oficial de Tailscale
  - habilita `tailscaled`
  - pregunta si quieres ejecutar `sudo tailscale up` para autenticar el equipo
  - puede omitirse con `--skip-tailscale`
- VirtualBox
- Guest Additions ISO cuando Ubuntu la ofrece

Guest Additions se instala dentro de la VM Windows desde:

`VirtualBox → Devices → Insert Guest Additions CD image…`

### `dev-tools.sh`

Tiene selectores interactivos por secciones.

**Herramientas base**

- Git
- NVM + Node LTS
- SDKMAN! + Java 21 Temurin
- uv

**Móvil**

- Flutter + FVM
- Android Studio
  - si ya existe el `.tar.gz` en `~/Downloads` o `~/Descargas`, lo reutiliza
  - si no existe, descarga con `curl` la página oficial de Android Studio
  - localiza el nodo Linux mediante `agree_studio_linux_bundle_download`
  - muestra la licencia extraída del propio HTML descargado
  - pide aceptación explícita en terminal
  - marca `checked="checked"` únicamente en la copia HTML temporal
  - extrae del mismo diálogo el enlace `edgedl.me.gvt1.com/...-linux.tar.gz`
  - descarga el archivo automáticamente con `curl -fL`

**IDEs y navegador**

- VS Code
- IntelliJ IDEA
- Brave

Para estas tres aplicaciones se puede elegir el método:

| Aplicación | Método 1 | Método 2 |
|---|---|---|
| VS Code | repositorio APT oficial de Microsoft | Snap |
| IntelliJ IDEA | JetBrains Toolbox | Snap |
| Brave | repositorio APT oficial de Brave | Snap |

Los nombres de los snaps son:

```bash
sudo snap install code --classic
sudo snap install intellij-idea --classic
sudo snap install brave
```

### `post-install.sh`

Crea:

```text
~/dev/
├── infrastructure/
└── projects/
```

Configura valores Git, revisa/genera opcionalmente una clave SSH y ofrece un flujo de personalización de terminal:

- instala/actualiza Oh My Posh mediante su instalador oficial
- instala opcionalmente `0xProto Nerd Font`
- puede activar Oh My Posh automáticamente en Bash mediante `~/.bashrc`

Después pregunta qué infraestructura Docker quieres preparar.

Valores iniciales del selector:

```text
[x] MySQL
[ ] PostgreSQL
[ ] Redis
[ ] Mailpit
```

Cada imagen pregunta por el tag y usa `latest` si pulsas Enter.

Ejemplo:

```text
¿Preparar MySQL? [Y/n]
Tag para mysql [latest]:
```

Entonces se hace:

```bash
docker pull mysql:latest
```

y `compose.yaml` contiene únicamente los servicios elegidos. También se pueden añadir imágenes personalizadas solo para hacer `docker pull`.

La infraestructura es exclusivamente local. Producción sigue aislada por proyecto.

### `check.sh`

Comprueba:

- Git y SSH
- Tailscale y estado de conexión
- Docker y Compose
- VirtualBox
- NVIDIA
- NVM / Node
- SDKMAN / Java
- uv
- Oh My Posh
- 0xProto Nerd Font
- FVM
- VS Code
- IntelliJ IDEA / Toolbox
- Brave
- Android Studio / ADB
- infraestructura e imágenes Docker locales

## Arquitectura de runtimes

```text
Host
├── Node → NVM
├── Java → SDKMAN!
├── Python → uv
├── Flutter → FVM
└── Docker
    ├── PHP por proyecto
    ├── Node por proyecto cuando esté dockerizado
    └── infraestructura local seleccionada
```

PHP no se instala globalmente. Cada proyecto fija su runtime:

```dockerfile
FROM php:8.2-fpm
```

o:

```dockerfile
FROM php:8.5-fpm
```

Los proyectos Node dockerizados también fijan su propia versión, por ejemplo `node:20`.

## Secretos

El repositorio no debe contener:

- claves SSH privadas
- tokens
- certificados
- `.env` de producción
- contraseñas de producción

`post-install.sh` genera contraseñas aleatorias únicamente para la infraestructura local y guarda `.env` con permisos `600`.


## Android Studio y curl

La licencia **no está copiada en el repositorio**. En cada instalación se obtiene de la página oficial actual:

```text
developer.android.com/studio
        │
        ▼
curl descarga el HTML
        │
        ▼
busca #agree_studio_linux_bundle_download
        │
        ├── extrae y muestra .sdk-terms
        │
        ▼
usuario acepta en terminal
        │
        ▼
checked="checked" en la copia temporal
        │
        ▼
grep extrae el enlace Linux del mismo diálogo
        │
        ▼
curl descarga android-studio-...-linux.tar.gz
```

El patrón de descarga está limitado al CDN oficial esperado:

```text
https://edgedl.me.gvt1.com/android/studio/ide-zips/.../android-studio-...-linux.tar.gz
```

La modificación del atributo `checked` ocurre solo en un archivo temporal local y representa la aceptación hecha por el usuario en terminal; no modifica ni envía el HTML de Google.
