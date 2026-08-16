#!/bin/bash
# --- Maralva Pack-Maker v2.0 (Data-Driven) ---

REPO_ROOT=$(dirname "$(readlink -f "$0")")/..
read -p "Nombre técnico del módulo (ej: maralva_base_internal): " MOD_NAME
read -p "Versión de Odoo (18 o 19): " VERSION
read -p "Archivo de dependencias en config/ (ej: pack_maralva.txt): " DEP_FILE

LISTA_DEP="$REPO_ROOT/config/$DEP_FILE"

if [ ! -f "$LISTA_DEP" ]; then
    echo "❌ Error: No se encuentra $LISTA_DEP"
    exit 1
fi

# 1. Preparar lista para Python (Limpia espacios y añade comillas/comas)
DEPENDS_PYTHON=$(sed -e 's/[[:space:]]*//g' -e '/^#/d' -e '/^$/d' -e "s/.*/        '&',/" "$LISTA_DEP")

TARGET_DIR="/opt/odoo/$VERSION/maralva-custom/$MOD_NAME"
echo "--- Generando Pack: $MOD_NAME (Odoo $VERSION) desde $DEP_FILE ---"

# 2. Crear estructura completa
mkdir -p "$TARGET_DIR"/{models,views,security,data,i18n,doc,static/description}
# Copiar el logo de la plantilla al icono del módulo
if [ -f "$REPO_ROOT/templates/logo_maralva_300.png" ]; then
    cp "$REPO_ROOT/templates/logo_maralva_300.png" "$TARGET_DIR/static/description/icon.png"
    echo "🎨 Icono Maralva inyectado en el módulo."
fi
touch "$TARGET_DIR/__init__.py"
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

# 6. Sincronización Git local
cd "/opt/odoo/$VERSION/maralva-custom"
git add "$MOD_NAME"
git commit -m "[ADD] $MOD_NAME: Generado desde $DEP_FILE"

echo "✅ Proceso finalizado. El módulo está listo en $TARGET_DIR"

echo "✅ Pack $MOD_NAME creado con éxito en Odoo $VERSION."
echo "💡 Recuerda subir los cambios a GitHub desde tu PC o con tu script de push."