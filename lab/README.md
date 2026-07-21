# Laboratorio — Doble proxy + certificados TLS

Demostración en contenedores del escenario ICASA: **Squid forward proxy → Nginx reverse proxy → AppDynamics SaaS**, con énfasis en por qué **HTTPS por IP falla** cuando el certificado está emitido para un **dominio**.

## Qué demuestra

| Test | Acción | Resultado esperado | Lección |
|------|--------|-------------------|---------|
| 1 | `http://IP:443` | 400 Bad Request | Usar HTTPS, no HTTP plano |
| 2 | `https://IP` + CA confiable | **Hostname mismatch** | El cert es para `appd-proxy.icasa.local`, no para la IP |
| 3 | `https://appd-proxy.icasa.local` directo | 200 OK | Con FQDN + CA, TLS funciona |
| 4 | `https://FQDN` vía Squid | 200 OK | **Configuración correcta del agente** |
| 5 | `https://IP` vía Squid | **403 o hostname mismatch** | Squid y/o TLS rechazan conexión por IP |
| 6 | Sin CA instalada | CA no confiable | Importar `ICASA-Dev-CA` en Trusted Root |
| 7 | `/controller/` vía doble proxy | JSON mock | Flujo completo hasta SaaS simulado |

## Arquitectura del lab

```
┌─────────────┐   CONNECT    ┌──────────────┐   proxy_pass   ┌─────────────┐
│   client    │─────────────►│ forward-proxy│───────────────►│reverse-proxy│
│  (curl)     │   :3128      │   (Squid)    │   TLS :443     │   (Nginx)   │
└─────────────┘              └──────────────┘                └──────┬──────┘
       │                              red: lan                         │ red: dmz
       │                              DNS: appd-proxy.icasa.local      ▼
       │                                                         ┌─────────────┐
       └────────────────────────────────────────────────────────►│  mock-saas  │
                    (test 3: directo, sin Squid)                  │  (mock AppD)│
                                                                  └─────────────┘
```

## Requisitos

- Docker Desktop o Docker Engine + Docker Compose v2
- `openssl` (para generar certificados la primera vez)
- ~500 MB de espacio para imágenes

## Inicio rápido

```bash
cd lab
chmod +x scripts/*.sh
./scripts/run-demo.sh
```

El script:
1. Genera certificados con SAN **solo de dominio** (sin IP — a propósito)
2. Construye y levanta los contenedores
3. Ejecuta los 7 tests con explicación en consola

## Comandos manuales

```bash
# Solo generar certificados
./scripts/generate-lab-certs.sh

# Levantar infraestructura
docker compose up -d mock-saas reverse-proxy forward-proxy

# Ejecutar pruebas
docker compose run --rm client

# Ver logs de Squid (buscar líneas CONNECT)
docker compose logs -f forward-proxy

# Probar desde el host (Squid expuesto en localhost:13128)
curl -vk --cacert certs/ca.crt \
  -x http://localhost:13128 \
  https://appd-proxy.icasa.local/health
# Nota: desde el host necesitas resolver appd-proxy.icasa.local
# Agregar a /etc/hosts la IP del contenedor reverse-proxy, o usar:
docker compose exec client curl -x http://forward-proxy:3128 \
  --cacert /certs/ca.crt https://appd-proxy.icasa.local/health

# Detener
docker compose down
```

## Certificados del laboratorio

Generados en `lab/certs/`:

| Archivo | Uso |
|---------|-----|
| `ca.crt` | CA raíz (`ICASA-Lab-CA`) — instalar en el cliente/agente |
| `ca.key` | Solo lab — no distribuir |
| `proxy.crt` | Cert del reverse proxy (CN=`appd-proxy.icasa.local`) |
| `proxy.key` | Clave privada del proxy |

Verificar que el cert **no** incluye IP en SAN:

```bash
openssl x509 -in certs/proxy.crt -noout -text | grep -A3 "Subject Alternative Name"
# Debe mostrar solo DNS:appd-proxy.icasa.local
```

> En producción ICASA, el script `scripts/generate-certs-selfsigned.sh` **sí** incluye `IP.1 = 10.250.5.12` como workaround. Este lab omite la IP a propósito para que el fallo sea visible.

## Mapeo con el ambiente real ICASA

| Lab (Docker) | Producción ICASA |
|--------------|-------------------|
| `forward-proxy:3128` | Squid `10.2.32.179:3128` |
| `reverse-proxy:443` | Nginx `10.250.5.12:443` |
| `appd-proxy.icasa.local` | Mismo FQDN |
| `mock-saas:8080` | `teresa202606020142139.saas.appdynamics.com:443` |
| `ICASA-Lab-CA` | `ICASA-Dev-CA` |

## Configuración correcta del .NET Agent (referencia)

```xml
<controller host="appd-proxy.icasa.local" port="443" ssl="true" enable_tls12="true">
  <account name="teresa202606020142139" password="ACCESS_KEY" />
  <proxy host="10.2.32.179" port="3128" enabled="true" />
</controller>
```

Ver también:
- [troubleshooting-doble-proxy.md](../docs/03-dotnet-agent-iis/troubleshooting-doble-proxy.md)
- [arquitectura-doble-proxy.md](../docs/00-arquitectura/arquitectura-doble-proxy.md)

## Troubleshooting del lab

**`docker compose build` falla**
- Verificar que Docker esté corriendo

**Squid rechaza CONNECT**
- Revisar `forward-proxy/squid.conf` — solo permite `appd-proxy.icasa.local:443`

**Nginx no arranca**
- Ejecutar `./scripts/generate-lab-certs.sh` antes de `docker compose up`

**Tests 2 y 5 no fallan**
- Verificar que `proxy.crt` no tenga IP en SAN (regenerar certificados)
