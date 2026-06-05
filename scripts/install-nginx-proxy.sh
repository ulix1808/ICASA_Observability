#!/bin/bash
# install-nginx-proxy.sh — Instala Nginx reverse proxy en RHEL 9 (DMZ)
# Uso: sudo ./scripts/install-nginx-proxy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== ICASA Observability — Instalación Nginx Proxy ==="

# Cargar variables si existe .env
if [[ -f "$REPO_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_DIR/.env"
    set +a
fi

# 1. Instalar paquetes
echo "[1/5] Instalando Nginx..."
dnf install -y nginx openssl firewalld

# 2. Crear directorio SSL
echo "[2/5] Configurando SSL..."
mkdir -p /etc/nginx/ssl

if [[ ! -f /etc/nginx/ssl/proxy.crt ]]; then
    echo "  No se encontró certificado. Generando autofirmado DEV..."
    "$SCRIPT_DIR/generate-certs-selfsigned.sh"
fi

# 3. Copiar configs
echo "[3/5] Copiando configuración Nginx..."
cp "$REPO_DIR/configs/nginx/appdynamics-upstream.conf" /etc/nginx/conf.d/
cp "$REPO_DIR/configs/nginx/splunk-upstream.conf" /etc/nginx/conf.d/

# 4. Validar y reiniciar
echo "[4/5] Validando configuración..."
nginx -t

echo "[5/5] Iniciando Nginx..."
systemctl enable nginx
systemctl restart nginx

# Firewall local
firewall-cmd --permanent --add-service=https 2>/dev/null || true
firewall-cmd --permanent --add-port=8443/tcp 2>/dev/null || true
firewall-cmd --permanent --add-port=8444/tcp 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true

echo ""
echo "=== Instalación completada ==="
echo "Health check: curl -k https://localhost/health"
echo "Verificar upstream: curl -s https://teresa202606020142139.saas.appdynamics.com/controller/rest/serverstatus"
