#!/bin/bash

# Script para actualizar repositorios desde upstream (OCA) mediante SSH
# Uso: ./update_oca_upstream.sh

# Timeout para git fetch (segundos); evita quedarse colgado por problemas de red
FETCH_TIMEOUT=300

echo "ADVERTENCIA: Esta actualización traerá cambios desde OCA que podrían afectar bases de datos existentes."
echo "REALIZAR SNAPSHOT DE LA MAQUINA VIRTUAL ANTES DE CONTINUAR."

# Verificación de seguridad: Instantánea de la VM
echo "POR SEGURIDAD: ¿Has realizado una instantánea de la máquina virtual? (sí/no)"
read -p "Respuesta: " snapshot
if [[ "$snapshot" != "sí" && "$snapshot" != "si" && "$snapshot" != "yes" && "$snapshot" != "y" ]]; then
    echo "Operación cancelada. Realiza una instantánea antes de continuar."
    exit 1
fi

# Instancia única: un solo /opt/odoo, sin sufijo de versión. La rama se detecta
# del propio clon del core en vez de preguntarla (aquí solo hay una).
BASE_INSTANCIA="/opt/odoo"
DIR_CORE="$BASE_INSTANCIA/odoo"
DIR_OCA="$BASE_INSTANCIA/oca"
# Detectar la raíz del repo (un nivel arriba de /scripts)
REPO_ROOT=$(dirname "$(readlink -f "$0")")/..
LISTA_REPOS="$REPO_ROOT/config/reposoca.txt"

if [ ! -d "$DIR_CORE/.git" ]; then
    echo "Error: no se encuentra $DIR_CORE (¿está instalado Odoo en esta máquina?)"
    exit 1
fi
BRANCH=$(git -C "$DIR_CORE" rev-parse --abbrev-ref HEAD)
echo "Rama detectada automáticamente: $BRANCH"

if [ ! -f "$LISTA_REPOS" ]; then
    echo "Error: No se encuentra $LISTA_REPOS"
    exit 1
fi

echo "--- Actualizando repositorios desde upstream (OCA) para rama $BRANCH ---"

CHANGED_MODULES_FILE="$REPO_ROOT/config/actualizaciones/modulos_${BRANCH}_$(date '+%Y-%m-%d_%H%M').txt"
mkdir -p "$(dirname "$CHANGED_MODULES_FILE")"
: > "$CHANGED_MODULES_FILE"
echo "Registrando módulos actualizados en $CHANGED_MODULES_FILE ..."

LOG_INCOHERENCIAS="/var/log/odoo/repos_con_divergencias.log"
echo "Preparando log en $LOG_INCOHERENCIAS ..."
> "$LOG_INCOHERENCIAS" || { echo "Error: no se puede escribir en $LOG_INCOHERENCIAS (¿permisos? ¿sudo?)"; exit 1; }
MAX_SIZE=1024 # 1 MB en KB
MAX_ARCHIVOS=5 # Guardar hasta 5 rotaciones antiguas

if [ -f "$LOG_INCOHERENCIAS" ]; then
    TAMANO=$(du -k "$LOG_INCOHERENCIAS" | cut -f1)
    if [ "$TAMANO" -gt "$MAX_SIZE" ]; then
        echo "--- Rotando log de divergencias (Superado 1MB) ---"
        # Desplazar archivos antiguos (.4 -> .5, .3 -> .4, etc.)
        for i in $(seq $((MAX_ARCHIVOS-1)) -1 1); do
            [ -f "${LOG_INCOHERENCIAS}.$i" ] && mv "${LOG_INCOHERENCIAS}.$i" "${LOG_INCOHERENCIAS}.$((i+1))"
        done
        # Renombrar el actual a .1
        mv "$LOG_INCOHERENCIAS" "${LOG_INCOHERENCIAS}.1"
        # Crear el nuevo vacío
        touch "$LOG_INCOHERENCIAS"
    fi
