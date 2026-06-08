# Instalación Nginx Reverse Proxy — RHEL 9 (DMZ)

Servidor: **STMPDMZPOCOB PROXY** — `10.250.5.12`

## Objetivo

Nginx actúa como reverse proxy TLS en la DMZ. Es el **único componente con salida a Internet** (TCP 443). Termina TLS hacia los agentes internos y reenvía tráfico HTTPS hacia:

- AppDynamics Controller SaaS
- Analytics Events API
- Splunk Cloud (HEC / ingest)

## Requisitos previos

- RHEL 9 con acceso root/sudo
- Salida TCP 443 hacia Internet (post-firewall DMZ)
- Entrada TCP 443 desde LAN (`10.2.x.x`) y servidores Windows IIS
- Certificados TLS (ver [certificados-tls.md](certificados-tls.md))

## Instalación automatizada

```bash
git clone https://github.com/ulix1808/ICASA_Observability.git
cd ICASA_Observability
cp .env.example .env
# Editar .env con valores reales
sudo ./scripts/install-nginx-proxy.sh
```

## Instalación manual paso a paso

### 1. Instalar Nginx y dependencias

```bash
sudo dnf install -y nginx openssl firewalld
sudo systemctl enable nginx
```

### 2. Configurar certificados TLS

Elegir una opción:

```bash
# Opción A: CA corporativa — ver certificados-tls.md
# Opción B: Autofirmado DEV
sudo ./scripts/generate-certs-selfsigned.sh
```

### 3. Copiar configuración Nginx

```bash
sudo cp configs/nginx/appdynamics-upstream.conf /etc/nginx/conf.d/
sudo cp configs/nginx/splunk-upstream.conf /etc/nginx/conf.d/
sudo nginx -t
sudo systemctl restart nginx
```

### 4. Firewall local (RHEL)

```bash
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

> Las reglas de firewall perimetral las gestiona el equipo de seguridad ICASA.

### 5. Validación

```bash
# Estado Nginx
sudo systemctl status nginx

# Test upstream AppDynamics
curl -s -o /dev/null -w "%{http_code}" \
  https://teresa202606020142139.saas.appdynamics.com/controller/rest/serverstatus
# Esperado: 200

# Test desde LAN (ejecutar en 10.2.32.179 o 10.2.32.180)
curl -k https://10.250.5.12/health
# Esperado: "OK"
```

## Configuración de agentes hacia el proxy

Los agentes AppDynamics deben apuntar al **proxy**, no directamente al controller SaaS:

| Parámetro | Valor agente | Valor real upstream (solo Nginx) |
|-----------|-------------|----------------------------------|
| Controller Host | `10.250.5.12` o FQDN proxy | `teresa202606020142139.saas.appdynamics.com` |
| Controller Port | `443` | `443` |
| SSL Enabled | `true` | — |

Nginx reescribe el header `Host` al FQDN real del controller SaaS en el upstream.

## Separación de tráfico por puerto (requisito cliente)

| Listener en proxy (LAN → DMZ) | Tráfico | Salida proxy → Internet |
|------------------------------|---------|-------------------------|
| **:443** | AppDynamics (agentes APM, HTTP SDK) | `:443` → SaaS |
| **:8443** | Analytics Events (SAP) | `:443` → analytics.api.appdynamics.com |
| **:8444** | Splunk HEC (UF, SC4SNMP) | `:443` → Splunk Cloud |

> Hacia afuera **solo 443**. Los puertos 8443/8444 existen solo en la interfaz LAN→DMZ para que Nginx enrute correctamente.

## Upstreams configurados

| Upstream | Destino | Uso |
|----------|---------|-----|
| `appd_controller` | `teresa202606020142139.saas.appdynamics.com:443` | Agentes APM |
| `appd_analytics` | `analytics.api.appdynamics.com:443` | SAP Analytics Events |
| `splunk_cloud` | Variable `$SPLUNK_HEC_HOST` | Splunk Cloud HEC |

## Reiniciar Nginx

Aplicar cambios de configuración o certificados:

```bash
# 1. Validar sintaxis antes de reiniciar (obligatorio)
sudo nginx -t

