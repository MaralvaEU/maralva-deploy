#!/bin/bash
set -e

# 1. Configuración dinámica del usuario que ejecuta
REAL_USER=${SUDO_USER:-$USER}

# 2. Variables obtenidas de install_master.sh (Exportadas)
if [ -z "$BRANCH" ] || [ -z "$ORGANIZACION" ] || [ -z "$SERVICE_NAME" ]; then
    echo "Error: variables necesarias no definidas."
    exit 1
fi

# 3. Definición de estructura (instancia única: sin sufijo de versión)
BASE_INSTANCIA="/opt/odoo"
DIR_CORE="$BASE_INSTANCIA/odoo"
DIR_OCA="$BASE_INSTANCIA/oca"
DIR_CUSTOM="$BASE_INSTANCIA/maralva-custom" # Tu repo de addons custom
DIR_MARALVA_OCA="$BASE_INSTANCIA/maralva-oca" # Repo propio de módulos OCA portados a esta versión (opcional)
DIR_VENV="$BASE_INSTANCIA/venv"
CONF_FILE="/etc/odoo/$SERVICE_NAME.conf"
LOG_DIR="/var/log/odoo"

echo "--- Preparando estructura para $BRANCH ---"
sudo mkdir -p "$BASE_INSTANCIA" "$DIR_CORE" "$DIR_OCA" "$DIR_CUSTOM" "$DIR_MARALVA_OCA" "$LOG_DIR" /etc/odoo
sudo chown -R "$REAL_USER":odoo "$BASE_INSTANCIA"
sudo chmod -R 775 "$BASE_INSTANCIA"

# --- 4. Configurar permisos y vinculación de grupo ---
# Aseguramos que el usuario que lanza el script pertenezca al grupo odoo
if ! id -nG "$REAL_USER" | grep -qw "odoo"; then
    echo "--- Añadiendo $REAL_USER al grupo odoo ---"
    sudo usermod -aG odoo "$REAL_USER"
    # Forzamos que el grupo principal para esta sesión de escritura sea odoo
    sudo usermod -g odoo "$REAL_USER"
	exec sg odoo "$0" "$@"
fi

echo "--- Preparando estructura de /opt/odoo para $BRANCH ---"
sudo mkdir -p "$BASE_INSTANCIA" "$DIR_CORE" "$DIR_OCA" "$DIR_CUSTOM" "$DIR_MARALVA_OCA" "$LOG_DIR" /etc/odoo

# Aplicamos la jerarquía de permisos Maralva:
# Usuario real como dueño, grupo odoo para que el servicio pueda leer/escribir
sudo chown -R "$REAL_USER":odoo "$BASE_INSTANCIA"
sudo chmod -R 775 "$BASE_INSTANCIA"

# Logs y configs: propiedad de odoo para que el servicio arranque sin trabas
sudo chown -R odoo:odoo "$LOG_DIR" /etc/odoo
sudo chmod -R 770 "$LOG_DIR" /etc/odoo

# Aseguramos que los nuevos archivos creados en el futuro hereden el grupo odoo (Setgid)
sudo chmod g+s "$BASE_INSTANCIA"

echo "--- Clonando y configurando Odoo $BRANCH ---"
sudo git config --system --add safe.directory '*'

# Comprobar si podemos crear forks automáticamente con GitHub CLI
GH_AVAILABLE=true
if ! command -v gh &>/dev/null; then
	echo "Aviso: 'gh' (GitHub CLI) no está instalado; los forks que falten habrá que crearlos a mano." >&2
	GH_AVAILABLE=false
elif ! gh auth status &>/dev/null; then
	echo "Aviso: 'gh' no está autenticado (ejecuta 'gh auth login'); los forks que falten habrá que crearlos a mano." >&2
	GH_AVAILABLE=false
fi

