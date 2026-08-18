#!/bin/bash
# --- Maralva Pack-Maker v2.0 (Data-Driven) ---
# Scaffoldea un módulo Odoo nuevo (README, icono, manifest con depends,
# datos de compañía ES/EUR, seguridad vacía) a partir de una lista de
# dependencias en config/.

REPO_ROOT=$(dirname "$(readlink -f "$0")")/..
read -p "Nombre técnico del módulo (ej: maralva_base_internal): " MOD_NAME
read -p "Versión de Odoo (ej: 18, también vale 18.0): " VERSION
read -p "Archivo de dependencias en config/ (ej: pack_maralva_base18.txt): " DEP_FILE

[ -z "$MOD_NAME" ] && { echo "❌ Error: el nombre técnico del módulo es obligatorio"; exit 1; }
[ -z "$VERSION" ] && { echo "❌ Error: la versión de Odoo es obligatoria"; exit 1; }
[ -z "$DEP_FILE" ] && { echo "❌ Error: el archivo de dependencias es obligatorio"; exit 1; }

# Nombre técnico válido como módulo Python/Odoo: minúsculas, dígitos y "_", sin
# empezar por número (si no, Odoo ni lo reconocería como addon).
if [[ ! "$MOD_NAME" =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo "❌ Error: '$MOD_NAME' no es un nombre técnico válido (usa minúsculas, dígitos y guión bajo, sin empezar por número)"
    exit 1
fi

# Normalizamos "18.0" -> "18" para que siempre coincida con /opt/odoo/<versión>
# que genera 02-odoo-setup-multi.sh (que usa BRANCH_DOMAIN, solo el número).
VERSION=$(echo "$VERSION" | cut -d. -f1)

LISTA_DEP="$REPO_ROOT/config/$DEP_FILE"

if [ ! -f "$LISTA_DEP" ]; then
    echo "❌ Error: No se encuentra $LISTA_DEP"
    exit 1
fi

# 1. Preparar lista para Python: quita comentarios (# a final de línea o línea
# completa), recorta espacios solo en los extremos y descarta líneas vacías.
DEPENDS_PYTHON=$(sed \
    -e 's/#.*//' \
    -e 's/^[[:space:]]*//' \
    -e 's/[[:space:]]*$//' \
    -e '/^$/d' \
    -e "s/.*/        '&',/" \
    "$LISTA_DEP")

TARGET_DIR="/opt/odoo/$VERSION/maralva-custom/$MOD_NAME"

if [ -d "$TARGET_DIR" ]; then
    echo "❌ Error: $TARGET_DIR ya existe — elige otro nombre o bórralo a mano si quieres regenerarlo."
    exit 1
fi

echo "--- Generando Pack: $MOD_NAME (Odoo $VERSION) desde $DEP_FILE ---"

# 2. Crear estructura completa
mkdir -p "$TARGET_DIR"/{models,views,security,data,i18n,doc,static/description}
# Copiar el logo de la plantilla al icono del módulo
if [ -f "$REPO_ROOT/templates/logo_maralva_300.png" ]; then
    cp "$REPO_ROOT/templates/logo_maralva_300.png" "$TARGET_DIR/static/description/icon.png"
    echo "🎨 Icono Maralva inyectado en el módulo."
fi
echo "from . import models" > "$TARGET_DIR/__init__.py"
touch "$TARGET_DIR/models/__init__.py"

# 3. GENERAR README.md (¡Recuperado!)
cat > "$TARGET_DIR/README.md" <<EOF
# Maralva Pack - ${MOD_NAME//_/ }

## Descripción
Pack generado automáticamente para Odoo $VERSION.
Configuración basada en: $DEP_FILE

## Contenido
- Localización española (ES/EUR).
- Selección de módulos OCA y Core según estrategia Maralva.

---
*Fábrica de Software Maralva*
EOF

# 4. Generar __manifest__.py (Con tus 80 módulos inyectados)
cat > "$TARGET_DIR/__manifest__.py" <<EOF
{
    'name': 'Maralva Pack - ${MOD_NAME//_/ }',
    'version': '$VERSION.0.1.0.0',
    'summary': 'Pack maestro Maralva para $VERSION',
    'author': 'Maralva',
    'license': 'AGPL-3',
    'depends': [
$DEPENDS_PYTHON
    ],
    'data': [
        'security/ir.model.access.csv',
        'data/res_company_data.xml',
    ],
    'installable': True,
    'application': True,
}
EOF

# 5. XML de España/EUR y Seguridad
cat > "$TARGET_DIR/data/res_company_data.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="base.main_company" model="res.company">
            <field name="country_id" ref="base.es"/>
            <field name="currency_id" ref="base.EUR"/>
        </record>
    </data>
</odoo>
EOF

echo "id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink" > "$TARGET_DIR/security/ir.model.access.csv"

echo "✅ Módulo generado en $TARGET_DIR"

# 6. Sincronización Git local (informativa: si algo falla aquí, el módulo ya
# está creado igualmente; solo avisamos, no lo damos por "éxito total" a ciegas)
CUSTOM_DIR="/opt/odoo/$VERSION/maralva-custom"
if [ ! -d "$CUSTOM_DIR/.git" ]; then
    echo "⚠️  $CUSTOM_DIR no es un repo git — no se ha commiteado nada. Hazlo a mano."
elif ! (cd "$CUSTOM_DIR" && git add "$MOD_NAME" && git commit -m "[ADD] $MOD_NAME: Generado desde $DEP_FILE"); then
    echo "⚠️  El módulo se creó bien, pero el commit en $CUSTOM_DIR falló (revisa el error de arriba —"
    echo "    por ejemplo, 'git config user.email'/'user.name' sin configurar en esta máquina)."
    echo "    Commitea a mano cuando lo arregles: cd $CUSTOM_DIR && git add $MOD_NAME && git commit -m '...'"
else
    echo "✅ Pack $MOD_NAME commiteado en $CUSTOM_DIR."
    echo "💡 Recuerda subir los cambios a GitHub desde tu PC o con tu script de push."
fi
