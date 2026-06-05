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

# Test desde LAN (ejecutar en 10.2.32.180)
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

## Upstreams configurados

| Upstream | Destino | Uso |
|----------|---------|-----|
| `appd_controller` | `teresa202606020142139.saas.appdynamics.com:443` | Agentes APM |
| `appd_analytics` | `analytics.api.appdynamics.com:443` | SAP Analytics Events |
| `splunk_cloud` | Variable `$SPLUNK_HEC_HOST` | Splunk Cloud HEC |

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

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| 502 Bad Gateway | Proxy no alcanza SaaS | Verificar DNS y firewall DMZ→Internet |
| SSL handshake failed (agente) | CA no confiada en agente | Importar CA del proxy en truststore |
| 503 Service Unavailable | Upstream AppDynamics caído | Verificar status SaaS |
| Connection refused :443 | Firewall LAN→DMZ | Solicitar apertura a seguridad |

## Referencias

- [Use a Reverse Proxy — AppDynamics](https://help.splunk.com/en/appdynamics-on-premises/controller-deployment/26.4.0/controller-deployment/administer-the-controller/use-a-reverse-proxy)
- [Nginx — ngx_http_proxy_module](http://nginx.org/en/docs/http/ngx_http_proxy_module.html)
