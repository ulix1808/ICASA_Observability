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

## Teoría de certificados TLS

Esta sección explica **por qué** fallan las pruebas del lab y qué ocurre en el ambiente real ICASA.

### ¿Qué problema resuelve HTTPS?

Sin TLS, cualquiera en la red puede leer o modificar el tráfico. Con HTTPS:

1. El **servidor** demuestra su identidad con un **certificado digital**.
2. Cliente y servidor acuerdan una **clave de cifrado** (handshake TLS).
3. El tráfico viaja **cifrado**.

En ICASA, el agente .NET no habla directo con AppDynamics SaaS. Habla con **Nginx en la DMZ**, que a su vez habla con SaaS. Eso implica **dos mundos TLS distintos**.

### Los tres actores del certificado

Cada certificado tiene piezas clave:

| Campo | En el lab | Significado |
|-------|-----------|-------------|
| **Subject / CN** | `appd-proxy.icasa.local` | Identidad declarada del servidor |
| **Issuer** | `ICASA-Lab-CA` | Autoridad que firmó el certificado |
| **SAN** (Subject Alternative Name) | `DNS:appd-proxy.icasa.local` | Nombres válidos para conectarse |
| **Clave privada** | `proxy.key` | Solo en el servidor; nunca se distribuye |
| **CA raíz** | `ca.crt` | Autoridad de confianza que el cliente debe conocer |

El script `generate-lab-certs.sh` crea esta jerarquía:

```
ICASA-Lab-CA (ca.crt)  ──firma──►  proxy.crt (para appd-proxy.icasa.local)
```

En producción, `ICASA-Dev-CA` cumple el mismo rol que `ICASA-Lab-CA`.

### Cadena de confianza (por qué importa `ca.crt`)

El cliente (agente, curl, .NET) no confía en `proxy.crt` por sí solo. Confía si puede construir una cadena hasta una **CA que ya tenga en su almacén de confianza**:

```
proxy.crt  →  firmado por  →  ICASA-Dev-CA  →  debe estar en Trusted Root
```

Por eso en Windows se importa **`ca.crt`** (la CA), no `proxy.crt` (el certificado del servidor).

- **Test 6 del lab**: sin `ca.crt` → `unable to get local issuer certificate`
- En troubleshooting ICASA: el mensaje del .NET Agent pide agregar la CA en `certmgr.msc` → Trusted Root

> Instalar solo el certificado del servidor en Trusted Root es un error común. Lo correcto es importar la **CA raíz** que lo emitió.

### Verificación de hostname (el corazón del lab)

TLS no solo pregunta *“¿confío en quien firmó esto?”*. También pregunta:

> **¿El nombre al que me conecté coincide con el certificado?**

Esa comparación usa el **hostname de la URL**, no la IP por la que llegaste.

```
Te conectas a:     https://10.250.5.12/health
Certificado dice:  CN/SAN = appd-proxy.icasa.local
Resultado:         ❌ hostname mismatch
```

```
Te conectas a:     https://appd-proxy.icasa.local/health
Certificado dice:  CN/SAN = appd-proxy.icasa.local
Resultado:         ✅ OK (si además confías en la CA)
```

Eso es el **Test 2** del lab: la CA está instalada, pero la conexión es por IP → falla con `no alternative certificate subject name matches target host name`.

**Tener la CA instalada no basta.** La CA responde “¿quién firmó esto?”. El hostname responde “¿es para el servidor al que me conecté?”.

### Por qué el lab omite la IP del SAN

En producción, `scripts/generate-certs-selfsigned.sh` incluye `IP.1 = 10.250.5.12` como workaround: si conectas por IP, el certificado también cubre esa dirección.

Este lab **no** incluye IP a propósito, para que el fallo sea visible:

| Enfoque | Ventaja | Desventaja |
|---------|---------|------------|
| **Solo dominio en SAN** | Correcto; alineado con buenas prácticas | Requiere DNS o entrada en `/etc/hosts` |
| **Dominio + IP en SAN** | Funciona aunque uses IP en la config | Oculta el problema; el agente debería usar FQDN igual |

La configuración correcta en ICASA sigue siendo **`appd-proxy.icasa.local`**, no la IP.

### Dos capas TLS en el doble proxy

```
Agente ──[TLS #1]──► Nginx ──[TLS #2]──► AppDynamics SaaS
         cert proxy              cert público AppD
         valida: agente          valida: Nginx (CA públicas)
```

| Salto | Quién presenta certificado | Quién valida | Qué instalar |
|-------|---------------------------|--------------|--------------|
| Agente → Nginx | `proxy.crt` (ICASA-Dev-CA) | Agente / .NET | `ca.crt` en Trusted Root |
| Nginx → SaaS | Certificado público de AppDynamics | Nginx | CA públicas del SO (ya vienen) |
| Agente → Squid | **Ninguno** (Squid no termina TLS) | — | — |

**Squid no valida el certificado del reverse proxy.** Solo abre un túnel TCP (`CONNECT`) hacia `appd-proxy.icasa.local:443`. El handshake TLS ocurre **entre el agente y Nginx**, después del túnel.

Por eso Squid no necesita `ca.crt`, pero el agente sí.

### Qué falla en cada test (teoría + práctica)

| Test | Qué ocurre a nivel TLS/red |
|------|---------------------------|
| **1** `http://IP:443` | No es TLS; Nginx espera handshake → **400 Bad Request** |
| **2** `https://IP` | Cadena OK, **hostname NO** → mismatch |
| **3** `https://FQDN` | Cadena OK, **hostname OK** → 200 |
| **4** FQDN vía Squid | Squid tuneliza; TLS agente↔Nginx con FQDN correcto → 200 |
| **5** IP vía Squid | Squid puede rechazar (403) o, si deja pasar, TLS falla por hostname |
| **6** Sin CA | No hay cadena de confianza → error de emisor |
| **7** `/controller/` | Flujo completo hasta mock SaaS si todo lo anterior es correcto |

### Analogía rápida

- **CA (`ca.crt`)**: lista de notarios que aceptas como válidos.
- **Certificado del proxy**: credencial que dice “soy el edificio `appd-proxy.icasa.local`”.
- **Conectar por IP**: llegas pidiendo el edificio `10.250.5.12`, pero la credencial dice `appd-proxy.icasa.local` → rechazo aunque el notario sea legítimo.
- **Squid**: el taxi que te lleva al edificio; no revisa tu credencial, solo te deja llegar (o no, según ACL).

### Checklist para ICASA

1. **Server del agente** = `appd-proxy.icasa.local` (FQDN del certificado)
2. **Proxy del agente** = `10.2.32.179:3128` (Squid, no Nginx)
3. **Trusted Root** = `ICASA-Dev-CA` (`ca.crt`), no el certificado del proxy
4. **DNS / hosts** = `appd-proxy.icasa.local` → `10.250.5.12`
5. **Squid** = permitir `CONNECT` a ese host:443, sin SSL Bump

Ver documentación ampliada: [certificados-tls.md](../docs/01-proxy-nginx/certificados-tls.md)

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
