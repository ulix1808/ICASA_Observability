# Certificados TLS — Proxy Nginx

## Concepto clave: NO se requiere certificado compuesto

En un reverse proxy TLS existen **dos saltos HTTPS independientes**, cada uno con su propio par certificado/clave:

```
┌─────────────┐  HTTPS #1   ┌─────────────┐  HTTPS #2   ┌─────────────┐
│   Agente    │ ──────────► │ Nginx Proxy │ ──────────► │ AppDynamics │
│  (cliente)  │  cert proxy │  (termina   │  cert SaaS  │    SaaS     │
└─────────────┘             │   TLS #1)   │             └─────────────┘
                            └─────────────┘
```

| Salto | Quién presenta certificado | Quién valida |
|-------|---------------------------|--------------|
| Agente → Proxy | Certificado del proxy | Agente (confía CA del proxy) |
| Proxy → AppDynamics | Certificado público de AppDynamics | Nginx (confía CA públicas del SO) |

**No se instala el certificado de AppDynamics en los agentes.** Los agentes solo necesitan confiar en el certificado del proxy.

**No se instala el certificado del proxy en Nginx hacia upstream.** Nginx usa las CA públicas del sistema para validar AppDynamics SaaS.

---

## Opción A — CA corporativa (recomendada)

### Paso 1: Generar CSR en el proxy

```bash
# En 10.250.5.12
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -new -newkey rsa:2048 -nodes \
  -keyout /etc/nginx/ssl/proxy.key \
  -out /etc/nginx/ssl/proxy.csr \
  -subj "/C=GT/O=ICASA/CN=appd-proxy.icasa.local"
```

Entregar `proxy.csr` al equipo de PKI / entidad certificadora.

### Paso 2: Instalar certificado emitido

```bash
# Copiar cert emitido + cadena CA
sudo cp proxy.crt /etc/nginx/ssl/
sudo cp icasa-ca-chain.crt /etc/nginx/ssl/
sudo chmod 600 /etc/nginx/ssl/proxy.key
sudo chown -R nginx:nginx /etc/nginx/ssl
```

### Paso 3: Distribuir CA a agentes

**RHEL / Java (Database Agent, Machine Agent):**

```bash
# Ver script completo: scripts/install-truststore-agent.sh
sudo keytool -importcert -alias icasa-ca \
  -file /etc/pki/tls/certs/icasa-ca.crt \
  -keystore /opt/appdynamics/cacerts.jks \
  -storepass changeit -noprompt
```

**Windows (.NET Agent):**

```powershell
Import-Certificate -FilePath "icasa-ca.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

---

## Opción B — Autofirmado (DEV / pruebas)

Usar el script incluido:

```bash
sudo ./scripts/generate-certs-selfsigned.sh
```

Genera:
- `/etc/nginx/ssl/ca.crt` — CA raíz (distribuir a agentes)
- `/etc/nginx/ssl/proxy.crt` — Certificado del proxy
- `/etc/nginx/ssl/proxy.key` — Clave privada del proxy

### Importar CA en Java (Database Agent)

```bash
export DB_AGENT_HOME=/opt/appdynamics/db-agent
sudo cp /etc/nginx/ssl/ca.crt $DB_AGENT_HOME/conf/

# Agregar al script de inicio del agente:
-Djavax.net.ssl.trustStore=$DB_AGENT_HOME/conf/truststore.jks
-Djavax.net.ssl.trustStorePassword=changeit
```

---

## Validación

### Desde MONITOR (10.2.32.179) o COLECTOR (10.2.32.180)

```bash
# Verificar certificado del proxy
openssl s_client -connect 10.250.5.12:443 -servername appd-proxy.icasa.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates

# Verificar que el proxy alcanza AppDynamics
curl -v --proxy https://10.250.5.12:443 \
  --proxy-cacert /etc/pki/tls/certs/icasa-ca.crt \
  https://teresa202606020142139.saas.appdynamics.com/controller/rest/serverstatus
```

### Desde el proxy (10.250.5.12)

```bash
# Verificar upstream AppDynamics
curl -v https://teresa202606020142139.saas.appdynamics.com/controller/rest/serverstatus

# Respuesta esperada: HTTP 200 con body "true"
```

---

## Configuración SSL en Nginx

Ver `configs/nginx/appdynamics-upstream.conf`:

```nginx
ssl_certificate     /etc/nginx/ssl/proxy.crt;
ssl_certificate_key /etc/nginx/ssl/proxy.key;
ssl_protocols       TLSv1.2 TLSv1.3;
ssl_ciphers         HIGH:!aNULL:!MD5;
```

Para upstream HTTPS hacia AppDynamics SaaS, Nginx usa el store de CA del sistema operativo (`/etc/pki/tls/certs/ca-bundle.crt` en RHEL).

---

## Renovación

| Certificado | Frecuencia | Acción |
|-------------|-----------|--------|
| Proxy (agente → proxy) | Según CA (típ. 1-2 años) | Renovar CSR, redistribuir si cambia CA |
| AppDynamics SaaS | Gestionado por Splunk/Cisco | Sin acción en ICASA |

Programar alerta 30 días antes de expiración del cert del proxy.
