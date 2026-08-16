#!/bin/bash
set -e

# 1. Configuración dinámica del usuario que ejecuta
REAL_USER=${SUDO_USER:-$USER}

# 2. Variables obtenidas de install_master.sh (Exportadas)
if [ -z "$BRANCH" ] || [ -z "$ORGANIZACION" ] || [ -z "$SERVICE_NAME" ]; then
    echo "Error: variables necesarias no definidas."
    exit 1
fi

# 3. Definición de estructura
BASE_INSTANCIA="/opt/odoo/$BRANCH_DOMAIN"
DIR_CORE="$BASE_INSTANCIA/odoo"
DIR_OCA="$BASE_INSTANCIA/oca"
DIR_CUSTOM="$BASE_INSTANCIA/gdigital-custom" # Tu repo personal
DIR_VENV="$BASE_INSTANCIA/venv"
CONF_FILE="/etc/odoo/$SERVICE_NAME.conf"
LOG_DIR="/var/log/odoo"

echo "--- Preparando estructura para $BRANCH ---"
sudo mkdir -p "$BASE_INSTANCIA" "$DIR_CORE" "$DIR_OCA" "$DIR_CUSTOM" "$LOG_DIR" /etc/odoo
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
sudo mkdir -p "$BASE_INSTANCIA" "$DIR_CORE" "$DIR_OCA" "$DIR_CUSTOM" "$LOG_DIR" /etc/odoo

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

# 8. Clonar OCB (Core) --- ACTUALIZADO CON ORGANIZACIÓN ---
if [ ! -d "$DIR_CORE/.git" ]; then
	echo "--- Clonando OCB $BRANCH desde $ORGANIZACION ---"
	git clone --depth 1 --branch "$BRANCH" "git@github.com:$ORGANIZACION/OCB.git" "$DIR_CORE"
fi
if [ -d "$DIR_CORE" ]; then
	cd "$DIR_CORE"
	if ! git remote | grep -q "upstream"; then
		echo "---Añadiendo upstream OCA/OCB ---"
		git remote add upstream "git@github.com:OCA/OCB.git"
		# Opcional: Traer metadatos del upstream sin bajar todo el historial
		git fetch --depth 1 upstream "$BRANCH"
	fi
fi

# 9. Clonar repositorios de la lista
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
				git clone --depth 1 --branch "$BRANCH" "$OCA_REPO" "$TARGET_DIR"
			fi
		fi
		# Configuración de remotes
		if [ -d "$TARGET_DIR" ]; then
			cd "$TARGET_DIR"
			# 1. Asegurar que origin es la Organización
			git remote set-url origin "$MY_FORK"
			# 2.- Añadir upstream (OCA) si no existe
			if ! git remote | grep -q "upstream"; then
				git remote add upstream "$OCA_REPO"
				git fetch --depth 1 upstream "$BRANCH"
			fi
		fi
	done < "$LISTA_REPOS"
else
	echo "Error: No existe el archivo $LISTA_REPOS"
	exit 1
fi

# --- 10. Clonar tu repositorio personal ---
if [ ! -d "$DIR_CUSTOM/.git" ]; then
    echo "--- Clonando tu repo personal gdigital-custom ---"
    git clone --branch "$BRANCH" "git@github.com:SOLDIGES/gdigital-custom.git" "$DIR_CUSTOM"
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

# --- 14. GENERACIÓN DEL ODOO.CONF (SIMPLIFICADO Y SMART) ---
echo "--- Generando archivo de configuración en $CONF_FILE ---"

# Simplificamos el addons_path a las raíces (Odoo escanea subcarpetas)
ADDONS_PATH="$DIR_CORE/addons,$DIR_OCA,$DIR_CUSTOM"

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
dbfilter = ^%d$
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