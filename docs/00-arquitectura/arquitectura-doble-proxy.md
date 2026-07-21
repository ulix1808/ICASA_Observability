# Arquitectura de doble proxy — ICASA

## Resumen

El ambiente del cliente requiere **dos capas de proxy** para salir a AppDynamics SaaS:

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────────┐     ┌──────────────────┐
│ Windows / RHEL  │     │ Forward Proxy Squid  │     │ Reverse Proxy Nginx │     │ AppDynamics SaaS │
│ .NET / DB Agent │────►│ 10.2.32.179 :3128    │────►│ 10.250.5.12 :443    │────►│ teresa...appd... │
│ (LAN)           │ HTTP│ (MONITOR)            │ HTTPS│ (DMZ)               │ HTTPS│                  │
└─────────────────┘     └──────────────────────┘     └─────────────────────┘     └──────────────────┘
```

| Capa | Servidor | IP | Puerto | Rol |
|------|----------|-----|--------|-----|
| **Forward proxy** | Squid (MONITOR) | `10.2.32.179` | `3128` | Proxy corporativo HTTP — los agentes salen por aquí |
| **Reverse proxy** | Nginx (DMZ) | `10.250.5.12` | `443` | Termina TLS, reenvía a AppDynamics SaaS |
| **Destino** | AppDynamics SaaS | `teresa202606020142139.saas.appdynamics.com` | `443` | Controller |

> **Importante:** `10.2.32.179` **NO es el Controller**. Es solo el forward proxy Squid.

## DNS requerido

El forward proxy Squid debe poder resolver el destino del reverse proxy:

| Hostname | IP | Dónde registrar |
|----------|-----|-----------------|
| `appd-proxy.icasa.local` | `10.250.5.12` | DNS interno ICASA **y/o** `/etc/hosts` en Squid |

Sin DNS, usar IP directa `10.250.5.12` en la configuración del agente (el certificado incluye SAN `IP.1 = 10.250.5.12`).

## Certificados TLS

Solo se necesita confiar en la **CA del reverse proxy** (`ICASA-Dev-CA`), no en AppDynamics SaaS:

| Servidor | Qué instalar | Dónde |
|----------|-------------|-------|
| Windows (.NET Agent) | `ca.crt` (ICASA-Dev-CA) | `Cert:\LocalMachine\Root` |
| RHEL (Database Agent) | `ca.crt` | Java truststore (`truststore.jks`) |
| Squid | No requiere (túnel CONNECT, no termina TLS) | — |
| Nginx | `proxy.crt` + `proxy.key` | `/etc/nginx/ssl/` |

## Configuración por agente

### .NET Agent (Windows)

| Campo | Valor |
|-------|-------|
| Server (Controller) | `appd-proxy.icasa.local` o `10.250.5.12` |
| Port | `443` |
| Enable SSL | ✓ |
| Enable TLS 1.2 | ✓ |
| Multi-Tenant Controller | ✓ |
| Account Name | `teresa202606020142139` |
| Account Access Key | *(valor real, sin espacios)* |
| **Use proxy** | ✓ |
| **Proxy address** | `10.2.32.179` |
| **Proxy port** | `3128` |

Ver `configs/dotnet-agent/config.xml`

### Database Agent (Java / RHEL)

```xml
<!-- controller-info.xml -->
<controller-host>10.250.5.12</controller-host>
<controller-port>443</controller-port>
<controller-ssl-enabled>true</controller-ssl-enabled>
```

```bash
# JVM args en db-agent.service
-Dappdynamics.http.proxyHost=10.2.32.179
-Dappdynamics.http.proxyPort=3128
```

### Machine Agent (Windows / Linux)

Mismos parámetros que Database Agent:
- Controller → `10.250.5.12:443`
- Proxy → `10.2.32.179:3128`

## Squid — requisitos mínimos

Squid en `10.2.32.179` debe permitir método **CONNECT** hacia el reverse proxy:

```squid
# /etc/squid/squid.conf (ejemplo)

# Permitir CONNECT HTTPS al reverse proxy
acl SSL_ports port 443
acl CONNECT method CONNECT
acl appd_proxy dst 10.250.5.12
http_access allow CONNECT SSL_ports appd_proxy
http_access allow CONNECT SSL_ports

# DNS: agregar en /etc/hosts si no hay DNS interno
# 10.250.5.12  appd-proxy.icasa.local
```

**No habilitar SSL Bump** hacia `10.250.5.12` — rompe el túnel CONNECT del agente.

## Validación por salto

### 1. Desde el servidor Windows (.NET Agent)

```powershell
# CA instalada
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*ICASA-Dev-CA*" }

# Test vía forward proxy Squid (HTTPS correcto)
Invoke-WebRequest -Uri "https://10.250.5.12/health" `
  -Proxy "http://10.2.32.179:3128" -UseBasicParsing

# Esperado: StatusCode 200, Content "OK"
```

### 2. Desde Squid (10.2.32.179)

```bash
# DNS
nslookup appd-proxy.icasa.local
# o: getent hosts appd-proxy.icasa.local

# Conectividad HTTPS (usar https, NO http)
curl -vk https://10.250.5.12/health
# Esperado: HTTP/1.1 200 OK

# Ver logs Squid durante prueba desde Windows
tail -f /var/log/squid/access.log
```

### 3. Desde Nginx DMZ (10.250.5.12)

```bash
curl -k https://localhost/health
curl -s https://teresa202606020142139.saas.appdynamics.com/controller/rest/serverstatus
# Esperado: 200
```

## Errores comunes

| Error | Causa | Solución |
|-------|-------|----------|
| `Unable to connect to the remote server` (Windows) | Squid no alcanza Nginx o DNS NXDOMAIN | DNS/hosts en Squid; firewall 179→DMZ:443 |
| `400 plain HTTP request was sent to HTTPS port` | `curl http://...` en puerto 443 | Usar `https://` |
| `certmgr.msc ... Trusted Root` | CA no en store del sistema | Importar `ca.crt` en LocalMachine\Root |
| `Invalid controller account access key` | Access Key vacío/corrupto en config.xml | Editar `%ProgramData%\AppDynamics\DotNetAgent\Config\config.xml` |
| Proxy = `10.250.5.12:443` en .NET | Confundir reverse con forward proxy | Proxy debe ser `10.2.32.179:3128` |
| Server = `10.2.32.179:3128` | Confundir Squid con Controller | Server debe ser `appd-proxy.icasa.local:443` |
| Squid SSL Bump | Inspección SSL rompe CONNECT | Deshabilitar bump hacia 10.250.5.12 |
| Nginx upstream SSL reset (Splunk) | Host/puerto Splunk incorrecto | Regenerar config con host Splunk real |

## Referencias

- [Troubleshooting .NET Agent — doble proxy](../03-dotnet-agent-iis/troubleshooting-doble-proxy.md)
- [Certificados TLS](../01-proxy-nginx/certificados-tls.md)
- Troubleshooting sesión cliente: `Troubleshooting_AppDynamics_Proxy.txt`