# 8. Clonar OCB (Core) --- ACTUALIZADO CON ORGANIZACIÓN ---
if [ ! -d "$DIR_CORE/.git" ]; then
	echo "--- Clonando OCB $BRANCH desde $ORGANIZACION ---"
	if ! git clone --depth 1 --branch "$BRANCH" "git@github.com:$ORGANIZACION/OCB.git" "$DIR_CORE"; then
		echo "   [!] Fork de OCB no encontrado en $ORGANIZACION. Clonando de OCA..."
		git clone --depth 1 --branch "$BRANCH" "git@github.com:OCA/OCB.git" "$DIR_CORE"
		if [ "$GH_AVAILABLE" = true ]; then
			echo "   --- Creando fork de OCA/OCB en $ORGANIZACION ---"
			gh repo fork OCA/OCB --org "$ORGANIZACION" --clone=false || echo "   [!] No se pudo crear el fork de OCB automáticamente." >&2
		else
			echo "   [!] Crea el fork de OCA/OCB en $ORGANIZACION manualmente para poder hacer push más adelante." >&2
		fi
	fi
fi
if [ -d "$DIR_CORE" ]; then
	cd "$DIR_CORE"
	git remote set-url origin "git@github.com:$ORGANIZACION/OCB.git"
	if ! git remote | grep -q "upstream"; then
		echo "---Añadiendo upstream OCA/OCB ---"
		git remote add upstream "git@github.com:OCA/OCB.git"
		# Opcional: Traer metadatos del upstream sin bajar todo el historial
		git fetch --depth 1 upstream "$BRANCH"
	fi
	cd - > /dev/null
fi

