# Puertos Splunk — Diseño aprobado por el cliente

## Requisito del cliente

> **Hacia afuera (DMZ → Internet): solo puerto 443.**  
> **Hacia el proxy (LAN → DMZ): puerto 8444** para tráfico Splunk. Nginx separa el tráfico por listener.

Este diseño cumple ambos requisitos.

## Resumen de puertos

| Tramo | Puerto | Rol |
|-------|--------|-----|
| LAN → Proxy (`10.250.5.12`) — AppDynamics | **443** | Database Agent, .NET Agent, HTTP SDK, Machine Agent |
| LAN → Proxy (`10.250.5.12`) — Splunk | **8444** | Splunk UF, SC4SNMP (HEC) |
| LAN → Proxy (`10.250.5.12`) — Analytics SAP | **8443** | Analytics Events API (opcional) |
| **Proxy → Internet** — AppDynamics | **443** | Hacia `*.saas.appdynamics.com` |
| **Proxy → Internet** — Splunk Cloud | **443** | Hacia `*.splunkcloud.com` (HEC oficial) |

```
┌──────────── LAN ────────────┐     ┌──── DMZ Proxy ────┐     ┌── Internet ──┐
│ UF / SC4SNMP                │     │ Nginx             │     │ Splunk Cloud │
│  ──8444──► 10.250.5.12:8444 │────►│ listen :8444      │────►│    :443      │
│                             │     │ proxy_pass → :443 │     └──────────────┘
│ DB Agent / .NET / SAP SDK   │     │                   │
│  ──443───► 10.250.5.12:443  │────►│ listen :443       │────► AppDynamics :443
└─────────────────────────────┘     └───────────────────┘
```

## Cómo Nginx separa el tráfico

Nginx en `10.250.5.12` usa **listeners distintos** en la LAN; hacia Internet todo sale por **443**:

| Listener Nginx (entrada LAN) | Config | Upstream (salida Internet) |
|-----------------------------|--------|--------------------------|
| `:443` | `configs/nginx/appdynamics-upstream.conf` | `teresa202606020142139.saas.appdynamics.com:443` |
| `:8443` | `configs/nginx/appdynamics-upstream.conf` | `analytics.api.appdynamics.com:443` |
| `:8444` | `configs/nginx/splunk-upstream.conf` | `*.splunkcloud.com:443` |

Ejemplo flujo Splunk:

```
https://10.250.5.12:8444/services/collector/event   (LAN → proxy)
         ↓ Nginx termina TLS, reenvía HTTPS
https://input-xxx.splunkcloud.com:443/services/collector/event   (proxy → Internet)
```

## Reglas de firewall

### LAN → DMZ (entrada al proxy)

| Origen | Destino | Puerto | Uso |
|--------|---------|--------|-----|
| `10.2.32.179`, `10.2.32.180`, IIS | `10.250.5.12` | **443** | AppDynamics |
| `10.2.32.179`, `10.2.32.180` | `10.250.5.12` | **8444** | Splunk HEC |
| SAP (analytics, si aplica) | `10.250.5.12` | **8443** | Analytics Events |

### DMZ → Internet (salida — solo 443)

| Origen | Destino | Puerto |
|--------|---------|--------|
| `10.250.5.12` | `*.saas.appdynamics.com` | **443** |
| `10.250.5.12` | `analytics.api.appdynamics.com` | **443** |
| `10.250.5.12` | `*.splunkcloud.com` | **443** |

> El **8444 no se abre hacia Internet**. Solo existe en la interfaz LAN→DMZ para que Nginx distinga tráfico Splunk del tráfico AppDynamics.

## Splunk Cloud — puerto oficial

Según [documentación Splunk HEC](https://help.splunk.com/en/splunk-cloud-platform/get-started/get-data-in/10.2.2510/get-data-with-http-event-collector/set-up-and-use-http-event-collector-in-splunk-web):

- **Producción:** HEC en puerto **443**
- **Trial / free tier:** HEC en puerto **8088**

ICASA usa producción → el proxy reenvía a **443**.

## Universal Forwarder — nota

Si Splunk indica que el UF debe usar **tcpout en 9997** (protocolo Splunk nativo, no HTTP), habrá que evaluar proxy TCP (`nginx stream`) o método HEC sobre `:8444`. Validar cuando se reciba la URL y credenciales de Splunk Cloud.

## Referencias

- [HEC — Splunk Cloud](https://help.splunk.com/en/splunk-cloud-platform/get-started/get-data-in/10.2.2510/get-data-with-http-event-collector/set-up-and-use-http-event-collector-in-splunk-web)
- [Proxy Nginx — instalación](../01-proxy-nginx/instalacion-rhel9.md)
- `configs/nginx/splunk-upstream.conf`
- `configs/nginx/appdynamics-upstream.conf`
