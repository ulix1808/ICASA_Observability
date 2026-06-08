#!/bin/bash
# install-db-agent.sh — Instala AppDynamics Database Agent en RHEL 9
# Uso: sudo ./scripts/install-db-agent.sh /path/to/db-agent.zip
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DB_ZIP="${1:-}"

if [[ -f "$REPO_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_DIR/.env"
    set +a
fi

DB_AGENT_HOME="${DB_AGENT_HOME:-/opt/appdynamics/db-agent}"

echo "=== ICASA — Instalación Database Agent ==="

# 1. Java
echo "[1/6] Verificando Java..."
if ! java -version 2>&1 | grep -q "version"; then
    dnf install -y java-17-openjdk java-17-openjdk-devel
fi
java -version

# 2. Usuario
echo "[2/6] Creando usuario appdynamics..."
id appdynamics &>/dev/null || useradd -r -s /sbin/nologin appdynamics

# 3. Descomprimir agente
echo "[3/6] Instalando agente..."
mkdir -p /opt/appdynamics

if [[ -n "$DB_ZIP" && -f "$DB_ZIP" ]]; then
    unzip -o "$DB_ZIP" -d /opt/appdynamics/
    # Detectar directorio descomprimido
    EXTRACTED=$(find /opt/appdynamics -maxdepth 1 -type d -name "db-agent*" | head -1)
    if [[ -n "$EXTRACTED" && "$EXTRACTED" != "$DB_AGENT_HOME" ]]; then
        rm -rf "$DB_AGENT_HOME"
        mv "$EXTRACTED" "$DB_AGENT_HOME"
    fi
else
    echo "  AVISO: No se proporcionó ZIP. Descargar de accounts.appdynamics.com/downloads"
    echo "  Uso: sudo $0 /path/to/db-agent.zip"
    mkdir -p "$DB_AGENT_HOME/conf" "$DB_AGENT_HOME/logs"
fi

# 4. Configuración
echo "[4/6] Copiando configuración..."
cp "$REPO_DIR/configs/database-agent/controller-info.xml" "$DB_AGENT_HOME/conf/"

# Truststore — CA del proxy autofirmado
CA_CERT="${CA_CERT_PATH:-/etc/pki/tls/certs/icasa-ca.crt}"
echo "[4b/6] Configurando truststore TLS (CA del proxy)..."
if [[ -f "$CA_CERT" ]]; then
    "$SCRIPT_DIR/install-truststore-agent.sh" --ca-cert "$CA_CERT" --agent-home "$DB_AGENT_HOME"
else
    echo ""
    echo "  AVISO: No se encontró ${CA_CERT}"
    echo "  El Database Agent necesita la CA del proxy (certificado autofirmado)."
    echo ""
    echo "  1. En el PROXY (10.250.5.12) debe existir /etc/nginx/ssl/ca.crt"
    echo "     (se genera con: sudo ./scripts/generate-certs-selfsigned.sh)"
    echo "  2. Cópielo a este servidor:"
    echo "     sudo ./scripts/fetch-proxy-ca.sh"
    echo "  3. Importe en truststore:"
    echo "     sudo ./scripts/install-truststore-agent.sh --ca-cert ${CA_CERT} --agent-home ${DB_AGENT_HOME}"
    echo ""
fi

# 5. Permisos
chown -R appdynamics:appdynamics "$DB_AGENT_HOME"

# 6. Systemd
echo "[5/6] Instalando servicio systemd..."
cp "$REPO_DIR/configs/database-agent/db-agent.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable db-agent

echo "[6/6] Iniciando agente..."
systemctl start db-agent || echo "  AVISO: Verificar que db-agent.sh existe y Access Key está configurada"

echo ""
echo "=== Instalación completada ==="
echo "  Logs: tail -f $DB_AGENT_HOME/logs/agent.log"
echo "  Status: systemctl status db-agent"
echo "  IMPORTANTE: Editar $DB_AGENT_HOME/conf/controller-info.xml con Access Key real"
