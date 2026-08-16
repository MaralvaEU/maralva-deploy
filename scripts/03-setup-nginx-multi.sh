#!/bin/bash
# Variables necesarias heredadas del lanzador: BRANCH_CLEAN (180), BRANCH_DOMAIN (18), DOMAIN, ODOO_PORT, ODOO_CHAT_PORT
NGINX_CONF="/etc/nginx/sites-available/odoo$BRANCH_CLEAN"

echo "--- Configurando Nginx para rama $BRANCH ($DOMAIN) ---"

# 1. Limpieza de seguridad para evitar duplicados
sudo rm -f /etc/nginx/sites-enabled/default
# Borramos el enlace anterior antes de generar el nuevo para evitar el error de "duplicate upstream"
sudo rm -f "/etc/nginx/sites-enabled/odoo$BRANCH_CLEAN"

# 2. Generación del archivo con la sintaxis corregida
sudo bash -c "cat > $NGINX_CONF <<EOF
upstream odoo_backend_$BRANCH_CLEAN {
    server 127.0.0.1:$ODOO_PORT;
}
upstream odoo_chat_$BRANCH_CLEAN {
    server 127.0.0.1:$ODOO_CHAT_PORT;
}

server {
    listen 80;
    server_name maralva$BRANCH_DOMAIN.$DOMAIN *.maralva$BRANCH_DOMAIN.$DOMAIN;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    client_max_body_size 128M;

    # Logs específicos por instancia
    access_log /var/log/nginx/odoo${BRANCH_CLEAN}_access.log;
    error_log /var/log/nginx/odoo${BRANCH_CLEAN}_error.log;

    location /longpolling {
        proxy_pass http://odoo_chat_$BRANCH_CLEAN;
    }

    location / {
        proxy_set_header X-Forwarded-Host \\\$host;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_pass http://odoo_backend_$BRANCH_CLEAN;
    }
}
EOF"

# 3. Habilitar y reiniciar
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
if sudo nginx -t; then
    sudo systemctl restart nginx
    echo "✅ Nginx configurado para maralva$BRANCH_DOMAIN.$DOMAIN"
else
    echo "❌ Error en el test de Nginx. Revisa el archivo $NGINX_CONF"
    exit 1
fi