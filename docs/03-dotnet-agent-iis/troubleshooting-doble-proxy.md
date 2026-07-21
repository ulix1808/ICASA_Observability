# Troubleshooting — .NET Agent con doble proxy

Basado en sesión de troubleshooting ICASA (julio 2026).

## Arquitectura

```
.NET Agent (Windows)  →  Squid 10.2.32.179:3128  →  Nginx 10.250.5.12:443  →  AppDynamics SaaS
```

## Configuración correcta del Configuration Utility

![Configuración correcta]

| Campo | Valor correcto | Valor incorrecto (visto en sesión) |
|-------|---------------|-----------------------------------|
| Server | `appd-proxy.icasa.local` | ~~`10.2.32.179`~~ (es Squid, no Controller) |
| Port | `443` | ~~`3128`~~ |
| Enable SSL | ✓ | |
| Enable TLS 1.2 | ✓ | Dejar desmarcado causa fallos TLS |
| Use proxy | ✓ | |
| Proxy address | `10.2.32.179` | ~~`10.250.5.12`~~ (ese es el reverse proxy) |
| Proxy port | `3128` | ~~`443`~~ |
| Account Name | `teresa202606020142139` | |
| Account Access Key | `awo27vhp6nrw` | Verificar sin espacios |

## config.xml correcto

Ubicación: `%ProgramData%\AppDynamics\DotNetAgent\Config\config.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<appdynamics-agent xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <controller host="appd-proxy.icasa.local"
              port="443"
              ssl="true"
              enable_tls12="true"
              enable_config_deployment="true">
    <account name="teresa202606020142139" password="awo27vhp6nrw" />
    <application name="ICASA-DEV-IIS" />
    <!-- Forward proxy Squid — NO el reverse proxy Nginx -->
    <proxy host="10.2.32.179" port="3128" enabled="true" />
  </controller>
  <iis><automatic /></iis>
  <machine-agent />
</appdynamics-agent>
```

Alternativa con IP (si DNS no resuelve):

```xml
<controller host="10.250.5.12" port="443" ssl="true" enable_tls12="true">
```

## Paso 1 — Certificado CA en Windows

```powershell
# Importar CA del proxy (ICASA-Dev-CA) — ejecutar como Administrador
Import-Certificate -FilePath "C:\certs\ca.crt" -CertStoreLocation Cert:\LocalMachine\Root

# Verificar
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*ICASA-Dev-CA*" }
certlm.msc  # Trusted Root Certification Authorities → debe aparecer ICASA-Dev-CA
```

El certificado `appd-proxy.icasa.local` **no** va en Trusted Root — solo la **CA raíz** (`ICASA-Dev-CA`).

## Paso 2 — DNS

En el servidor Windows y en Squid (`10.2.32.179`):

```bash
# En Squid — /etc/hosts si no hay DNS
echo "10.250.5.12  appd-proxy.icasa.local" | sudo tee -a /etc/hosts

# Verificar
nslookup appd-proxy.icasa.local
```

En Windows (opcional si no hay DNS):

```
C:\Windows\System32\drivers\etc\hosts
10.250.5.12  appd-proxy.icasa.local
```

## Paso 3 — Pruebas de conectividad

### Desde Windows (servidor del .NET Agent)

```powershell
# Test 1: directo al reverse proxy (puede fallar si firewall solo permite vía Squid)
Invoke-WebRequest -Uri "https://10.250.5.12/health" -SkipCertificateCheck -UseBasicParsing

# Test 2: vía forward proxy Squid (este es el camino real del agente)
Invoke-WebRequest -Uri "https://appd-proxy.icasa.local/health" `
  -Proxy "http://10.2.32.179:3128" -UseBasicParsing

# Test 3: con IP si DNS falla
Invoke-WebRequest -Uri "https://10.250.5.12/health" `
  -Proxy "http://10.2.32.179:3128" -UseBasicParsing
```

Esperado: **StatusCode 200**, Content **OK**

### Desde Squid (10.2.32.179)

```bash
# IMPORTANTE: usar HTTPS, no HTTP
curl -vk https://10.250.5.12/health
# Esperado: HTTP/1.1 200 OK

# NO usar (genera 400 Bad Request):
# curl -vk http://10.250.5.12:443/health
```

### Monitorear Squid durante prueba Windows

```bash
sudo tail -f /var/log/squid/access.log
# Buscar líneas CONNECT hacia 10.250.5.12:443
```

## Paso 4 — Error Access Key

Si el Coordinator muestra:

```
Invalid controller account access key is null, empty or corrupt
```

1. Abrir `config.xml` como Administrador
2. Verificar que `password` en `<account>` tenga el Access Key completo
3. Sin comillas extra, sin espacios, sin saltos de línea
4. Reiniciar servicio:

```powershell
Restart-Service AppDynamics.Agent.Coordinator
Get-Content "C:\ProgramData\AppDynamics\DotNetAgent\Logs\*.log" -Tail 30
```

## Paso 5 — Test en Configuration Utility

1. Abrir **AppDynamics .NET Agent Configuration Utility** como Administrador
2. Configurar según tabla arriba
3. Clic **Test Controller connection**
4. Esperado: conexión exitosa

## Checklist de resolución

- [ ] CA `ICASA-Dev-CA` en `LocalMachine\Root` en servidor Windows
- [ ] DNS `appd-proxy.icasa.local` → `10.250.5.12` (o usar IP en config)
- [ ] Squid permite CONNECT a `10.250.5.12:443`
- [ ] Squid **sin** SSL Bump hacia el reverse proxy
- [ ] Nginx responde `curl -vk https://10.250.5.12/health` → 200 OK
- [ ] `config.xml`: Server = proxy DMZ, Proxy = Squid 3128
- [ ] Access Key correcto en config.xml
- [ ] `Restart-Service AppDynamics.Agent.Coordinator`
- [ ] Test Controller connection = OK

## Si Invoke-WebRequest sigue fallando vía proxy

Revisar con equipo de red/Squid:

1. ¿Squid tiene ACL que bloquea CONNECT a `10.250.5.12`?
2. ¿Squid resuelve `appd-proxy.icasa.local`? (agregar `/etc/hosts`)
3. ¿Firewall permite `10.2.32.179` → `10.250.5.12:443`?
4. ¿Squid requiere autenticación? (si sí, agregar en config.xml)

```xml
<proxy host="10.2.32.179" port="3128" enabled="true">
  <authentication enabled="true" user_name="USER" password="PASS" domain=""/>
</proxy>
```
