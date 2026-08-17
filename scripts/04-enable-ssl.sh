#!/bin/bash
# --- Maralva Deploy: activar HTTPS sobre el vhost ya generado por 03-setup-nginx.sh ---
#
# Paso manual y aparte del resto de la instalación: comprueba que el dominio de esta
# instancia ya tiene certificado emitido (con maralva-ops/certs/setup-ssl-duckdns.sh)
# antes de tocar nada. Si no lo encuentra, avisa y no modifica el nginx actual —
# certificar no siempre es necesario ni posible para toda instancia.
set -e

read -p "Dominio de esta instancia (ej. maralva.eu): " DOMAIN
[ -z "$DOMAIN" ] && { echo "Error: Dominio obligatorio"; exit 1; }

NGINX_CONF="/etc/nginx/sites-available/odoo"
CERT_APEX="/etc/letsencrypt/live/$DOMAIN"
CERT_WILDCARD="/etc/letsencrypt/live/wildcard.$DOMAIN"

echo "--- Comprobando certificados para $DOMAIN ---"
if ! sudo test -f "$CERT_APEX/fullchain.pem" || ! sudo test -f "$CERT_WILDCARD/fullchain.pem"; then
    echo "❌ No se encuentra certificado válido para $DOMAIN." >&2
    echo "   Esperaba: $CERT_APEX/fullchain.pem" >&2
    echo "   y:        $CERT_WILDCARD/fullchain.pem" >&2
    echo "   Ejecuta primero maralva-ops/certs/setup-ssl-duckdns.sh con el dominio '$DOMAIN' y vuelve a lanzar este script." >&2
    exit 1
fi
echo "✅ Certificados encontrados."

if [ ! -f "$NGINX_CONF" ]; then
    echo "Error: no existe $NGINX_CONF. Ejecuta primero 03-setup-nginx.sh para esta instancia." >&2
    exit 1
fi

read -p "Puerto HTTP de Odoo: " ODOO_PORT
[ -z "$ODOO_PORT" ] && { echo "Error: Puerto HTTP obligatorio"; exit 1; }
read -p "Puerto Longpolling/Gevent de Odoo: " ODOO_CHAT_PORT
[ -z "$ODOO_CHAT_PORT" ] && { echo "Error: Puerto Longpolling/Gevent obligatorio"; exit 1; }

echo "--- Regenerando $NGINX_CONF con HTTPS ---"
sudo bash -c "cat > $NGINX_CONF <<EOF
upstream odoo_backend {
    server 127.0.0.1:$ODOO_PORT;
}
upstream odoo_chat {
    server 127.0.0.1:$ODOO_CHAT_PORT;
}

# Redirección HTTP -> HTTPS
server {
    listen 80;
    server_name $DOMAIN *.$DOMAIN;
    return 301 https://\\\$host\\\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate $CERT_APEX/fullchain.pem;
    ssl_certificate_key $CERT_APEX/privkey.pem;

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

server {
    listen 443 ssl;
    server_name *.$DOMAIN;
    ssl_certificate $CERT_WILDCARD/fullchain.pem;
    ssl_certificate_key $CERT_WILDCARD/privkey.pem;

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

if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "✅ HTTPS activado para $DOMAIN (y *.$DOMAIN)."
else
    echo "❌ Error en el test de Nginx. Revisa $NGINX_CONF" >&2
    exit 1
fi
