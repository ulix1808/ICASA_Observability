#!/bin/bash
# fetch-proxy-ca.sh — Copia la CA del proxy autofirmado al servidor del agente
# Uso: sudo ./scripts/fetch-proxy-ca.sh
#
# Ejecutar en el servidor del agente (ej. MONITOR 10.2.32.179), NO en el proxy.
# Requiere que el proxy ya haya ejecutado generate-certs-selfsigned.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$REPO_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_DIR/.env"
    set +a
fi

PROXY_HOST="${PROXY_HOST:-10.250.5.12}"
PROXY_USER="${PROXY_SSH_USER:-root}"
CA_DEST="${CA_CERT_PATH:-/etc/pki/tls/certs/icasa-ca.crt}"
CA_SRC="/etc/nginx/ssl/ca.crt"

echo "=== Copiar CA del proxy al servidor agente ==="
echo "Origen:  ${PROXY_USER}@${PROXY_HOST}:${CA_SRC}"
echo "Destino: ${CA_DEST}"
echo ""

mkdir -p "$(dirname "$CA_DEST")"

if scp "${PROXY_USER}@${PROXY_HOST}:${CA_SRC}" "$CA_DEST"; then
    chmod 644 "$CA_DEST"
    echo ""
    echo "CA copiada correctamente."
    echo "Siguiente paso — importar en truststore del Database Agent:"
    echo "  sudo ./scripts/install-truststore-agent.sh \\"
    echo "    --ca-cert ${CA_DEST} \\"
    echo "    --agent-home /opt/appdynamics/db-agent"
else
    echo ""
    echo "Error al copiar. Alternativa manual:"
    echo "  1. En el PROXY (${PROXY_HOST}):"
    echo "     sudo cat ${CA_SRC}"
    echo "  2. En este servidor (MONITOR), guardar en ${CA_DEST}"
    echo ""
    echo "  O con USB/SFTP: copiar el archivo ${CA_SRC} del proxy."
    exit 1
fi
