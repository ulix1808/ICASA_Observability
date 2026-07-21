#!/bin/bash
# Levanta el laboratorio y ejecuta la demostración
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"
cd "$LAB_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== ICASA Lab — Doble proxy + certificados TLS ===${NC}"
echo ""

# 1. Certificados
if [[ ! -f certs/ca.crt || ! -f certs/proxy.crt ]]; then
    echo -e "${YELLOW}Generando certificados de laboratorio...${NC}"
    chmod +x scripts/generate-lab-certs.sh
    ./scripts/generate-lab-certs.sh
else
    echo "Certificados existentes en lab/certs/"
fi

# 2. Build
echo ""
echo -e "${YELLOW}Construyendo imágenes Docker...${NC}"
docker compose build --quiet

# 3. Levantar servicios
echo ""
echo -e "${YELLOW}Iniciando servicios (mock-saas, reverse-proxy, forward-proxy)...${NC}"
docker compose up -d mock-saas reverse-proxy forward-proxy

# Esperar a que Nginx y Squid estén listos
sleep 3

# 4. Ejecutar pruebas
echo ""
echo -e "${YELLOW}Ejecutando demostración desde contenedor cliente...${NC}"
docker compose run --rm client

echo ""
echo -e "${GREEN}Servicios siguen corriendo. Para detener:${NC}"
echo "  cd lab && docker compose down"
echo ""
echo -e "${GREEN}Ver logs de Squid durante pruebas manuales:${NC}"
echo "  docker compose logs -f forward-proxy"
