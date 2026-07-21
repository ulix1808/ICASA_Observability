#!/bin/bash
# Demostración interactiva: certificados de dominio + doble proxy
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROXY="http://forward-proxy:3128"
CA="/certs/ca.crt"
HOSTNAME="appd-proxy.icasa.local"
REVERSE_IP="$(getent hosts reverse-proxy | awk '{print $1}')"

section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; }
info() { echo -e "${YELLOW}→ $1${NC}"; }

run_curl() {
    # shellcheck disable=SC2068
    curl -sS -w "\nHTTP_CODE:%{http_code}\n" "$@" 2>&1
}

section "Laboratorio ICASA — Doble proxy + TLS por dominio"
echo "Hostname del certificado: ${HOSTNAME}"
echo "IP del reverse proxy:     ${REVERSE_IP}"
echo "Forward proxy (Squid):    forward-proxy:3128"
echo ""
info "El certificado del lab tiene SAN solo para el dominio (sin IP)."
info "Esto replica el escenario real donde conectar por IP falla."

# ── Test 1: HTTP plano al puerto 443 ──────────────────────────────────────
section "Test 1 — HTTP plano al puerto 443 (INCORRECTO)"
info "Equivalente a: curl http://10.250.5.12:443"
info "Nginx espera TLS; recibe HTTP → 400 Bad Request"
echo ""
OUTPUT=$(run_curl "http://${REVERSE_IP}:443/health" || true)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "HTTP_CODE:400"; then
    ok "Resultado esperado: 400 Bad Request (protocolo incorrecto)"
else
    fail "Se esperaba HTTP 400"
fi

# ── Test 2: HTTPS por IP con CA confiable ─────────────────────────────────
section "Test 2 — HTTPS por IP con CA instalada (INCORRECTO para TLS)"
info "Equivalente a: controller host=10.250.5.12 en el .NET Agent"
info "La CA es confiable, pero el certificado es para '${HOSTNAME}', no para la IP"
echo ""
set +e
OUTPUT=$(curl -sS --cacert "$CA" "https://${REVERSE_IP}/health" 2>&1)
RC=$?
set -e
echo "$OUTPUT"
if [[ $RC -ne 0 ]] && echo "$OUTPUT" | grep -qiE "subject name|hostname|certificate"; then
    ok "Resultado esperado: fallo por hostname mismatch (cert ≠ IP)"
else
    fail "Se esperaba error de validación de hostname"
fi

# ── Test 3: HTTPS por dominio directo ────────────────────────────────────
section "Test 3 — HTTPS por dominio directo (válido TLS, sin Squid)"
info "Equivalente a: Invoke-WebRequest https://appd-proxy.icasa.local"
info "En ICASA puede fallar por firewall; aquí demuestra que el certificado SÍ funciona con el FQDN"
echo ""
OUTPUT=$(run_curl --cacert "$CA" "https://${HOSTNAME}/health")
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "HTTP_CODE:200"; then
    ok "Resultado esperado: 200 OK — el certificado coincide con el hostname"
else
    fail "Se esperaba HTTP 200"
fi

# ── Test 4: HTTPS por dominio vía Squid (camino del agente) ───────────────
section "Test 4 — HTTPS por dominio vía Squid (CORRECTO — camino del agente)"
info "Equivalente a: .NET Agent con Server=${HOSTNAME}, Proxy=10.2.32.179:3128"
info "Squid abre túnel CONNECT; el cliente valida TLS contra el dominio"
echo ""
OUTPUT=$(run_curl -x "$PROXY" --cacert "$CA" "https://${HOSTNAME}/health")
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "HTTP_CODE:200"; then
    ok "Resultado esperado: 200 OK — configuración correcta del agente"
else
    fail "Se esperaba HTTP 200 vía proxy"
fi

# ── Test 5: HTTPS por IP vía Squid ────────────────────────────────────────
section "Test 5 — HTTPS por IP vía Squid (INCORRECTO)"
info "Aunque Squid conecte al destino, el cliente valida el cert contra la IP usada en la URL"
info "Squid también puede rechazar CONNECT por IP si el ACL solo permite el dominio (403)"
echo ""
set +e
OUTPUT=$(curl -sS -x "$PROXY" --cacert "$CA" "https://${REVERSE_IP}/health" 2>&1)
RC=$?
set -e
echo "$OUTPUT"
if [[ $RC -ne 0 ]] && echo "$OUTPUT" | grep -qiE "subject name|hostname|certificate"; then
    ok "Resultado esperado: fallo por hostname mismatch incluso vía proxy"
elif [[ $RC -ne 0 ]] && echo "$OUTPUT" | grep -qiE "403|CONNECT tunnel failed|denied"; then
    ok "Resultado esperado: Squid rechaza CONNECT por IP (ACL solo permite el dominio)"
else
    fail "Se esperaba error de hostname o rechazo del proxy"
fi

# ── Test 6: Sin CA instalada ─────────────────────────────────────────────
section "Test 6 — HTTPS sin CA de confianza (INCORRECTO)"
info "Equivalente a: no importar ICASA-Dev-CA en Trusted Root"
echo ""
set +e
OUTPUT=$(curl -sS -x "$PROXY" "https://${HOSTNAME}/health" 2>&1)
RC=$?
set -e
echo "$OUTPUT"
if [[ $RC -ne 0 ]] && echo "$OUTPUT" | grep -qiE "unable to get local issuer|certificate"; then
    ok "Resultado esperado: fallo por CA no confiable"
else
    fail "Se esperaba error de CA no confiable"
fi

# ── Test 7: Endpoint del Controller mock ──────────────────────────────────
section "Test 7 — Flujo completo hasta mock SaaS"
info "GET /controller/ vía Squid → Nginx → mock AppDynamics"
echo ""
OUTPUT=$(run_curl -x "$PROXY" --cacert "$CA" "https://${HOSTNAME}/controller/")
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "mock-appd-saas"; then
    ok "Resultado esperado: respuesta del mock Controller"
else
    fail "No se recibió respuesta del mock SaaS"
fi

# ── Resumen ───────────────────────────────────────────────────────────────
section "Resumen — qué configurar en ICASA"
cat << EOF

  Campo .NET Agent          Valor correcto
  ─────────────────────────────────────────────────────
  Server (Controller)       appd-proxy.icasa.local   ← NO la IP
  Port                      443
  SSL / TLS 1.2             habilitados
  Use proxy                 sí
  Proxy                     10.2.32.179:3128         ← Squid, NO Nginx
  CA en Trusted Root        ICASA-Dev-CA (ca.crt)

  Requisitos de red:
  • DNS: appd-proxy.icasa.local → 10.250.5.12 (hosts o DNS interno)
  • Squid: permitir CONNECT a appd-proxy.icasa.local:443
  • Squid: sin SSL Bump hacia el reverse proxy

EOF
ok "Laboratorio completado"
