# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Descripción del proyecto

Automatización para **provisionar desde cero** un servidor Odoo del proyecto Maralva: instala dependencias de sistema y PostgreSQL, clona el core OCB + repos OCA + el repo de addons custom (`maralva-custom`), crea el venv, genera `odoo.conf` y el servicio systemd, y configura Nginx como proxy. No contiene módulos Odoo; es infraestructura/shell scripting puro.

## Entorno técnico

- Scripts Bash pensados para ejecutarse **con `sudo` en el propio servidor Linux** (Ubuntu/Debian) que va a alojar Odoo, no en este checkout de Windows.
- Estructura que se crea en el servidor: `/opt/odoo/<branch_domain>/{odoo (core OCB), oca/<repo>, maralva-custom, venv}`, config en `/etc/odoo/<service_name>.conf`, logs en `/var/log/odoo/`.
- **Addons-path generado**: `<core>/addons,<oca>,<maralva-custom>` (las tres rutas raíz; Odoo escanea subcarpetas).
- Servicio: `odoo<branch_clean>` (ej. `odoo180` para la rama `18.0`) vía systemd, con `workers = 5`, `proxy_mode = True`, `unaccent = True`.
- **PostgreSQL — acceso remoto**: `pg_hba.conf` solo admite conexiones TCP con contraseña (`scram-sha-256`) desde las dos redes de confianza de Maralva: `192.168.1.0/24` (conexión directa) y `192.168.100.0/24` (VPN). Pensado para herramientas como pgAdmin; Odoo conecta en local por socket Unix y no depende de esta regla.
- **`odoo.conf` — decisiones deliberadas, no las "corrijas" sin preguntar**:
  - `admin_passwd` se deja **sin definir a propósito**: el máster password se fija/gestiona desde el propio asistente "Crear base de datos" de Odoo la primera vez, no en este archivo.
  - `list_db` se deja en su valor por defecto (`True`, es decir, no se añade `list_db = False`): cada instancia aloja varias bases (Real, pruebas, formación) y hace falta poder listarlas para mantenimiento.
  - `db_password` sigue siendo `odoo` (contraseña del rol de PostgreSQL `odoo`, no confundir con `admin_passwd` ni con el login de un usuario Odoo). Ahora sí se exige de verdad para conexiones remotas por TCP (antes pg_hba usaba `trust`, sin contraseña); pendiente de decidir si se refuerza.

## Convenciones del proyecto

