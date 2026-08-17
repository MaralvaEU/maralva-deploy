#!/bin/bash

# Descarta los cambios traídos de OCA y vuelve a lo que hay en tu propio fork
# (origin) — rollback a usar cuando update_oca_upstream.sh + update_databases.sh
# no salieron bien en las pruebas.
# Uso: ./update_org_origin.sh

echo "ADVERTENCIA: Esto descartará los cambios traídos de OCA y dejará cada repo"
echo "exactamente como está en tu fork (origin), perdiendo cualquier cambio local"
echo "no subido."
read -p "¿Confirmas que quieres deshacer la actualización y volver a origin? (sí/no): " confirma
if [[ "$confirma" != "sí" && "$confirma" != "si" && "$confirma" != "yes" && "$confirma" != "y" ]]; then
    echo "Operación cancelada."
    exit 1
fi

# Instancia única: sin sufijo de versión. La rama se detecta del propio clon del core.
BASE_INSTANCIA="/opt/odoo"
DIR_CORE="$BASE_INSTANCIA/odoo"
DIR_OCA="$BASE_INSTANCIA/oca"
REPO_ROOT=$(dirname "$(readlink -f "$0")")/..
LISTA_REPOS="$REPO_ROOT/config/reposoca.txt"

if [ ! -f "$LISTA_REPOS" ]; then
    echo "Error: No se encuentra $LISTA_REPOS"
    exit 1
fi

if [ ! -d "$DIR_CORE/.git" ]; then
    echo "Error: no se encuentra $DIR_CORE (¿está instalado Odoo en esta máquina?)"
    exit 1
fi
BRANCH=$(git -C "$DIR_CORE" rev-parse --abbrev-ref HEAD)
echo "Rama detectada automáticamente: $BRANCH"

echo "--- Volviendo a origin para rama $BRANCH ---"

reset_repo_a_origin() {
    local repo_path=$1
    local repo_name=$(basename "$repo_path")

    if [ -d "$repo_path/.git" ]; then
        cd "$repo_path" || return
        echo "--- Restaurando $repo_name a origin/$BRANCH ---"
        if git fetch origin "$BRANCH" && git reset --hard "origin/$BRANCH" > /dev/null 2>&1; then
            echo "   [OK] $repo_name restaurado a origin/$BRANCH."
        else
            echo "   [ERROR] Fallo al restaurar $repo_name."
        fi
        cd - > /dev/null || true
    fi
}

reset_repo_a_origin "$DIR_CORE"

while IFS= read -r repo || [ -n "$repo" ]; do
    [[ -z "$repo" || "$repo" =~ ^# ]] && continue
    TARGET_DIR="$DIR_OCA/${repo}"
    reset_repo_a_origin "$TARGET_DIR"
done < "$LISTA_REPOS"

echo "--- Restauración a origin completada ---"
echo "Si ya habías aplicado el update a alguna base de datos (update_databases.sh),"
echo "recuerda restaurarla también desde el backup/snapshot — este script solo"
echo "afecta al código, no a las bases de datos."
