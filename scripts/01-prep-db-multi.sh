#!/bin/bash
set -e
# Reutilizamos tu lógica de usuario y dependencias
REAL_USER=${SUDO_USER:-$USER}
sudo id -u odoo &>/dev/null || sudo adduser --system --quiet --shell=/bin/bash --home /opt/odoo --group odoo

echo "--- Instalando dependencias del sistema ---"
sudo apt update && sudo apt install -y git postgresql python3-venv python3-dev build-essential libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev libssl-dev libpq-dev libjpeg-dev nginx

echo "--- Configurando PostgreSQL ---"
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='odoo'" | grep -q 1; then
    sudo -u postgres createuser -s odoo
fi

# Establecemos la contraseña para que pgAdmin no proteste
sudo -u postgres psql -c "ALTER USER odoo WITH PASSWORD 'odoo';"

echo "--- Habilitando conexiones externas para PgAdmin ---"

# 1. Detectar versión de Postgres instalada
PG_VER=$(psql --version | grep -P -o '\d+(?=\.\d+)' | head -1)
PG_CONF="/etc/postgresql/$PG_VER/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VER/main/pg_hba.conf"

# 2. Permitir que escuche en todas las interfaces (listen_addresses)
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

# 3. Añadir permiso a tu rango de red local en pg_hba.conf
# Ajustamos para que acepte cualquier IP de tu red doméstica (192.168.1.x)
if ! sudogrep -q "0.0.0.0/0" "$PG_HBA"; then
    echo "host    all             all             0.0.0.0/0               trust" | sudo tee -a "$PG_HBA"
fi

echo "--- Habilitando extensión unaccent en PostgreSQL ---"

# 1. Habilitar en template1 para que cualquier base de datos NUEVA la tenga por defecto
sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS unaccent;"

# 2. Habilitar en tu base de datos actual (maralva18)
# Cambia 'maralva18' por el nombre de tu BD si es distinto
IF_DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='maralva18'")
if [ "$IF_DB_EXISTS" = "1" ]; then
    sudo -u postgres psql -d maralva18 -c "CREATE EXTENSION IF NOT EXISTS unaccent;"
    echo "Unaccent habilitado en maralva18"
fi

# 4. Reiniciar para aplicar cambios
sudo systemctl restart postgresql

# 5. Paquetes para python3
# Actualizar repositorios
sudo apt-get update

# Instalar dependencias de Odoo 18
sudo apt-get install -y \
    build-essential python3-dev python3-venv python3-wheel \
    libxslt1-dev libxml2-dev libzip-dev libldap2-dev libsasl2-dev \
    libffi-dev pkg-config libpq-dev libjpeg-dev zlib1g-dev \
    libwebp-dev liblcms2-dev libtiff5-dev libcairo2-dev \
    libgirepository1.0-dev libfreetype6-dev libharfbuzz-dev \
    libfribidi-dev libxcb1-dev fonts-dejavu-core fonts-freefont-ttf \
    libssl-dev node-less npm python3-pip
