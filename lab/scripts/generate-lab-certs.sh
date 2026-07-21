#!/bin/bash
# Genera CA + certificado de laboratorio SOLO con SAN de dominio (sin IP).
# Demuestra por qué conectar por IP falla la validación TLS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="${LAB_DIR}/certs"
DAYS=365
CN="appd-proxy.icasa.local"
CA_CN="ICASA-Lab-CA"

mkdir -p "$CERTS_DIR"

echo "=== Generando certificados de laboratorio ==="
echo "CN proxy: $CN (solo DNS en SAN — sin IP)"
echo "Salida:   $CERTS_DIR"
echo ""

# CA raíz del laboratorio
openssl genrsa -out "$CERTS_DIR/ca.key" 4096 2>/dev/null
openssl req -x509 -new -nodes -key "$CERTS_DIR/ca.key" -sha256 -days "$DAYS" \
    -out "$CERTS_DIR/ca.crt" \
    -subj "/C=GT/O=ICASA/CN=${CA_CN}"

# Clave y CSR del reverse proxy
openssl genrsa -out "$CERTS_DIR/proxy.key" 2048 2>/dev/null
openssl req -new -key "$CERTS_DIR/proxy.key" \
    -out "$CERTS_DIR/proxy.csr" \
    -subj "/C=GT/O=ICASA/CN=${CN}"

# SAN solo con dominio — deliberadamente SIN IP para el ejercicio didáctico
cat > "$CERTS_DIR/proxy.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CN}
EOF

openssl x509 -req -in "$CERTS_DIR/proxy.csr" \
    -CA "$CERTS_DIR/ca.crt" -CAkey "$CERTS_DIR/ca.key" -CAcreateserial \
    -out "$CERTS_DIR/proxy.crt" -days "$DAYS" -sha256 \
    -extfile "$CERTS_DIR/proxy.ext"

chmod 600 "$CERTS_DIR"/*.key
chmod 644 "$CERTS_DIR"/*.crt

echo "Archivos generados:"
ls -la "$CERTS_DIR"
echo ""
echo "Verificar SAN (solo DNS, sin IP):"
openssl x509 -in "$CERTS_DIR/proxy.crt" -noout -text | grep -A2 "Subject Alternative Name"
echo ""
echo "Listo. Ejecutar: cd lab && ./scripts/run-demo.sh"