# 2. Recargar configuración sin cortar conexiones activas (recomendado)
sudo systemctl reload nginx

# 3. Reinicio completo (si reload no aplica o tras cambio de certificados)
sudo systemctl restart nginx

# 4. Verificar que quedó en ejecución
sudo systemctl status nginx
```

Cuándo usar cada opción:

| Situación | Comando |
|-----------|---------|
| Cambio en `.conf` de `/etc/nginx/conf.d/` | `nginx -t` → `systemctl reload nginx` |
| Renovación de certificado TLS | `nginx -t` → `systemctl restart nginx` |
| Nginx no responde / error en logs | `systemctl restart nginx` |
| Tras instalar o actualizar paquete nginx | `systemctl restart nginx` |

Si `nginx -t` falla, **no reiniciar** — corregir el error en la configuración primero.

```bash
# Ver último error si el servicio no arranca
sudo journalctl -u nginx -n 50 --no-pager
```

## Monitoreo del proxy

Endpoint de health check:

```
GET https://10.250.5.12/health
Response: 200 OK
```

Logs:

```bash
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## Troubleshooting

### `curl: (7) Failed to connect to localhost port 443: Connection refused`

Nginx está **activo** pero **no escucha en 443**. Diagnóstico en el servidor proxy (`STMPDMZPOCOB` / `10.250.5.12`):

```bash
# 1. Confirmar que es el servidor proxy DMZ (no el colector STMPLPOCOB .179/.180)
hostname -f
ip addr | grep "inet "

# 2. Ver en qué puertos escucha Nginx
sudo ss -tlnp | grep nginx
# Debe mostrar :443, :8443 y :8444. Si solo aparece :80, falta la config SSL.

# 3. Verificar que existen los archivos de configuración ICASA
ls -la /etc/nginx/conf.d/
# Deben existir: appdynamics-upstream.conf  splunk-upstream.conf

# 4. Verificar certificados TLS
ls -la /etc/nginx/ssl/proxy.crt /etc/nginx/ssl/proxy.key

# 5. Validar configuración
sudo nginx -t

# 6. Si faltan configs o certificados, copiar desde el repo y reiniciar
sudo cp appdynamics-upstream.conf splunk-upstream.conf /etc/nginx/conf.d/
sudo ./scripts/generate-certs-selfsigned.sh   # o instalar certs de CA
sudo nginx -t && sudo systemctl restart nginx

# 7. Probar de nuevo
curl -k https://localhost/health
curl -k https://10.250.5.12/health
```

| Causa | Indicador | Solución |
|-------|-----------|----------|
| Servidor incorrecto | hostname `STMPPOCOB` (colector) | Ejecutar en **proxy DMZ** `10.250.5.12` |
| Config no desplegada | `conf.d/` sin archivos ICASA | Copiar configs del repo |
| Certificados faltantes | `nginx -t` error SSL | Generar o instalar `proxy.crt` / `proxy.key` |
| Solo puerto 80 activo | `ss` muestra `:80` pero no `:443` | Desplegar config SSL y `restart nginx` |
| Firewall local | `ss` muestra `:443` pero curl falla desde otro host | `firewall-cmd --add-service=https` |

### Otros errores

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| 502 Bad Gateway | Proxy no alcanza SaaS | Verificar DNS y firewall DMZ→Internet |
| SSL handshake failed (agente) | CA no confiada en agente | Importar CA del proxy en truststore |
| 503 Service Unavailable | Upstream AppDynamics caído | Verificar status SaaS |
| Connection refused :443 (desde LAN) | Firewall perimetral | Solicitar apertura a seguridad |

## Referencias

- [Use a Reverse Proxy — AppDynamics](https://help.splunk.com/en/appdynamics-on-premises/controller-deployment/26.4.0/controller-deployment/administer-the-controller/use-a-reverse-proxy)
- [Nginx — ngx_http_proxy_module](http://nginx.org/en/docs/http/ngx_http_proxy_module.html)
