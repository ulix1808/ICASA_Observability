#!/bin/bash
# install-sc4snmp.sh — Instala Splunk Connect for SNMP en RHEL 9
# Uso: sudo ./scripts/install-sc4snmp.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="/opt/sc4snmp"

echo "=== ICASA — Instalación SC4SNMP ==="

# 1. Docker
echo "[1/4] Instalando Docker..."
if ! command -v docker &>/dev/null; then
    dnf install -y docker docker-compose-plugin
    systemctl enable --now docker
fi

# 2. Directorio
echo "[2/4] Preparando directorio..."
mkdir -p "$INSTALL_DIR"
cp "$REPO_DIR/configs/splunk/sc4snmp.env" "$INSTALL_DIR/.env"
cp "$REPO_DIR/configs/splunk/snmp.yaml" "$INSTALL_DIR/"

echo "[3/4] Descargar SC4SNMP manualmente desde:"
echo "  https://github.com/splunk/splunk-connect-for-snmp/releases"
echo "  Extraer en $INSTALL_DIR y ejecutar: docker compose up -d"

echo "[4/4] Configuración copiada."
echo ""
echo "  Editar $INSTALL_DIR/.env con HEC token real"
echo "  Editar $INSTALL_DIR/snmp.yaml con inventario de dispositivos"
echo "  Desplegar: cd $INSTALL_DIR && docker compose up -d"
