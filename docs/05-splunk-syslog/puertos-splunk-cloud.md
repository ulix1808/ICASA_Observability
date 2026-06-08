# Puertos Splunk Cloud — Validación

## Respuesta corta

**No.** El puerto **8444 NO es el puerto de Splunk Cloud**. Es un puerto **interno** del proxy Nginx en ICASA para separar el tráfico Splunk del tráfico AppDynamics.

| Tramo | Puerto | ¿Validado? |
|-------|--------|------------|
| LAN → Proxy Nginx (`10.250.5.12`) | **8444** | Elección de diseño ICASA (listener Nginx para HEC) |
| Proxy → Splunk Cloud (Internet) | **443** | **Sí** — puerto oficial HEC en producción |
| Splunk Cloud trial / free tier HEC | **8088** | Alternativa según [documentación Splunk](https://help.splunk.com/en/splunk-cloud-platform/get-started/get-data-in/10.2.2510/get-data-with-http-event-collector/set-up-and-use-http-event-collector-in-splunk-web) |

## Por qué usamos 8444 en el proxy

Nginx escucha en varios puertos en `10.250.5.12`:

| Puerto proxy | Upstream | Uso |
|--------------|----------|-----|
| **443** | `teresa202606020142139.saas.appdynamics.com:443` | Agentes AppDynamics |
| **8443** | `analytics.api.appdynamics.com:443` | Analytics Events (SAP) |
| **8444** | `*.splunkcloud.com:443` | HEC Splunk (SC4SNMP, ingest HTTP) |

El proxy **termina TLS en 8444** y reenvía a Splunk Cloud en **443**:

```
SC4SNMP / HEC  →  https://10.250.5.12:8444/services/collector/event
                        ↓ (Nginx reverse proxy)
                  https://input-xxx.splunkcloud.com:443/services/collector/event
```

Configuración: `configs/nginx/splunk-upstream.conf` — upstream en puerto **443**.

## Reglas de firewall correctas

### Firewall LAN → DMZ

| Origen | Destino | Puerto |
|--------|---------|--------|
| `10.2.32.179`, `10.2.32.180` | `10.250.5.12` | **8444** TCP |

### Firewall DMZ → Internet (Splunk)

| Origen | Destino | Puerto |
|--------|---------|--------|
| `10.250.5.12` | `*.splunkcloud.com` (URL definitiva) | **443** TCP |

> **No abrir 8444 hacia Internet.** Splunk Cloud no escucha en ese puerto.

## Universal Forwarder — consideración adicional

El **Splunk UF** en `10.2.32.179` puede usar dos métodos hacia Splunk Cloud:

| Método | Puerto hacia Cloud | Notas |
|--------|-------------------|-------|
| **HEC (HTTP)** | 443 vía proxy `:8444` | Compatible con nuestro Nginx HTTP reverse proxy |
| **Splunk-to-Splunk (tcpout)** | **9997** típico | Protocolo propietario; requiere `splunkclouduf.spl` y posiblemente proxy TCP (nginx `stream`), no HTTP |

Cuando se reciba la URL y credenciales de Splunk Cloud, validar con el admin de Splunk cuál método aplica. Si es tcpout nativo (`9997`), habrá que ajustar el proxy o abrir **443/9997** directamente según indique Splunk.

Referencias:
- [HEC — Splunk Cloud](https://help.splunk.com/en/splunk-cloud-platform/get-started/get-data-in/10.2.2510/get-data-with-http-event-collector/set-up-and-use-http-event-collector-in-splunk-web)
- [UF credentials — Splunk Cloud](https://help.splunk.com/en/splunk-cloud-platform/forward-and-process-data/universal-forwarder-manual/10.4/configure-the-universal-forwarder/enable-a-receiver-for-the-splunk-cloud-platform)
