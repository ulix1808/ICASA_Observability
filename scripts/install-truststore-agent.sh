#!/bin/bash
# install-truststore-agent.sh — Importa CA en Java truststore del agente
# Uso: sudo ./scripts/install-truststore-agent.sh --ca-cert /path/ca.crt --agent-home /opt/appdynamics/db-agent
set -euo pipefail

CA_CERT=""
AGENT_HOME="/opt/appdynamics/db-agent"
STORE_PASS="changeit"

while [[ $# -gt 0 ]]; do
    case $1 in
        --ca-cert) CA_CERT="$2"; shift 2 ;;
        --agent-home) AGENT_HOME="$2"; shift 2 ;;
        *) echo "Uso: $0 --ca-cert /path/ca.crt [--agent-home /opt/appdynamics/db-agent]"; exit 1 ;;
    esac
done

if [[ -z "$CA_CERT" || ! -f "$CA_CERT" ]]; then
    echo "Error: no se encontró el archivo CA: ${CA_CERT:-'(no especificado)'}"
    echo ""
    echo "¿De dónde sale este certificado?"
    echo "  Es la CA raíz que genera el PROXY al crear certs autofirmados."
    echo "  Se crea al ejecutar en el proxy (10.250.5.12):"
    echo "    sudo ./scripts/generate-certs-selfsigned.sh"
    echo ""
    echo "  Archivo en el proxy: /etc/nginx/ssl/ca.crt"
    echo ""
    echo "Cópielo al servidor del agente (MONITOR 10.2.32.179):"
    echo "  sudo ./scripts/fetch-proxy-ca.sh"
    echo "  # o: scp root@10.250.5.12:/etc/nginx/ssl/ca.crt /etc/pki/tls/certs/icasa-ca.crt"
    echo ""
    echo "Luego ejecute de nuevo este script con --ca-cert apuntando al archivo copiado."
    exit 1
fi

TRUSTSTORE="$AGENT_HOME/conf/truststore.jks"
mkdir -p "$AGENT_HOME/conf"

if [[ ! -f "$TRUSTSTORE" ]]; then
    keytool -genkey -noprompt \
        -alias placeholder -dname "CN=placeholder" \
        -keystore "$TRUSTSTORE" -storepass "$STORE_PASS" \
        -keypass "$STORE_PASS" -keyalg RSA
    keytool -delete -alias placeholder -keystore "$TRUSTSTORE" -storepass "$STORE_PASS" 2>/dev/null || true
fi

keytool -importcert -noprompt \
    -alias icasa-ca \
    -file "$CA_CERT" \
    -keystore "$TRUSTSTORE" \
    -storepass "$STORE_PASS"

echo "CA importada en $TRUSTSTORE"
echo "Verificar: keytool -list -keystore $TRUSTSTORE -storepass $STORE_PASS | grep icasa"
