#!/bin/bash

# Aplica a las bases de datos los módulos traídos por update_oca_upstream.sh
# Uso: ./update_databases.sh

# --- 0. Detectar rutas del repo ---
REPO_ROOT=$(dirname "$(readlink -f "$0")")/..

read -p "Rama de Odoo/OCA (ej. 18.0, 19.0) [18.0]: " BRANCH
BRANCH=${BRANCH:-18.0}
BRANCH_DOMAIN=$(echo "$BRANCH" | cut -d. -f1)
BRANCH_CLEAN=$(echo "$BRANCH" | tr -d '.')
BASE_INSTANCIA="/opt/odoo/$BRANCH_DOMAIN"
DIR_CORE="$BASE_INSTANCIA/odoo"
DIR_VENV="$BASE_INSTANCIA/venv"
SERVICE_NAME="odoo${BRANCH_CLEAN}"
CONF_FILE="/etc/odoo/$SERVICE_NAME.conf"

# --- 1. Localizar el último fichero de módulos actualizados para esta rama ---
# Solo es informativo (qué probar después) — el -u real usa "all" más abajo, para no
# depender de que la lista capture también cambios del core (OCB), que se excluyen a
# propósito de este fichero y podrían dejar el esquema de la BD sin migrar del todo.
CHANGED_MODULES_DIR="$REPO_ROOT/config/actualizaciones"
CHANGED_MODULES_FILE=$(ls -t "$CHANGED_MODULES_DIR"/modulos_${BRANCH}_*.txt 2>/dev/null | head -1)

if [ -z "$CHANGED_MODULES_FILE" ]; then
    echo "Aviso: no se encontró ningún fichero de módulos actualizados para la rama $BRANCH en $CHANGED_MODULES_DIR."
    echo "(Se genera al ejecutar update_oca_upstream.sh; no es obligatorio para continuar, solo informativo.)"
else
    echo "--- Módulos actualizados según $CHANGED_MODULES_FILE (para saber qué probar después) ---"
    cat "$CHANGED_MODULES_FILE"
    echo ""
fi
echo "Se aplicará: -u all (todos los módulos instalados, incluye el core y evita huecos de migración de esquema)"

# --- 2. Confirmación de seguridad ---
read -p "¿Has hecho backup/snapshot de las bases de datos antes de continuar? (sí/no): " backup_ok
if [[ "$backup_ok" != "sí" && "$backup_ok" != "si" && "$backup_ok" != "yes" && "$backup_ok" != "y" ]]; then
    echo "Operación cancelada. Haz backup antes de continuar."
    exit 1
fi

# --- 3. Detectar bases de datos existentes ---
DB_LIST=$(sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'template0', 'template1');")

if [ -z "$DB_LIST" ]; then
    echo "No se ha detectado ninguna base de datos."
    exit 1
fi

echo "--- Bases de datos detectadas ---"
echo "$DB_LIST"
echo ""
read -p "¿Sobre qué bases de datos aplicar el update? (nombres separados por coma, o 'todas'): " DB_SELECCION

if [ "$DB_SELECCION" = "todas" ]; then
    DBS_A_ACTUALIZAR=$DB_LIST
else
    DBS_A_ACTUALIZAR=$(echo "$DB_SELECCION" | tr ',' '\n' | sed 's/^ *//; s/ *$//')
fi

if [ -z "$DBS_A_ACTUALIZAR" ]; then
    echo "No se ha seleccionado ninguna base de datos. Operación cancelada."
    exit 1
fi

# --- 4. Parar el servicio antes de actualizar (evita choques con el proceso en marcha) ---
echo "--- Deteniendo $SERVICE_NAME ---"
sudo systemctl stop "$SERVICE_NAME"

# --- 5. Aplicar -u por cada base de datos seleccionada ---
FALLOS=()
for DB in $DBS_A_ACTUALIZAR; do
    echo "--- Actualizando $DB ---"
    if sudo -u odoo "$DIR_VENV/bin/python3" "$DIR_CORE/odoo-bin" -c "$CONF_FILE" -u all -d "$DB" --stop-after-init; then
        echo "   [OK] $DB actualizada."
    else
        echo "   [ERROR] Falló la actualización de $DB."
        FALLOS+=("$DB")
    fi
done

# --- 6. Reiniciar el servicio ---
echo "--- Reiniciando $SERVICE_NAME ---"
sudo systemctl start "$SERVICE_NAME"

if [ ${#FALLOS[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Fallaron estas bases de datos: ${FALLOS[*]}"
    echo "Revisa los logs en /var/log/odoo/$SERVICE_NAME.log antes de decidir push/rollback."
    exit 1
fi

echo "✅ Actualización aplicada correctamente a: $DBS_A_ACTUALIZAR"
echo "Si las pruebas de los módulos actualizados son correctas: ./push_org_origin.sh"
echo "Si algo falló: ./update_org_origin.sh (vuelve a lo que había en tu fork)"
