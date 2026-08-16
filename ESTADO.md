# ESTADO.md — Bitácora del proyecto

> Este archivo es la memoria compartida entre sesiones de trabajo. Claude Code (VS Code) lo actualiza al final de cada sesión técnica. Cowork lo puede leer después —conectando la carpeta del repo vía el puente de dispositivo— para generar informes de avance o revisar qué se hizo, sin ejecutar ni instalar nada.
>
> Convención: entradas en orden cronológico inverso (la más reciente arriba). No borrar histórico salvo limpieza puntual acordada.

## Módulos en curso

_(No aplica — este repo no contiene módulos Odoo, solo scripts de infraestructura.)_

## Pendientes / próximos pasos

1. **Commitear los arreglos ya hechos en el working tree** de `01-prep-db-multi.sh`, `02-odoo-setup-multi.sh`, `pack-maker.sh`, `master_install.sh` y `CLAUDE.md` (ver "Decisiones tomadas" — ya validados con el usuario, solo falta confirmar el commit).
2. **Crear la variante de instalación única por versión** en ramas específicas del repo (por ahora solo existe `master`), a partir de los scripts `-multi` actuales. Decidir ahí mismo si `master_install.sh` necesita bifurcarse en dos variantes (multi vs. single).
3. **En el script de producción (single-instance), cambiar `dbfilter`** de `^%d$` (coincidencia exacta, válido solo para el caso multi-instancia por versión) a `^%d.*$` (prefijo), para que un dominio de cliente muestre todas sus bases (`maralva_real`, `maralva_pruebas`, `maralva_formacion`, `proasur_real`, etc.).
4. **Vhost nginx de producción**: un único bloque `server_name maralva.eu *.maralva.eu;` (wildcard) en vez de un vhost por cliente, para que los subdominios nuevos (un cliente final = un subdominio, ej. futuro `gdigital.maralva.eu`) funcionen solo dando de alta el DNS, sin tocar nginx cada vez. No hace falta cambiar nada del `proxy_set_header` actual (ya reenvía `X-Forwarded-Host`, y `odoo.conf` ya tiene `proxy_mode = True`).
5. **Certificado wildcard `*.maralva.eu` — mecanismo de renovación automática sin decidir todavía.** Contexto:
   - Un wildcard exige validación **DNS-01** (no HTTP-01), lo cual de paso elimina el conflicto histórico de puerto 80 entre certbot y nginx.
   - `maralva.eu` está delegado en SupremeDNS (`dns1-4.supremedns.com`), parte del mismo panel de hosting que sirve el correo del dominio (`fi.cloudlogin.co`) — **no hay plugin de certbot conocido para SupremeDNS**, y migrar toda la zona a otro proveedor para tener plugin nativo se descartó por el riesgo de romper el correo (MX, SPF, DKIM) en la migración.
   - Opción con menor radio de impacto: delegar **solo** el nombre `_acme-challenge.maralva.eu` (vía CNAME, una única vez, a mano en SupremeDNS) hacia un proveedor con API sencilla (ej. DuckDNS), y automatizar la renovación con hooks de certbot contra esa API — sin tocar el resto de la zona ni el correo.
   - Se había planificado usar DuckDNS (de ahí existe `../maralva-ops/certs/setup-ssl-duckdns.sh`, hoy vacío), pero el router que da el operador de internet no admite DuckDNS como cliente DDNS; por eso ahora mismo se usa **ChangeIP** para mantener actualizada la IP dinámica de `proasur.maralva.eu` (esto es un problema aparte, de IP dinámica, no del reto ACME). Hay un router propio más configurable de repuesto, pendiente de poner en marcha por falta de tiempo.
   - En producción siempre habrá IP fija, así que el problema de DNS dinámico (ChangeIP) no se dará ahí — pero el problema del reto ACME en SupremeDNS sí persiste igual, con o sin IP fija.
   - Alternativas aún abiertas: (a) DuckDNS + CNAME delegado como se explicó, (b) revisar si el panel de `fi.cloudlogin.co`/SupremeDNS expone alguna API de DNS propia, (c) validación manual del TXT en cada renovación (~90 días) como opción menos automatizada.
6. Completar `../maralva-ops/certs/setup-ssl-duckdns.sh` (hoy vacío) con el resultado de la decisión del punto 5.

## Bugs conocidos

