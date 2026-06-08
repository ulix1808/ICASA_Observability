#!/bin/bash
# install-nginx-proxy.sh — Instala Nginx reverse proxy en RHEL 9 (DMZ)
# Uso: sudo ./scripts/install-nginx-proxy.sh
#
# Genera automáticamente los archivos de configuración si no existen.
# Pregunta hosts de AppDynamics y Splunk (Enter = valor por defecto).
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
    echo "Variables cargadas desde .env"
fi

# 1. Instalar paquetes
echo ""
echo "[1/6] Instalando Nginx..."
dnf install -y nginx openssl firewalld

# 2. Crear directorio SSL
echo ""
echo "[2/6] Configurando SSL..."
mkdir -p /etc/nginx/ssl

if [[ ! -f /etc/nginx/ssl/proxy.crt ]]; then
    echo "  No se encontró certificado. Generando autofirmado DEV..."
    PROXY_FQDN="${PROXY_FQDN:-appd-proxy.icasa.local}" \
        "$SCRIPT_DIR/generate-certs-selfsigned.sh"
fi

# 3. Generar configuración Nginx (interactivo o desde .env)
echo ""
echo "[3/6] Generando configuración Nginx..."
"$SCRIPT_DIR/generate-nginx-configs.sh"

# 4. Deshabilitar server por defecto en puerto 80 (evita conflicto)
echo ""
echo "[4/6] Ajustando configuración por defecto..."
if [[ -f /etc/nginx/nginx.conf ]]; then
    if grep -q "listen.*80 default_server" /etc/nginx/nginx.conf 2>/dev/null; then
        sed -i 's/^\(\s*listen\s\+80\s\+default_server;\)/    # \1 # deshabilitado por ICASA/' /etc/nginx/nginx.conf || true
    fi
fi

# 5. Validar configuración
echo ""
echo "[5/6] Validando configuración..."
nginx -t

# 6. Iniciar servicio
echo ""
echo "[6/6] Iniciando Nginx..."
systemctl enable nginx
systemctl restart nginx

# Firewall local
firewall-cmd --permanent --add-service=https 2>/dev/null || true
firewall-cmd --permanent --add-port=8443/tcp 2>/dev/null || true
firewall-cmd --permanent --add-port=8444/tcp 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true

echo ""
echo "=== Instalación completada ==="
echo ""
echo "Puertos activos esperados:"
ss -tlnp | grep nginx || true
echo ""
echo "Health check:"
echo "  curl -k https://localhost/health"
echo ""
echo "Regenerar solo configs (sin reinstalar):"
echo "  sudo ./scripts/generate-nginx-configs.sh"
echo "  sudo nginx -t && sudo systemctl reload nginx"
echo ""
echo "Reinicio completo:"
echo "  sudo systemctl restart nginx"
