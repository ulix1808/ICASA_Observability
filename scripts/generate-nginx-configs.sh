#!/bin/bash
# generate-nginx-configs.sh — Genera configs Nginx en /etc/nginx/conf.d/
# Uso: sudo ./scripts/generate-nginx-configs.sh
# También invocado desde install-nginx-proxy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"

# Cargar .env si existe (valores por defecto)
if [[ -f "$REPO_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_DIR/.env"
    set +a
fi

DEFAULT_APPD_HOST="${APPD_CONTROLLER_HOST:-teresa202606020142139.saas.appdynamics.com}"
DEFAULT_ANALYTICS_HOST="${APPD_ANALYTICS_HOST:-analytics.api.appdynamics.com}"
DEFAULT_SPLUNK_HOST="${SPLUNK_CLOUD_HOST:-input-prd-pendiente.splunkcloud.com}"
DEFAULT_PROXY_IP="${PROXY_HOST:-10.250.5.12}"
DEFAULT_PROXY_FQDN="${PROXY_FQDN:-appd-proxy.icasa.local}"

prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local input=""

    if [[ -t 0 ]] || [[ -c /dev/tty ]]; then
        read -r -p "$prompt_text [$default_value]: " input </dev/tty
    fi

    if [[ -z "$input" ]]; then
        echo "$default_value"
    else
        echo "$input"
    fi
}

echo "=== Generación de configuración Nginx ==="
echo "Presione Enter para aceptar el valor entre corchetes."
echo ""

APPD_HOST=$(prompt_with_default "Host AppDynamics Controller (SaaS)" "$DEFAULT_APPD_HOST")
ANALYTICS_HOST=$(prompt_with_default "Host Analytics Events API (SAP)" "$DEFAULT_ANALYTICS_HOST")
SPLUNK_HOST=$(prompt_with_default "Host Splunk Cloud (HEC)" "$DEFAULT_SPLUNK_HOST")
PROXY_IP=$(prompt_with_default "IP del proxy en DMZ" "$DEFAULT_PROXY_IP")
PROXY_FQDN=$(prompt_with_default "FQDN del proxy (opcional)" "$DEFAULT_PROXY_FQDN")

mkdir -p "$OUTPUT_DIR"

cat > "$OUTPUT_DIR/appdynamics-upstream.conf" << EOF
# Generado por generate-nginx-configs.sh — $(date -Iseconds)
# AppDynamics SaaS — Reverse Proxy

upstream appd_controller {
    server ${APPD_HOST}:443;
    keepalive 32;
}

upstream appd_analytics {
    server ${ANALYTICS_HOST}:443;
    keepalive 16;
}

server {
    listen 443 ssl default_server;
    server_name ${PROXY_IP} ${PROXY_FQDN} localhost;

    ssl_certificate     /etc/nginx/ssl/proxy.crt;
    ssl_certificate_key /etc/nginx/ssl/proxy.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }

    location / {
        proxy_pass              https://appd_controller;
        proxy_ssl_server_name   on;
        proxy_ssl_name          ${APPD_HOST};
        proxy_ssl_verify        on;
        proxy_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;

        proxy_set_header        Host ${APPD_HOST};
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto https;

        proxy_connect_timeout   30s;
        proxy_send_timeout      60s;
        proxy_read_timeout      60s;
        proxy_http_version      1.1;
        proxy_set_header        Connection "";
    }
}

server {
    listen 8443 ssl;
    server_name ${PROXY_IP} ${PROXY_FQDN};

    ssl_certificate     /etc/nginx/ssl/proxy.crt;
    ssl_certificate_key /etc/nginx/ssl/proxy.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location / {
        proxy_pass              https://appd_analytics;
        proxy_ssl_server_name   on;
        proxy_ssl_name          ${ANALYTICS_HOST};
        proxy_ssl_verify        on;
        proxy_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;

        proxy_set_header        Host ${ANALYTICS_HOST};
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto https;
    }
}
EOF

cat > "$OUTPUT_DIR/splunk-upstream.conf" << EOF
# Generado por generate-nginx-configs.sh — $(date -Iseconds)
# Splunk Cloud — Reverse Proxy

upstream splunk_cloud {
    server ${SPLUNK_HOST}:443;
    keepalive 16;
}

server {
    listen 8444 ssl;
    server_name ${PROXY_IP} splunk-proxy.icasa.local;

    ssl_certificate     /etc/nginx/ssl/proxy.crt;
    ssl_certificate_key /etc/nginx/ssl/proxy.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location /services/collector {
        proxy_pass              https://splunk_cloud;
        proxy_ssl_server_name   on;
        proxy_ssl_verify        on;
        proxy_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;

        proxy_set_header        Host ${SPLUNK_HOST};
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto https;
        proxy_pass_request_headers on;
    }

    location / {
        proxy_pass              https://splunk_cloud;
        proxy_ssl_server_name   on;
        proxy_ssl_verify        on;
        proxy_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;

        proxy_set_header        Host ${SPLUNK_HOST};
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto https;
    }
}
EOF

echo ""
echo "Archivos generados en $OUTPUT_DIR:"
echo "  - appdynamics-upstream.conf  (AppDynamics: ${APPD_HOST})"
echo "  - splunk-upstream.conf       (Splunk: ${SPLUNK_HOST})"
echo ""
echo "Validar: sudo nginx -t"
echo "Aplicar: sudo systemctl reload nginx"