fi
# Función para actualizar un repo (CORREGIDA)
update_repo() {
    local repo_path=$1
    local is_core=${2:-false}
    local repo_name=$(basename "$repo_path")

    if [ -d "$repo_path/.git" ]; then
        cd "$repo_path" || return
        local old_head
        old_head=$(git rev-parse HEAD)

        # 1. Traer novedades
        echo "   Fetching upstream/$BRANCH en $repo_name (timeout ${FETCH_TIMEOUT}s) ..."
        if ! timeout "$FETCH_TIMEOUT" git fetch upstream "$BRANCH"; then
            echo "   [ERROR] Timeout o fallo en $repo_name."
            cd - > /dev/null || true # Volver atrás antes de salir
            exit 1
        fi

        # 2. Comprobar incoherencias
        BEHIND=$(git rev-list HEAD..upstream/"$BRANCH" --count)
        AHEAD=$(git rev-list upstream/"$BRANCH"..HEAD --count)

        if [ "$AHEAD" -gt 0 ]; then
            echo "[ALERTA] $repo_name tiene $AHEAD commits divergentes."
            echo "$(date '+%Y-%m-%d %H:%M:%S') - REPO: $repo_name - Divergencia: $AHEAD commits" >> "$LOG_INCOHERENCIAS"
        fi

        # 3. Sincronizar servidor con Upstream
        echo "--- Sincronizando $repo_name con Upstream ---"
        if git reset --hard "upstream/$BRANCH" > /dev/null 2>&1; then
            echo "   [OK] $repo_name actualizado."

            # 4. Registrar qué módulos cambiaron de verdad (el core se omite: demasiado ruido)
            if [ "$is_core" != "true" ]; then
                local modulos
                modulos=$(git diff --name-only "$old_head" HEAD -- . | cut -d/ -f1 | sort -u)
                if [ -n "$modulos" ]; then
                    while IFS= read -r modulo; do
                        if [ -f "$modulo/__manifest__.py" ] || [ -f "$modulo/__openerp__.py" ]; then
                            # Si el módulo no existía en el commit anterior, es de nueva incorporación
                            if git cat-file -e "$old_head:$modulo" 2>/dev/null; then
                                echo "$repo_name/$modulo" >> "$CHANGED_MODULES_FILE"
                            else
                                echo "$repo_name/$modulo [NUEVO]" >> "$CHANGED_MODULES_FILE"
                            fi
                        fi
                    done <<< "$modulos"
                fi
            fi
        else
            echo "   [ERROR] Fallo crítico al resetear $repo_name."
        fi

        # 5. VOLVER A LA CARPETA ANTERIOR (Crucial para el bucle)
        cd - > /dev/null || true
    fi
}

# Actualizar core (OCB) — suele ser el más pesado
echo "--- Repo core: $DIR_CORE ---"
echo "    (El core tiene muchos cambios; el fetch puede tardar varios minutos.)"
update_repo "$DIR_CORE" true

# Actualizar repos OCA desde lista
while IFS= read -r repo || [ -n "$repo" ]; do
    [[ -z "$repo" || "$repo" =~ ^# ]] && continue
    
    TARGET_DIR="$DIR_OCA/${repo}"
    update_repo "$TARGET_DIR"
done < "$LISTA_REPOS"

echo "--- Actualización desde upstream completada ---"
echo "IMPORTANTE: Revisa si hay cambios que puedan afectar bases de datos existentes."
echo "Considera hacer backup antes de reiniciar Odoo."

if [ -s "$CHANGED_MODULES_FILE" ]; then
    echo ""
    echo "📄 Módulos actualizados (guardado en $CHANGED_MODULES_FILE):"
    cat "$CHANGED_MODULES_FILE"
    echo ""
    echo "Siguiente paso: ./update_databases.sh para aplicar estos cambios a las bases de datos."
else
    echo "No se detectaron módulos con cambios."
fi