# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Descripción del proyecto

Automatización para **provisionar desde cero** un servidor Odoo del proyecto Maralva: instala dependencias de sistema y PostgreSQL, clona el core OCB + repos OCA + el repo de addons custom (`maralva-custom`), crea el venv, genera `odoo.conf` y el servicio systemd, y configura Nginx como proxy. No contiene módulos Odoo; es infraestructura/shell scripting puro.

**Esta rama (`19.0`) es la variante de instalación única**: un solo Odoo, una sola versión, en toda la máquina — nunca convive con otra versión en el mismo servidor (a diferencia de la rama `master`, que mantiene los scripts `-multi` para desarrollo/pruebas con varias versiones a la vez). Por eso aquí las rutas y nombres **no llevan sufijo de versión**: `/opt/odoo` (no `/opt/odoo/19`), `odoo.conf`/`odoo.log` (no `odoo190.conf`), servicio `odoo` (no `odoo190`). La rama de Odoo/OCA a usar **no se pregunta**: los scripts de mantenimiento (`update_oca_upstream.sh`, `update_databases.sh`, `push_org_origin.sh`, `update_org_origin.sh`) la detectan automáticamente con `git -C /opt/odoo/odoo rev-parse --abbrev-ref HEAD`.

## Entorno técnico

- Scripts Bash pensados para ejecutarse **con `sudo` en el propio servidor Linux** (Ubuntu/Debian) que va a alojar Odoo, no en este checkout de Windows.
- Estructura que se crea en el servidor: `/opt/odoo/{odoo (core OCB), oca/<repo>, openupgradelib, maralva-custom, venv}`, config en `/etc/odoo/odoo.conf`, logs en `/var/log/odoo/`.
- **Addons-path generado**: `<core>/addons,<oca>,<maralva-custom>` (las tres rutas raíz; Odoo escanea subcarpetas).
- Servicio: `odoo` vía systemd, con `workers = 5`, `proxy_mode = True`, `unaccent = True`.
- **`dbfilter = ^%d.*$`** (prefijo, no coincidencia exacta) — a propósito, para multi-cliente por dominio: Odoo sustituye `%d` por "lo que hay antes del primer punto del hostname", así que `maralva.eu` → prefijo `maralva` (muestra `maralva_real`, `maralva_pruebas`, etc.) y `proasur.maralva.eu` → prefijo `proasur`, sin necesitar subdominio propio para la marca principal.
- **PostgreSQL — acceso remoto**: `pg_hba.conf` solo admite conexiones TCP con contraseña (`scram-sha-256`) desde las dos redes de confianza de Maralva: `192.168.1.0/24` (conexión directa) y `192.168.100.0/24` (VPN). Pensado para herramientas como pgAdmin; Odoo conecta en local por socket Unix y no depende de esta regla.
- **`odoo.conf` — decisiones deliberadas, no las "corrijas" sin preguntar**:
  - `admin_passwd` se deja **sin definir a propósito**: el máster password se fija/gestiona desde el propio asistente "Crear base de datos" de Odoo la primera vez, no en este archivo.
  - `list_db` se deja en su valor por defecto (`True`, es decir, no se añade `list_db = False`): cada instancia aloja varias bases (Real, pruebas, formación) y hace falta poder listarlas para mantenimiento.
  - `db_password` sigue siendo `odoo` (contraseña del rol de PostgreSQL `odoo`, no confundir con `admin_passwd` ni con el login de un usuario Odoo). Ahora sí se exige de verdad para conexiones remotas por TCP (antes pg_hba usaba `trust`, sin contraseña); pendiente de decidir si se refuerza.

## Convenciones del proyecto

