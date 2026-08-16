# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Descripción del proyecto

Automatización para **provisionar desde cero** un servidor Odoo del proyecto Maralva: instala dependencias de sistema y PostgreSQL, clona el core OCB + repos OCA + el repo de addons custom (`maralva-custom`), crea el venv, genera `odoo.conf` y el servicio systemd, y configura Nginx como proxy. No contiene módulos Odoo; es infraestructura/shell scripting puro.

## Entorno técnico

- Scripts Bash pensados para ejecutarse **con `sudo` en el propio servidor Linux** (Ubuntu/Debian) que va a alojar Odoo, no en este checkout de Windows.
- Estructura que se crea en el servidor: `/opt/odoo/<branch_domain>/{odoo (core OCB), oca/<repo>, gdigital-custom (= repo maralva-custom), venv}`, config en `/etc/odoo/<service_name>.conf`, logs en `/var/log/odoo/`.
- **Addons-path generado**: `<core>/addons,<oca>,<gdigital-custom>` (las tres rutas raíz; Odoo escanea subcarpetas).
- Servicio: `odoo<branch_clean>` (ej. `odoo180` para la rama `18.0`) vía systemd, con `workers = 5`, `proxy_mode = True`, `unaccent = True`.

## Convenciones del proyecto

- **Organización GitHub de forks**: se pide de forma interactiva (`ORGANIZACION`); en la práctica es `MaralvaEU`.
- **Rama de trabajo de este repo**: `master` (única rama; el repo aún no diferencia por versión de Odoo).
- **Rama de Odoo/OCA a desplegar**: se pide de forma interactiva (`18.0`, `19.0`, ...) y determina `SERVICE_NAME`, rutas y `addons_path`.
- **`scripts/01-prep-db-multi.sh`, `02-odoo-setup-multi.sh`, `03-setup-nginx-multi.sh`** (sufijo `-multi`): variante pensada para **multi-instancia** — varias versiones/instancias de Odoo conviviendo en el mismo servidor (una por rama, cada una con su propio puerto/servicio/vhost). Está previsto crear, a partir de estas, una variante de instalación única por versión en ramas específicas del repo (por ahora solo existe `master`); mientras eso no exista, `master_install.sh` sigue siendo un único script que orquesta las tres fases `-multi`.
- **Listas de configuración en `config/`**:
  - `reposoca.txt` — nombres de repos OCA a clonar (uno por línea).
  - `requirements_standard.txt` / `third_parties.txt` — dependencias pip adicionales a las de `requirements.txt` del core.
  - `pack_maralva_base18.txt` / `pack_maralva_base19.txt` — lista de módulos `depends` para que `scripts/pack-maker.sh` scaffoldee un nuevo módulo maestro por versión de Odoo.

⚠️ **Inconsistencia conocida**: `scripts/02-odoo-setup-multi.sh` y `scripts/pack-maker.sh` clonan el repo de addons custom como `gdigital-custom` desde `git@github.com:SOLDIGES/gdigital-custom.git` — un nombre de org/repo antiguo. El repo real actual es `git@github.com:MaralvaEU/maralva-custom.git`. Si actualizas estos scripts, decide si conviene alinear también el nombre de carpeta/remoto.

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
```

## Notas para Claude Code

- Este repo se trabaja **solo desde VS Code + extensión Claude Code** (edición, instalación, pruebas, ejecución de Odoo, revisión de diffs).
- Cowork (Claude en la app de escritorio) se usa aparte para seguimiento y documentación del proyecto, sin tocar este entorno técnico — ver `ESTADO.md` para la bitácora que Cowork puede consultar.
- Al final de cada sesión de trabajo, actualizar `ESTADO.md` con un resumen de lo hecho (pedir a Claude Code: "resume lo que hicimos hoy en ESTADO.md").
