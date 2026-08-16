#!/bin/bash

# --- 0. DETECTAR RUTAS DEL REPO ---
# Obtenemos la carpeta donde está este script (Raíz)
export REPO_ROOT=$(dirname "$(readlink -f "$0")")
export SCRIPTS_DIR="$REPO_ROOT/scripts"
export CONFIG_DIR="$REPO_ROOT/config"

# --- 1. SOLICITUD DE DATOS (Interactivo) ---
echo "=============================================="
echo " MARALVA DEPLOY - INSTALADOR MAESTRO "
echo "=============================================="

read -p "Rama de Odoo/OCA (ej. 18.0, 19.0): " BRANCH
[ -z "$BRANCH" ] && { echo "Error: Rama obligatoria"; exit 1; }
export BRANCH

read -p "Organización de GitHub (tu fork): " ORGANIZACION
[ -z "$ORGANIZACION" ] && { echo "Error: Organización obligatoria"; exit 1; }
export ORGANIZACION

read -p "Dominio base (ej. maralva.loc): " DOMAIN
[ -z "$DOMAIN" ] && { echo "Error: Dominio obligatorio"; exit 1; }
export DOMAIN

read -p "Puerto HTTP: " ODOO_PORT
[ -z "$ODOO_PORT" ] && { echo "Error: Puerto HTTP obligatorio"; exit 1; }
export ODOO_PORT

read -p "Puerto Longpolling/Gevent: " ODOO_CHAT_PORT
[ -z "$ODOO_CHAT_PORT" ] && { echo "Error: Puerto Longpolling/Gevent obligatorio"; exit 1; }
export ODOO_CHAT_PORT

# --- 2. CÁLCULO DE VARIABLES DERIVADAS ---
export BRANCH_CLEAN=$(echo "$BRANCH" | tr -d '.')
export BRANCH_DOMAIN=$(echo "$BRANCH" | cut -d. -f1)
export MARCA=$(echo "$DOMAIN" | cut -d. -f1)
export SERVICE_NAME="odoo${BRANCH_CLEAN}"

# RUTAS DE CONFIGURACIÓN (Exportadas para los scripts hijos)
export LISTA_REPOS="$CONFIG_DIR/reposoca.txt"
export REQS_CUSTOM="$CONFIG_DIR/requirements_standard.txt"

# --- 3. LANZAMIENTO DE FASES ---
# Damos permisos a todos los scripts de la carpeta de una vez
chmod +x "$SCRIPTS_DIR"/*.sh

echo -e "\n>>> Fase 1: PostgreSQL y Sistema..."
"$SCRIPTS_DIR/01-prep-db-multi.sh" || { echo "Falló Fase 1"; exit 1; }

echo -e "\n>>> Fase 2: Odoo Setup (Core, OCA, Venv)..."
"$SCRIPTS_DIR/02-odoo-setup-multi.sh" || { echo "Falló Fase 2"; exit 1; }

echo -e "\n>>> Fase 3: Nginx..."
"$SCRIPTS_DIR/03-setup-nginx-multi.sh" || { echo "Falló Fase 3"; exit 1; }

echo -e "\n=============================================="
echo " INSTALACIÓN COMPLETADA "
echo " URL: http://$MARCA$BRANCH_DOMAIN.loc"
echo "=============================================="

# --- SECCIÓN: COMPROBACIÓN FINAL ---
echo -e "\n--- Verificando estado de los servicios ---"

# 1. PostgreSQL
if systemctl is-active --quiet postgresql; then
    echo "[OK] PostgreSQL activo."
else
    echo "[ERROR] PostgreSQL no responde."
fi

# 2. Servicio Odoo específico (ej. odoo180)
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[OK] Servicio $SERVICE_NAME activo."
else
    echo "[ERROR] El servicio $SERVICE_NAME no arrancó. Revisa: sudo journalctl -u $SERVICE_NAME"
fi

# 3. Nginx
if systemctl is-active --quiet nginx; then
    echo "[OK] Nginx activo."
else
    echo "[ERROR] Nginx falló. Revisa: sudo nginx -t"
fi

# 4. Puertos (Usando las variables del lanzador)
echo "--- Puertos en escucha para esta instancia ---"
sudo ss -tunlp | grep -E ":$ODOO_PORT|:$ODOO_CHAT_PORT"

echo -e "\n🚀 Instancia Odoo $BRANCH lista en: http://$MARCA$BRANCH_DOMAIN.loc"
echo "📂 Log disponible en: /var/log/odoo/$SERVICE_NAME.log"