_(Ninguno abierto a día de hoy — los detectados esta sesión están arreglados en el working tree, pendientes solo de commit; ver Pendientes #1.)_

## Decisiones tomadas

- 2026-08-16 — Scripts `01-prep-db.sh`, `02-odoo-setup.sh`, `03-setup-nginx.sh` renombrados a `*-multi.sh` — motivo: son la variante **multi-instancia** (varias versiones de Odoo en un mismo servidor), pensada solo para desarrollo/pruebas; se deja sitio para una futura variante de instalación única por versión en ramas específicas, pensada para producción.
- 2026-08-16 — `pg_hba.conf` restringido a las redes de confianza de Maralva (`192.168.1.0/24` conexión directa, `192.168.100.0/24` VPN) con autenticación `scram-sha-256`, en vez de `trust` abierto a `0.0.0.0/0` — motivo: eliminaba por completo la contraseña para cualquier IP de internet. El uso real (pgAdmin remoto para mantenimiento) queda igual: mismo alcance de acceso, solo que ahora pide la contraseña del rol `odoo` (que se puede guardar en pgAdmin).
- 2026-08-16 — `admin_passwd` se deja **sin definir** en el `odoo.conf` generado, a propósito — decisión explícita del usuario: el máster password se gestiona desde el propio asistente "Crear base de datos" de Odoo, no desde este archivo. No "corregir" esto en el futuro sin volver a preguntar.
- 2026-08-16 — `list_db` se mantiene en su valor por defecto (`True`, no se añade `list_db = False`) — motivo: cada instancia aloja varias bases (Real, pruebas, formación) que necesitan poder listarse para tareas de mantenimiento.
- 2026-08-16 — `db_password` se mantiene como `odoo` por ahora (sin cambio), aunque con el fix de `pg_hba` ya sí se exige de verdad en conexiones remotas (antes, con `trust`, daba igual cuál fuera). Reforzarla queda como posible mejora futura, no decidida.
- 2026-08-16 — Para el filtrado multi-cliente en producción: el dominio raíz (`maralva.eu`) no necesita subdominio propio, porque Odoo ya sustituye `%d` en `dbfilter` por "lo que hay antes del primer punto del hostname", que para `maralva.eu` ya es `maralva`.
- 2026-08-16 — Para el certificado wildcard: se descarta migrar la zona DNS completa de `maralva.eu` fuera de SupremeDNS (por el riesgo sobre el correo del dominio, alojado en el mismo panel); se prefiere delegar únicamente el nombre `_acme-challenge.maralva.eu`. Mecanismo concreto aún sin cerrar (ver Pendientes #5).
- 2026-08-16 — `SOLDIGES/gdigital-custom` (nombre de org/repo antiguo) sustituido por `$ORGANIZACION/maralva-custom` en `02-odoo-setup-multi.sh` y `pack-maker.sh`, para que coincida con el remoto real (`MaralvaEU/maralva-custom`).

---

## Histórico de sesiones

### 2026-08-16

**Hecho:**
- Renombrados `01-prep-db.sh` → `01-prep-db-multi.sh`, `02-odoo-setup.sh` → `02-odoo-setup-multi.sh`, `03-setup-nginx.sh` → `03-setup-nginx-multi.sh` (con `git mv`, historial preservado); `master_install.sh` actualizado; commiteado y pusheado a `origin/master`.
- `CLAUDE.md` y este `ESTADO.md` añadidos al control de versiones (commiteado y pusheado).
- Revisión de seguridad/bugs de los scripts `-multi`: `sudogrep` → `sudo grep`, `pg_hba.conf` restringido con contraseña a las dos redes reales, `unaccent` generalizado a todas las BDs existentes (antes solo `maralva18` hardcodeado), `SOLDIGES/gdigital-custom` → `$ORGANIZACION/maralva-custom`, validación de `ODOO_PORT`/`ODOO_CHAT_PORT` en `master_install.sh`. Todo esto está en el working tree, **pendiente de commit** (ver Pendientes #1).
- Discusión de arquitectura para producción (multi-cliente por subdominio vía `dbfilter` de prefijo + vhost wildcard) y del problema del certificado wildcard de `*.maralva.eu` (SupremeDNS sin plugin de certbot, correo alojado en el mismo panel, saga DuckDNS/ChangeIP por la IP dinámica del router actual). Sin cerrar, ver Pendientes #3-6.

**Pendiente para la próxima sesión:**
- Confirmar y commitear los arreglos de bugs ya hechos.
- Decidir el mecanismo de automatización del certificado wildcard (Pendientes #5).
- Diseñar y crear los scripts de instalación única por versión (Pendientes #2-4).

**Notas:**
- El dato de que SupremeDNS también sirve el correo del dominio fue clave para descartar una migración completa de zona DNS y quedarse con la delegación puntual de `_acme-challenge.maralva.eu`.
