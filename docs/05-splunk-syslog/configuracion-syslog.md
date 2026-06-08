# Splunk Syslog — Configuración TCP 514

Servidor: **STMPLPOCOB MONITOR** — `10.2.32.179`

## Requisitos

- Splunk Universal Forwarder instalado en MONITOR (`10.2.32.179`)
- Puerto TCP 514 abierto en MONITOR (desde equipos de red LAN)
- Conectividad MONITOR → proxy `10.250.5.12:8444`
- Token HEC o configuración UF outputs hacia Splunk Cloud (pendiente URL)

## Instalación Universal Forwarder

```bash
# Descargar UF para RHEL 9 desde splunk.com
sudo tar -xzf splunkforwarder-*.tgz -C /opt
sudo useradd -r splunkfwd 2>/dev/null || true
sudo chown -R splunkfwd:splunkfwd /opt/splunkforwarder

# Aceptar licencia e iniciar
sudo -u splunkfwd /opt/splunkforwarder/bin/splunk start --accept-license --answer-yes --no-prompt
```

## Configuración inputs — Syslog TCP 514

Archivo: `configs/splunk/inputs.conf`

```ini
# /opt/splunkforwarder/etc/system/local/inputs.conf

[tcp://514]
connection_host = ip
sourcetype = syslog
index = network
disabled = 0

# Syslog de servidores Linux/Windows
[tcp://515]
connection_host = dns
sourcetype = syslog:host
index = os
disabled = 0
```

Aplicar:

```bash
sudo cp configs/splunk/inputs.conf /opt/splunkforwarder/etc/system/local/
sudo chown splunkfwd:splunkfwd /opt/splunkforwarder/etc/system/local/inputs.conf
sudo -u splunkfwd /opt/splunkforwarder/bin/splunk restart
```

## Configuración outputs — vía proxy hacia Splunk Cloud

Archivo: `configs/splunk/outputs.conf`

```ini
# /opt/splunkforwarder/etc/system/local/outputs.conf

[tcpout]
defaultGroup = splunk_cloud_proxy

[tcpout:splunk_cloud_proxy]
server = 10.250.5.12:8444
sslVerifyServerCert = true
sslRootCAPath = /etc/pki/tls/certs/icasa-ca.crt
clientCert = /opt/splunkforwarder/etc/auth/proxy-client.pem
useClientSSLCompression = true
```

> **Nota:** Ajustar `server` y certificados cuando se reciba la URL definitiva de Splunk Cloud. El proxy Nginx en `:8444` reenvía al endpoint cloud.

Alternativa con HEC (para eventos estructurados):

```ini
# props.conf + transforms o usar SC4SNMP HEC output
```

## Firewall

Solicitar apertura:

| Origen | Destino | Puerto | Protocolo |
|--------|---------|--------|-----------|
| Equipos red (LAN) | `10.2.32.179` | 514 | TCP |
| `10.2.32.179` | `10.250.5.12` | 8444 | TCP |

## Configuración en dispositivos de red

Ejemplo genérico (Cisco IOS):

```
logging host 10.2.32.179 transport tcp port 514
logging trap informational
```

Ejemplo Linux (rsyslog):

```
*.* @@10.2.32.179:514
```

## Verificación

```bash
# Verificar que UF escucha en 514
sudo ss -tlnp | grep 514

# Test local
logger -n 10.2.32.179 -P 514 -T "Test syslog ICASA DEV"

# Verificar en Splunk Cloud (cuando esté configurado)
# index=network sourcetype=syslog | head 10
```

## Troubleshooting

| Síntoma | Solución |
|---------|----------|
| No llegan eventos | Verificar firewall LAN → MONITOR :514 |
| UF no reenvía | Verificar outputs.conf y conectividad a proxy |
| Cert SSL error | Importar CA del proxy en UF |
| Sourcetype incorrecto | Ajustar inputs.conf por tipo de dispositivo |

## Referencias

- [Splunk — Configure Syslog Input](https://docs.splunk.com/Documentation/Splunk/latest/Data/MonitorSyslog)
- [Splunk UF — outputs.conf](https://docs.splunk.com/Documentation/Splunk/latest/Admin/Outputsconf)
