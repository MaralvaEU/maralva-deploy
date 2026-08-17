#!/bin/bash
# Variables necesarias heredadas del lanzador: DOMAIN, ODOO_PORT, ODOO_CHAT_PORT
# Instancia única: un solo vhost, sin sufijo de versión.
NGINX_CONF="/etc/nginx/sites-available/odoo"

echo "--- Configurando Nginx para $DOMAIN ---"

# 1. Limpieza de seguridad para evitar duplicados
sudo rm -f /etc/nginx/sites-enabled/default
# Borramos el enlace anterior antes de generar el nuevo para evitar el error de "duplicate upstream"
sudo rm -f "/etc/nginx/sites-enabled/odoo"

# 2. Generación del archivo con la sintaxis corregida
sudo bash -c "cat > $NGINX_CONF <<EOF
upstream odoo_backend {
    server 127.0.0.1:$ODOO_PORT;
}
upstream odoo_chat {
    server 127.0.0.1:$ODOO_CHAT_PORT;
}

server {
    listen 80;
    server_name $DOMAIN *.$DOMAIN;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    client_max_body_size 128M;

    access_log /var/log/nginx/odoo_access.log;
    error_log /var/log/nginx/odoo_error.log;

    location /longpolling {
        proxy_pass http://odoo_chat;
    }

    location / {
        proxy_set_header X-Forwarded-Host \\\$host;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_pass http://odoo_backend;
    }
}
EOF"

# 3. Habilitar y reiniciar
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
if sudo nginx -t; then
    sudo systemctl restart nginx
    echo "✅ Nginx configurado para $DOMAIN"
else
    echo "❌ Error en el test de Nginx. Revisa el archivo $NGINX_CONF"
    exit 1
fi
