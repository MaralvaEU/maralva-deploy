#!/bin/bash

# --- 0. DETECTAR RUTAS DEL REPO ---
REPO_ROOT=$(dirname "$(readlink -f "$0")")/..
CONFIG_DIR="$REPO_ROOT/config"
LISTA_REPOS="$CONFIG_DIR/reposoca.txt"

# 1. Verificación de seguridad
echo "ADVERTENCIA: Vas a subir (PUSH) los cambios locales de este servidor a tus forks en GitHub."
read -p "POR SEGURIDAD: ¿Has realizado una instantánea de la máquina virtual? (sí/no): " snapshot
if [[ "$snapshot" != "sí" && "$snapshot" != "si" && "$snapshot" != "yes" && "$snapshot" != "y" ]]; then
    echo "Operación cancelada."
    exit 1
fi

read -p "¿Se actualizaron las bases de datos (update_databases.sh) y las pruebas de los módulos fueron correctas? (sí/no): " pruebas_ok
if [[ "$pruebas_ok" != "sí" && "$pruebas_ok" != "si" && "$pruebas_ok" != "yes" && "$pruebas_ok" != "y" ]]; then
    echo "Operación cancelada. Si las pruebas fallaron, usa update_org_origin.sh para volver a origin en vez de subir esto."
    exit 1
fi

# 2. Datos de la rama
read -p "Rama de Odoo/OCA (ej. 18.0, 19.0) [18.0]: " BRANCH
BRANCH=${BRANCH:-18.0}
BRANCH_DOMAIN=$(echo "$BRANCH" | cut -d. -f1)
BRANCH_CLEAN=$(echo "$BRANCH" | tr -d '.')
BASE_INSTANCIA="/opt/odoo/$BRANCH_DOMAIN"
DIR_CORE="$BASE_INSTANCIA/odoo"
DIR_OCA="$BASE_INSTANCIA/oca"
SERVICE_NAME="odoo${BRANCH_CLEAN}"

if [ ! -f "$LISTA_REPOS" ]; then
    echo "Error: No se encuentra $LISTA_REPOS"
    exit 1
fi

# 3. Funciones de apoyo
check_odoo_service() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "   [OK] Servicio $SERVICE_NAME activo."
        return 0
    else
        echo "   [ERROR] Servicio $SERVICE_NAME caído tras el cambio."
        return 1
    fi
}

update_repo() {
    local repo_path=$1
    local repo_name=$(basename "$repo_path")
    
    if [ -d "$repo_path/.git" ]; then
        echo "--- Subiendo $repo_name ---"
        cd "$repo_path" || return 1
        
        # Intentamos el push
        if git push origin "$BRANCH"; then
            echo "   [OK] $repo_name subido a origin."
            cd - > /dev/null || return 1 # VOLVER A LA CARPETA RAIZ (CRUCIAL)
            check_odoo_service
        else
            echo "   [ERROR] Falló el push de $repo_name."
            cd - > /dev/null || return 1
            return 1
        fi
    fi
}

# 4. Ejecución
echo "--- Iniciando Push masivo a tu Organización ---"

# Core
update_repo "$DIR_CORE" || exit 1

# Repos OCA
while IFS= read -r repo || [ -n "$repo" ]; do
    [[ -z "$repo" || "$repo" =~ ^# ]] && continue
    TARGET_DIR="$DIR_OCA/${repo}"
    update_repo "$TARGET_DIR" || exit 1
done < "$LISTA_REPOS"

echo "✅ Proceso completado. Tus forks en GitHub están sincronizados con este servidor."