- **Organización GitHub de forks**: se pide de forma interactiva (`ORGANIZACION`); en la práctica es `MaralvaEU`.
- **Rama de trabajo de este repo**: `master` (única rama; el repo aún no diferencia por versión de Odoo).
- **Rama de Odoo/OCA a desplegar**: se pide de forma interactiva (`18.0`, `19.0`, ...) y determina `SERVICE_NAME`, rutas y `addons_path`.
- **`scripts/01-prep-db-multi.sh`, `02-odoo-setup-multi.sh`, `03-setup-nginx-multi.sh`** (sufijo `-multi`): variante pensada para **multi-instancia** — varias versiones/instancias de Odoo conviviendo en el mismo servidor (una por rama, cada una con su propio puerto/servicio/vhost). Está previsto crear, a partir de estas, una variante de instalación única por versión en ramas específicas del repo (por ahora solo existe `master`); mientras eso no exista, `master_install.sh` sigue siendo un único script que orquesta las tres fases `-multi`. `03-setup-nginx-multi.sh` genera **solo HTTP** (puerto 80) — no toca el certificado ni HTTPS.
- **`01-prep-db-multi.sh` — apt no interactivo**: todas las llamadas a `apt`/`apt-get` van precedidas de `sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a` (variable `$APT_ENV` en el script) para que `needrestart` no abra un diálogo interactivo preguntando qué servicios reiniciar — eso bloquearía el script indefinidamente. También arranca con `apt update && apt upgrade -y` antes de instalar nada, razonable en un servidor recién instalado (aunque no evita los diálogos de `needrestart` en sí — por eso hace falta el paso anterior de todas formas).
- **`02-odoo-setup-multi.sh` — clonado resiliente de OCB/OCA**: para cada repo (OCB incluido), intenta primero el fork en `$ORGANIZACION`; si no existe, clona de OCA y **crea el fork automáticamente** con `gh repo fork ... --org "$ORGANIZACION" --clone=false` (requiere `gh` instalado y autenticado — `gh auth login` funciona sin entorno gráfico, por código de un solo uso; si `gh` no está disponible, el script avisa y sigue, dejando el fork por crear a mano). Si un repo de `reposoca.txt` ni siquiera tiene la rama pedida en OCA todavía (típico en una versión de Odoo recién salida, ej. `19.0`), se **omite con aviso** y la instalación continúa con el resto — no aborta todo el proceso por un repo. Al final imprime la lista de repos omitidos; los módulos de `pack_maralva_base*.txt` que dependan de esos repos no estarán disponibles hasta que OCA migre esa rama.
- **`scripts/04-enable-ssl-multi.sh`**: paso **manual y aparte**, no invocado por `master_install.sh`. Activa HTTPS sobre un vhost ya creado por `03-setup-nginx-multi.sh`, comprobando antes que ya existe certificado válido (emitido con `maralva-ops/certs/setup-ssl-duckdns.sh` para el dominio `maralva<rama>.<dominio>`) — si no lo encuentra, avisa y no toca nginx. Deliberadamente separado del resto de fases porque certificar no siempre es necesario ni posible para toda instancia (p. ej. una instancia de desarrollo puro sin dominio público). El mismo patrón (comprobar certificado → regenerar vhost con HTTPS + redirect 80→443) se reutilizará cuando exista la variante de instalación única.
- **`scripts/setup_logrotate.sh`**: usa `copytruncate` (no `postrotate`/`create`) — motivo: Odoo no soporta reabrir su log por señal como nginx/apache, así que sin `copytruncate` la rotación no serviría de nada (el proceso seguiría escribiendo en el fichero viejo renombrado). La versión original tenía un bug real: el `postrotate` recargaba nginx en vez de avisar a Odoo de nada — quedó corregido usando `copytruncate`, que no necesita avisar al proceso.
- **Listas de configuración en `config/`**:
  - `reposoca.txt` — nombres de repos OCA a clonar (uno por línea).
  - `requirements_standard.txt` / `third_parties.txt` — dependencias pip adicionales a las de `requirements.txt` del core.
  - `pack_maralva_base18.txt` / `pack_maralva_base19.txt` — lista de módulos `depends` para que `scripts/pack-maker.sh` scaffoldee un nuevo módulo maestro por versión de Odoo.

✅ Resuelto: `scripts/02-odoo-setup-multi.sh` y `scripts/pack-maker.sh` ya clonan/usan `$ORGANIZACION/maralva-custom.git` (antes hardcodeaban `SOLDIGES/gdigital-custom`, un nombre de org/repo antiguo).

## Prerrequisito manual en un servidor recién instalado

Un Ubuntu Server recién instalado (mínimo, solo con OpenSSH) **no trae `git`**. `01-prep-db-multi.sh` sí instala `git` por `apt`, pero ese script vive dentro de este mismo repo — hace falta `git` para poder clonarlo la primera vez. Por tanto, antes de clonar `maralva-deploy` en un servidor nuevo:

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

# Subir cambios locales del servidor a tus forks en GitHub
sudo ./scripts/update_org_origin.sh

# Scaffoldear un nuevo módulo custom a partir de una lista de dependencias en config/
sudo ./scripts/pack-maker.sh

# Configurar logrotate para los logs de Odoo
sudo ./scripts/setup_logrotate.sh

# Activar HTTPS en una instancia -multi ya instalada (requiere certificado ya emitido)
sudo ./scripts/04-enable-ssl-multi.sh
```

## Notas para Claude Code

- Este repo se trabaja **solo desde VS Code + extensión Claude Code** (edición, instalación, pruebas, ejecución de Odoo, revisión de diffs).
- Cowork (Claude en la app de escritorio) se usa aparte para seguimiento y documentación del proyecto, sin tocar este entorno técnico — ver `ESTADO.md` para la bitácora que Cowork puede consultar.
- Al final de cada sesión de trabajo, actualizar `ESTADO.md` con un resumen de lo hecho (pedir a Claude Code: "resume lo que hicimos hoy en ESTADO.md").