- **Organización GitHub de forks**: se pide de forma interactiva (`ORGANIZACION`); en la práctica es `MaralvaEU`.
- **Rama de trabajo de este repo**: `19.0` (instalación única para Odoo 19.0; creada a partir de `master`, que sigue manteniendo la variante `-multi` para desarrollo/pruebas). Existe también (o existirá) una rama equivalente `18.0`.
- **`01-prep-db.sh` — apt no interactivo**: todas las llamadas a `apt`/`apt-get` van precedidas de `sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a` (variable `$APT_ENV` en el script) para que `needrestart` no abra un diálogo interactivo preguntando qué servicios reiniciar — eso bloquearía el script indefinidamente. También arranca con `apt update && apt upgrade -y` antes de instalar nada.
- **`01-prep-db.sh` — wkhtmltopdf**: se instala la build con Qt parcheado de [wkhtmltopdf.org/downloads.html](https://wkhtmltopdf.org/downloads.html) (recomendada por Odoo para informes PDF), no el paquete `wkhtmltopdf` de los repos de Ubuntu. No hay build oficial para Ubuntu 24.04 (noble): se usa la más reciente publicada, `wkhtmltox_0.12.6.1-2.jammy_amd64.deb` — jammy ya usa OpenSSL 3 como noble, así que no arrastra el problema de `libssl1.1` obsoleto de las builds focal/bionic. Instalación no interactiva: `wget` + `dpkg -i`, con `apt-get install -f -y` como fallback si dpkg se queja de dependencias (`fontconfig`, `xfonts-75dpi`, `xfonts-base`) — verificado en servidor real. No depende de la versión de Odoo, así que el mismo bloque vive igual en `18.0`, `19.0` y `01-prep-db-multi.sh` de `master`.
- **`02-odoo-setup.sh` — clonado resiliente de OCB/OCA**: para cada repo (OCB incluido), intenta primero el fork en `$ORGANIZACION`; si no existe, clona de OCA y **crea el fork automáticamente** con `gh repo fork ... --org "$ORGANIZACION" --clone=false` (requiere `gh` instalado y autenticado — `gh auth login` funciona sin entorno gráfico, por código de un solo uso; si `gh` no está disponible, el script avisa y sigue, dejando el fork por crear a mano). Si un repo de `reposoca.txt` ni siquiera tiene la rama pedida en OCA todavía, se **omite con aviso** y la instalación continúa con el resto. Al final imprime la lista de repos omitidos.
- **Gotcha real de sesión — grupo `odoo` no activo**: si ya lanzaste `master_install.sh` una vez en un servidor (lo que te añade al grupo `odoo` vía `usermod`) y vuelves a lanzarlo **en la misma sesión SSH**, tu shell sigue con el grupo antiguo activo aunque el sistema ya te tenga añadido — el script comprueba la pertenencia con `id -nG "$REAL_USER"` (mira la cuenta, no la sesión activa), así que no detecta el problema y no vuelve a forzar el `sg odoo`. Síntoma: `git clone` falla con `Permission denied` al crear `/opt/odoo/...` aunque los directorios y permisos parezcan correctos. Solución: cerrar sesión SSH y volver a entrar antes de relanzar el script.
- **`02-odoo-setup.sh` — caso especial `openupgradelib`**: **no es un módulo de Odoo** (no tiene `__manifest__.py`), es una librería Python normal (`from openupgradelib import openupgrade`), y no depende de la versión de Odoo (solo tiene rama `master`). Por eso NO vive en `oca/` ni en `reposoca.txt` (rompería con `--branch $BRANCH`, y además Odoo no la cargaría como addon aunque estuviera ahí): se clona en `/opt/odoo/openupgradelib` (mismo patrón fork→OCA→autofork que el resto, pero con `master` fijo), y el venv la instala en modo editable (`pip install -e /opt/odoo/openupgradelib`) en la sección de dependencias Python.
- **`scripts/04-enable-ssl.sh`**: paso **manual y aparte**, no invocado por `master_install.sh`. Activa HTTPS sobre el vhost ya creado por `03-setup-nginx.sh`, comprobando antes que ya existe certificado válido (emitido con `maralva-ops/certs/setup-ssl-duckdns.sh` para `$DOMAIN`) — si no lo encuentra, avisa y no toca nginx. Genera dos bloques HTTPS (uno para `$DOMAIN`, otro para `*.$DOMAIN`), cada uno con su propio certificado (apex/wildcard — ver `maralva-ops/certs/`), más una redirección 80→443. Deliberadamente separado del resto de fases porque certificar no siempre es necesario ni posible.
- **`03-setup-nginx.sh`**: un único vhost HTTP con `server_name $DOMAIN *.$DOMAIN;` — cualquier subdominio nuevo (un cliente = un subdominio) funciona solo dando de alta el DNS, sin tocar nginx.
- **`scripts/setup_logrotate.sh`**: usa `copytruncate` (no `postrotate`) — motivo: Odoo no soporta reabrir su log por señal como nginx/apache. Necesita mantener `su odoo odoo`: sin esa directiva, logrotate se salta el fichero porque `/var/log/odoo` es escribible por el grupo `odoo` (770), no por `root`. `create` no hace falta (no se usa con `copytruncate`).
- **Flujo de actualización desde OCA** (4 scripts, se lanzan manualmente uno por uno, en desarrollo o copia de la máquina de producción — nunca directo en producción; todos detectan la rama solos, no la preguntan):
  1. `scripts/update_oca_upstream.sh` — trae cambios de `upstream` (OCA) a cada repo (core incluido) y genera `config/actualizaciones/modulos_<rama>_<fecha>.txt` con los módulos de verdad cambiados (por repo, filtrando por presencia de `__manifest__.py`/`__openerp__.py`; el core se excluye del listado por demasiado ruido, pero sí se actualiza). Los módulos que no existían antes del `reset` (nuevos en OCA) se marcan con `[NUEVO]` al final de la línea.
  2. `scripts/update_databases.sh` — muestra el último fichero de módulos como referencia (para saber qué probar después), pide confirmación de que hay backup de las BDs, detecta las bases de datos existentes y pregunta sobre cuáles actuar; para el servicio y ejecuta `odoo-bin -u all -d <bd>` por cada una (como usuario `odoo`), reiniciándolo al terminar. Usa `-u all` (no la lista de módulos del fichero) **a propósito**: esa lista solo cubre repos de `reposoca.txt`, y el core (OCB) queda fuera de ella — si el core cambió algo que necesita migración de esquema, un `-u` limitado a módulos OCA no lo aplicaría, dejando la BD con un esquema desincronizado (confirmado en real en la variante `-multi`: error de Postgres tras actualizar solo con la lista OCA).
  3. Si las pruebas salen bien → `scripts/push_org_origin.sh` — pide confirmar snapshot **y** que las BDs se actualizaron correctamente, luego sube cada repo a tu fork con `git push --force-with-lease` (no un push normal): `update_oca_upstream.sh` pudo haber descartado commits que tu fork todavía tiene (por el `reset --hard` a upstream), así que un push normal (fast-forward) fallaría con "non-fast-forward". `--force-with-lease` reescribe el fork para que quede igual que la copia local, pero aborta si alguien más lo ha tocado entre medias (a diferencia de `--force` a secas).
     - **Bloqueo de integridad**: antes de subir cada repo, compara el HEAD local contra `upstream/$BRANCH`; si hay commits locales que OCA no tiene, **no sube ese repo** (los demás siguen normal) y avisa — los repos de OCA deben ser espejos limpios, cualquier código propio va en `maralva-custom`, no editado a mano dentro de `oca/`.
  4. Si las pruebas fallan → `scripts/update_org_origin.sh` — descarta lo traído de OCA y vuelve a `origin/$BRANCH` en cada repo (rollback de código; las bases de datos hay que restaurarlas aparte, desde el backup).
- **Listas de configuración en `config/`**:
  - `reposoca.txt` — nombres de repos OCA a clonar (uno por línea).
  - `requirements_standard.txt` / `third_parties.txt` — dependencias pip adicionales a las de `requirements.txt` del core.
  - `pack_maralva_base.txt` — lista de módulos `depends` del pack maestro de esta versión (en `master` hay uno por versión, `pack_maralva_base18.txt`/`pack_maralva_base19.txt`; aquí solo el de la `19.0`). `scripts/pack-maker.sh` (el scaffolder que los consume) no está en esta rama — es una herramienta de desarrollo, se dejó fuera a propósito.
  - `actualizaciones/` — generada por `scripts/update_oca_upstream.sh` en cada servidor (ignorada por git, ver `.gitignore`); no forma parte del repo compartido.

## Prerrequisito manual en un servidor recién instalado

Un Ubuntu Server recién instalado (mínimo, solo con OpenSSH) **no trae `git`**. `01-prep-db.sh` sí instala `git` por `apt`, pero ese script vive dentro de este mismo repo — hace falta `git` para poder clonarlo la primera vez. Por tanto, antes de clonar `maralva-deploy` en un servidor nuevo:

```bash
sudo apt update && sudo apt install -y git
```

Después de esto ya se puede clonar este repo y lanzar `master_install.sh` con normalidad.

## Comandos habituales

No hay tests ni linter (son scripts Bash de infraestructura). Flujo típico en el servidor:

```bash
# Instalación completa interactiva (fases 1-3: DB/sistema, Odoo+OCA+venv, Nginx)
sudo ./master_install.sh

# Sincronizar los forks OCA/OCB locales con upstream OCA (pide confirmación de snapshot)
sudo ./scripts/update_oca_upstream.sh

# Aplicar a las BDs los módulos que trajo update_oca_upstream.sh
sudo ./scripts/update_databases.sh

# Si las pruebas fueron bien: subir cambios locales a tus forks en GitHub
sudo ./scripts/push_org_origin.sh

# Si las pruebas fallaron: descartar y volver a lo que había en tu fork
sudo ./scripts/update_org_origin.sh

# Configurar logrotate para los logs de Odoo
sudo ./scripts/setup_logrotate.sh

# Activar HTTPS (requiere certificado ya emitido con maralva-ops/certs/setup-ssl-duckdns.sh)
sudo ./scripts/04-enable-ssl.sh
```

## Notas para Claude Code

- Este repo se trabaja **solo desde VS Code + extensión Claude Code** (edición, instalación, pruebas, ejecución de Odoo, revisión de diffs).
- Cowork (Claude en la app de escritorio) se usa aparte para seguimiento y documentación del proyecto, sin tocar este entorno técnico — ver `ESTADO.md` para la bitácora que Cowork puede consultar.
- Al final de cada sesión de trabajo, actualizar `ESTADO.md` con un resumen de lo hecho (pedir a Claude Code: "resume lo que hicimos hoy en ESTADO.md").
