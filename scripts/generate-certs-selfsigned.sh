#!/bin/bash
# generate-certs-selfsigned.sh — Genera CA + cert autofirmado para proxy DEV
# Uso: sudo ./scripts/generate-certs-selfsigned.sh
set -euo pipefail

SSL_DIR="/etc/nginx/ssl"
DAYS=365
CN="${PROXY_FQDN:-appd-proxy.icasa.local}"

echo "=== Generando certificados autofirmados DEV ==="
mkdir -p "$SSL_DIR"

# CA raíz
openssl genrsa -out "$SSL_DIR/ca.key" 4096
openssl req -x509 -new -nodes -key "$SSL_DIR/ca.key" -sha256 -days $DAYS \
    -out "$SSL_DIR/ca.crt" \
    -subj "/C=GT/O=ICASA/CN=ICASA-Dev-CA"

# Cert del proxy
openssl genrsa -out "$SSL_DIR/proxy.key" 2048
openssl req -new -key "$SSL_DIR/proxy.key" \
    -out "$SSL_DIR/proxy.csr" \
    -subj "/C=GT/O=ICASA/CN=$CN"

cat > "$SSL_DIR/proxy.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CN
DNS.2 = appd-proxy.icasa.local
DNS.3 = splunk-proxy.icasa.local
IP.1 = 10.250.5.12
EOF

openssl x509 -req -in "$SSL_DIR/proxy.csr" \
    -CA "$SSL_DIR/ca.crt" -CAkey "$SSL_DIR/ca.key" -CAcreateserial \
    -out "$SSL_DIR/proxy.crt" -days $DAYS -sha256 \
    -extfile "$SSL_DIR/proxy.ext"

chmod 600 "$SSL_DIR/proxy.key" "$SSL_DIR/ca.key"
chmod 644 "$SSL_DIR/proxy.crt" "$SSL_DIR/ca.crt"

# Copiar CA al path estándar RHEL
cp "$SSL_DIR/ca.crt" /etc/pki/tls/certs/icasa-ca.crt

echo ""
echo "=== Certificados generados en el PROXY ==="
echo "  CA raíz:        $SSL_DIR/ca.crt"
echo "  Cert proxy:     $SSL_DIR/proxy.crt"
echo "  Key proxy:      $SSL_DIR/proxy.key"
echo "  Copia local CA: /etc/pki/tls/certs/icasa-ca.crt"
echo ""
echo "=== IMPORTANTE: distribuir CA a servidores con agentes ==="
echo "El agente conecta al proxy por HTTPS. Debe confiar en esta CA."
echo ""
echo "Opción A — desde MONITOR (10.2.32.179) con SSH:"
echo "  sudo ./scripts/fetch-proxy-ca.sh"
echo "  sudo ./scripts/install-truststore-agent.sh --ca-cert /etc/pki/tls/certs/icasa-ca.crt --agent-home /opt/appdynamics/db-agent"
echo ""
echo "Opción B — copia manual (scp):"
echo "  scp root@10.250.5.12:${SSL_DIR}/ca.crt /etc/pki/tls/certs/icasa-ca.crt"
echo ""
echo "Opción C — ver contenido para pegar en archivo:"
echo "  sudo cat ${SSL_DIR}/ca.crt"
