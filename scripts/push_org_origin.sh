#!/bin/bash

# --- 0. DETECTAR RUTAS DEL REPO ---
REPO_ROOT=$(dirname "$(readlink -f "$0")")/..
CONFIG_DIR="$REPO_ROOT/config"
LISTA_REPOS="$CONFIG_DIR/reposoca.txt"

# 1. Verificación de seguridad
echo "ADVERTENCIA: Vas a subir (PUSH --force-with-lease) los cambios locales de este servidor a tus forks en GitHub."
echo "Esto puede reescribir el historial de tu fork (por ejemplo, si update_oca_upstream.sh descartó commits divergentes al traer de OCA)."
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

# 2. Rutas e instancia única: sin sufijo de versión. La rama se detecta del core.
BASE_INSTANCIA="/opt/odoo"
DIR_CORE="$BASE_INSTANCIA/odoo"
DIR_OCA="$BASE_INSTANCIA/oca"
SERVICE_NAME="odoo"

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
        cd "$repo_path" || return 1

        # Bloqueo de seguridad: los repos de OCA deben ser espejos limpios de upstream.
        # Si hay commits locales que upstream no tiene, alguien tocó el código a mano
        # en vez de usar maralva-custom — no se sube ese repo.
        if git remote | grep -q "upstream"; then
            git fetch --quiet upstream "$BRANCH" 2>/dev/null || true
            AHEAD=$(git rev-list "upstream/$BRANCH"..HEAD --count 2>/dev/null || echo 0)
            if [ "$AHEAD" -gt 0 ]; then
                echo "--- Subiendo $repo_name ---"
                echo "   [BLOQUEADO] $repo_name tiene $AHEAD commit(s) que no vienen de OCA (upstream/$BRANCH). No se sube."
                echo "   El código de OCA no debe editarse a mano; revisa 'git log upstream/$BRANCH..HEAD' en $repo_path."
                echo "   Si el cambio es intencional, va en maralva-custom, no aquí."
                cd - > /dev/null || return 1
                return 2
            fi
        fi

        echo "--- Subiendo $repo_name ---"
        # Push forzado (con seguro): update_oca_upstream.sh puede haber descartado
        # commits que tu fork todavía tiene (reset --hard a upstream), así que un push
        # normal (fast-forward) fallaría aquí. --force-with-lease reescribe tu fork
        # para que quede igual que tu copia local, pero aborta si alguien más ha
        # tocado el fork entre medias (a diferencia de --force a secas).
        if git push --force-with-lease origin "$BRANCH"; then
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
REPOS_BLOQUEADOS=()

ejecutar_update_repo() {
    local repo_path=$1
    local repo_name
    repo_name=$(basename "$repo_path")
    update_repo "$repo_path"
    local resultado=$?
    if [ "$resultado" -eq 2 ]; then
        REPOS_BLOQUEADOS+=("$repo_name")
    elif [ "$resultado" -ne 0 ]; then
        exit 1
    fi
}

# Core
ejecutar_update_repo "$DIR_CORE"

# Repos OCA
while IFS= read -r repo || [ -n "$repo" ]; do
    [[ -z "$repo" || "$repo" =~ ^# ]] && continue
    TARGET_DIR="$DIR_OCA/${repo}"
    ejecutar_update_repo "$TARGET_DIR"
done < "$LISTA_REPOS"

if [ ${#REPOS_BLOQUEADOS[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Repos NO subidos por tener cambios ajenos a OCA: ${REPOS_BLOQUEADOS[*]}"
    echo "    Revísalos antes de decidir qué hacer (no se han tocado ni descartado, solo no se han subido)."
fi

echo "✅ Proceso completado. Tus forks en GitHub están sincronizados con este servidor (salvo los bloqueados, si los hay)."