# 9. Clonar repositorios de la lista
REPOS_OMITIDOS=()
# Cada repo de reposoca.txt es su propio addons_path: Odoo solo escanea un
# nivel de subcarpetas de cada ruta, así que apuntar solo a "$DIR_OCA" (la
# carpeta que contiene los repos, no los módulos) no encuentra ningún
# módulo real dentro de ellos.
OCA_ADDONS_DIRS=()
if [ -f "$LISTA_REPOS" ]; then
	while IFS= read -r repo || [ -n "$repo" ]; do
		[[ -z "$repo" || "$repo" =~ ^# ]] && continue

		TARGET_DIR="$DIR_OCA/${repo}"
		MY_FORK="git@github.com:$ORGANIZACION/${repo}.git"
		OCA_REPO="git@github.com:OCA/${repo}.git"

		if [ ! -d "$TARGET_DIR" ]; then
			echo "--- Repositorio: $repo ---"
			# Intentar clonar Fork, si falla, clonar OCA (mostrando errores para poder depurar)
			if git clone --depth 1 --branch "$BRANCH" "$MY_FORK" "$TARGET_DIR"; then
				echo "   [OK] Fork de $ORGANIZACION clonado."
			else
				echo "   [!] Fork no encontrado en $ORGANIZACION o error de acceso. Clonando de OCA..."
				if git clone --depth 1 --branch "$BRANCH" "$OCA_REPO" "$TARGET_DIR"; then
					if [ "$GH_AVAILABLE" = true ]; then
						echo "   --- Creando fork de OCA/$repo en $ORGANIZACION ---"
						gh repo fork "OCA/$repo" --org "$ORGANIZACION" --clone=false || echo "   [!] No se pudo crear el fork de $repo automáticamente." >&2
					else
						echo "   [!] Crea el fork de OCA/$repo en $ORGANIZACION manualmente más adelante." >&2
					fi
				else
					echo "   [!] $repo tampoco tiene la rama $BRANCH en OCA todavía. Se omite." >&2
					REPOS_OMITIDOS+=("$repo")
					continue
				fi
			fi
		fi
		# Configuración de remotes
		if [ -d "$TARGET_DIR" ]; then
			OCA_ADDONS_DIRS+=("$TARGET_DIR")
			cd "$TARGET_DIR"
			# 1. Asegurar que origin es la Organización
			git remote set-url origin "$MY_FORK"
			# 2.- Añadir upstream (OCA) si no existe
			if ! git remote | grep -q "upstream"; then
				git remote add upstream "$OCA_REPO"
				git fetch --depth 1 upstream "$BRANCH"
			fi
			cd - > /dev/null
		fi
	done < "$LISTA_REPOS"
else
	echo "Error: No existe el archivo $LISTA_REPOS"
	exit 1
fi

if [ ${#REPOS_OMITIDOS[@]} -gt 0 ]; then
	echo ""
	echo "⚠️  Repositorios OMITIDOS (sin rama $BRANCH todavía en OCA): ${REPOS_OMITIDOS[*]}"
	echo "    Revisa config/pack_maralva_base*.txt: los módulos de esos repos no estarán disponibles hasta que OCA migre esa rama."
fi

# --- 9b. Clonar openupgradelib ---
# No es un módulo de Odoo (no tiene __manifest__.py): es una librería Python normal
# (from openupgradelib import openupgrade), y no depende de la versión de Odoo, solo
# tiene rama "master". Por eso NO va dentro de oca/, sino en su propia carpeta;
# el venv la instala en modo editable (ver sección 11).
OPENUPGRADELIB_DIR="$BASE_INSTANCIA/openupgradelib"
if [ ! -d "$OPENUPGRADELIB_DIR/.git" ]; then
	echo "--- Repositorio: openupgradelib (rama master) ---"
	if git clone --depth 1 --branch master "git@github.com:$ORGANIZACION/openupgradelib.git" "$OPENUPGRADELIB_DIR"; then
		echo "   [OK] Fork de $ORGANIZACION clonado."
	else
		echo "   [!] Fork no encontrado en $ORGANIZACION. Clonando de OCA..."
		if git clone --depth 1 --branch master "git@github.com:OCA/openupgradelib.git" "$OPENUPGRADELIB_DIR"; then
			if [ "$GH_AVAILABLE" = true ]; then
				echo "   --- Creando fork de OCA/openupgradelib en $ORGANIZACION ---"
				gh repo fork OCA/openupgradelib --org "$ORGANIZACION" --clone=false || echo "   [!] No se pudo crear el fork automáticamente." >&2
			else
				echo "   [!] Crea el fork de OCA/openupgradelib en $ORGANIZACION manualmente más adelante." >&2
			fi
		else
			echo "   [ERROR] No se pudo clonar openupgradelib ni de $ORGANIZACION ni de OCA." >&2
		fi
	fi
fi
if [ -d "$OPENUPGRADELIB_DIR/.git" ]; then
	cd "$OPENUPGRADELIB_DIR"
	git remote set-url origin "git@github.com:$ORGANIZACION/openupgradelib.git"
	if ! git remote | grep -q "upstream"; then
		git remote add upstream "git@github.com:OCA/openupgradelib.git"
		git fetch --depth 1 upstream master
	fi
	cd - > /dev/null
fi

# --- 10. Clonar tu repositorio personal ---
if [ ! -d "$DIR_CUSTOM/.git" ]; then
    echo "--- Clonando tu repo de addons custom maralva-custom ---"
    git clone --branch "$BRANCH" "git@github.com:$ORGANIZACION/maralva-custom.git" "$DIR_CUSTOM"
fi

# --- 10b. Clonar (opcional) tu repo de módulos OCA portados manualmente ---
# maralva-oca es un repo propio (sin origen en OCA) para módulos OCA que
# todavía no tienen rama publicada para esta versión de Odoo y se han
# portado a mano (ver README de ese repo, ej. account_loan en 19.0) -- no
# toda organización/instalación lo necesita, así que si el repo o la rama
# $BRANCH no existen todavía se omite con aviso, sin abortar la instalación.
DIR_MARALVA_OCA_ADDONS=""
if [ ! -d "$DIR_MARALVA_OCA/.git" ]; then
	echo "--- Clonando (si existe) tu repo de módulos OCA portados maralva-oca ---"
	if git clone --branch "$BRANCH" "git@github.com:$ORGANIZACION/maralva-oca.git" "$DIR_MARALVA_OCA" 2>/dev/null; then
		echo "   [OK] maralva-oca clonado."
	else
		echo "   [!] maralva-oca no existe en $ORGANIZACION o no tiene la rama $BRANCH todavía. Se omite (opcional)." >&2
	fi
fi
if [ -d "$DIR_MARALVA_OCA/.git" ]; then
	DIR_MARALVA_OCA_ADDONS="$DIR_MARALVA_OCA"
fi

# --- 11. Entorno Virtual y Dependencias (MEJORADO) ---
if [ ! -d "$DIR_VENV" ]; then
    echo "--- Creando entorno virtual en $DIR_VENV ---"
    python3 -m venv "$DIR_VENV"
fi

echo "--- Instalando dependencias Python ---"
"$DIR_VENV/bin/pip" install --upgrade pip
[ -f "$DIR_CORE/requirements.txt" ] && "$DIR_VENV/bin/pip" install -r "$DIR_CORE/requirements.txt"

# INYECCIÓN DE TUS REQUIREMENTS PERSONALIZADOS
if [ -f "$REQS_CUSTOM" ]; then
    echo "--- Instalando tus requerimientos estándar desde $REQS_CUSTOM ---"
    "$DIR_VENV/bin/pip" install -r "$REQS_CUSTOM"
fi

# openupgradelib en modo editable (ver sección 9b)
if [ -d "$OPENUPGRADELIB_DIR" ]; then
    echo "--- Instalando openupgradelib (editable) en el venv ---"
    "$DIR_VENV/bin/pip" install -e "$OPENUPGRADELIB_DIR"
fi

# --- 14. GENERACIÓN DEL ODOO.CONF (SIMPLIFICADO Y SMART) ---
echo "--- Generando archivo de configuración en $CONF_FILE ---"

# Odoo solo escanea un nivel de subcarpetas por cada ruta del addons_path:
# "$DIR_OCA" no vale como ruta única porque contiene repos (una carpeta por
# repo), no módulos directamente -- cada repo de OCA_ADDONS_DIRS (rellenado
# en la sección 9 a partir de reposoca.txt) necesita su propia entrada.
OCA_ADDONS_PATH=$(IFS=,; echo "${OCA_ADDONS_DIRS[*]}")
ADDONS_PATH="$DIR_CORE/addons,$OCA_ADDONS_PATH,$DIR_CUSTOM"
if [ -n "$DIR_MARALVA_OCA_ADDONS" ]; then
	ADDONS_PATH="$ADDONS_PATH,$DIR_MARALVA_OCA_ADDONS"
fi

# Lógica para Odoo 19: gevent_port vs longpolling_port
if [ "$BRANCH_DOMAIN" -eq 19 ]; then
    CHAT_PARAM="gevent_port = $ODOO_CHAT_PORT"
else
    CHAT_PARAM="longpolling_port = $ODOO_CHAT_PORT"
fi

sudo bash -c "cat > $CONF_FILE <<EOF
[options]
db_user = odoo
db_password = odoo
http_port = $ODOO_PORT
proxy_mode = True
logrotate = True
dbfilter = ^%d.*$
$CHAT_PARAM
addons_path = $ADDONS_PATH
logfile = $LOG_DIR/$SERVICE_NAME.log
workers = 5
unaccent = True
EOF"

# 15. Generar Servicio Systemd ---
FILE_SERVICE="/etc/systemd/system/$SERVICE_NAME.service"

echo "--- Generando archivo de servicio en $FILE_SERVICE ---"
sudo bash -c "cat > $FILE_SERVICE <<EOF
[Unit]
Description=Odoo $BRANCH Service
After=network.target postgresql.service

[Service]
Type=simple
User=odoo
Group=odoo
# Usamos la ruta absoluta del python del venv y del odoo-bin
ExecStart=$DIR_VENV/bin/python3 $DIR_CORE/odoo-bin -c $CONF_FILE
# Esto asegura que si falla, intente reiniciar solo
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF"

# 16. Recargar y arrancar servicio
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo "✅ Configuración de Odoo $BRANCH completada."