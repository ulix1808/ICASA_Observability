# ICASA Observability

Documentación técnica para la implementación de observabilidad en **ICASA**, ambiente **DEV**.

Repositorio: [github.com/ulix1808/ICASA_Observability](https://github.com/ulix1808/ICASA_Observability)

## Alcance

| Componente | Tecnología | Servidor |
|------------|-----------|----------|
| APM — SQL Server | AppDynamics Database Agent | RHEL 9 — Colector `10.2.32.180` |
| APM — IIS | AppDynamics .NET Agent + Machine Agent | Windows Server (LAN) |
| APM — SAP | ABAP Agent + HTTP SDK + Machine Agent | SAP (LAN) + HTTP SDK en colector |
| Proxy salida | Nginx reverse proxy | RHEL 9 DMZ — `10.250.5.12` |
| Logs | Syslog TCP/514 → Splunk Cloud | Colector → Proxy → Cloud |
| SNMP | Splunk Connect for SNMP (SC4SNMP) | RHEL 9 — Colector `10.2.32.180` |
| Controller APM | AppDynamics SaaS | `teresa202606020142139.saas.appdynamics.com` |

## Arquitectura de red

```
LAN (10.2.x.x)                         DMZ                         Internet
┌─────────────────────────┐    ┌──────────────────┐    ┌─────────────────────────┐
│ STMPLPOCOB COLECTOR     │    │ Firewall         │    │ AppDynamics SaaS        │
│ 10.2.32.180             │───►│                  │───►│ teresa...appdynamics.com│
│  • Database Agent       │443 │ STMPDMZPOCOB     │443 │ analytics.api.appd...   │
│  • HTTP SDK (SAP)       │    │ PROXY            │    ├─────────────────────────┤
│  • SC4SNMP              │    │ 10.250.5.12      │    │ Splunk Cloud            │
│  • Splunk UF (syslog)   │    │ (Nginx RHEL 9)   │    │ (URL pendiente licencia)│
└─────────────────────────┘    └──────────────────┘    └─────────────────────────┘
         ▲
         │ Syslog TCP/514, SNMP
   Servidores, equipos de red, SAP, SQL Server, IIS
```

## Descargas de instaladores

| Paquete | Versión | Descarga |
|---------|---------|----------|
| AppDynamics Database Agent | 26.4.0.5606 | [packages/db-agent-26.4.0.5606.zip](packages/db-agent-26.4.0.5606.zip) |

Después de descomprimir, reemplazar `conf/controller-info.xml` con el del repo:

```bash
unzip db-agent-26.4.0.5606.zip -d /opt/appdynamics/
cp db-agent/conf/controller-info.xml /opt/appdynamics/db-agent-26.4.0.5606/conf/
```

URL directa:

```
https://github.com/ulix1808/ICASA_Observability/raw/main/packages/db-agent-26.4.0.5606.zip
```

## Documentación

| # | Tema | Archivo |
|---|------|---------|
| 0 | Arquitectura general | [docs/00-arquitectura/arquitectura-general.md](docs/00-arquitectura/arquitectura-general.md) |
| 1 | Proxy Nginx + certificados TLS | [docs/01-proxy-nginx/](docs/01-proxy-nginx/) |
| 2 | Database Agent (RHEL 9 + SQL Server) | [docs/02-database-agent/](docs/02-database-agent/) |
| 3 | .NET Agent + IIS | [docs/03-dotnet-agent-iis/](docs/03-dotnet-agent-iis/) |
| 4 | SAP Monitoring | [docs/04-sap-monitoring/](docs/04-sap-monitoring/) |
| 5 | Splunk Syslog | [docs/05-splunk-syslog/](docs/05-splunk-syslog/) |
| 6 | Splunk Connect for SNMP | [docs/06-splunk-sc4snmp/](docs/06-splunk-sc4snmp/) |

## Configuraciones y scripts

```
configs/
├── nginx/              # Virtual hosts AppDynamics + Splunk
├── database-agent/     # controller-info.xml, systemd unit
├── dotnet-agent/       # config.xml de ejemplo
├── sap/                # Referencias de transports
└── splunk/             # UF, SC4SNMP, syslog inputs

scripts/
├── install-nginx-proxy.sh
├── install-db-agent.sh
├── generate-certs-selfsigned.sh
├── install-truststore-agent.sh
└── install-sc4snmp.sh
```

## Variables de entorno

Copiar `.env.example` a `.env` y completar valores reales. **No commitear `.env`**.

```bash
cp .env.example .env
```

## Controller AppDynamics (DEV)

| Parámetro | Valor |
|-----------|-------|
| Controller Host | `teresa202606020142139.saas.appdynamics.com` |
| Controller Port | `443` |
| SSL | Habilitado |
| Account Name | `teresa202606020142139` |
| Account Access Key | Ver `.env` — **no incluir en el repo** |

## Orden de implementación recomendado

1. **Proxy Nginx** en DMZ (`10.250.5.12`) + certificados TLS
2. **Validar conectividad** proxy → AppDynamics SaaS y Splunk Cloud
3. **Database Agent** en colector (`10.2.32.180`)
4. **Splunk UF + Syslog** en colector
5. **SC4SNMP** en colector
6. **.NET Agent** en servidores IIS (LAN)
7. **SAP ABAP Agent** (imports TMS por equipo BASIS)
8. **HTTP SDK** en colector + configuración ABAP Agent

## Referencias oficiales

- [AppDynamics SaaS — Database Agent](https://help.splunk.com/en/appdynamics-saas/database-visibility/25.8.0/administer-the-database-agent/install-the-database-agent)
- [AppDynamics — Use a Reverse Proxy](https://help.splunk.com/en/appdynamics-on-premises/controller-deployment/26.4.0/controller-deployment/administer-the-controller/use-a-reverse-proxy)
- [SAP Monitoring — Cisco AppDynamics](https://help.splunk.com/en/appdynamics-sap-agent/sap-monitoring/sap-monitoring-using-cisco-appdynamics)
- [Splunk Connect for SNMP](https://splunk.github.io/splunk-connect-for-snmp/main/)

## Pendientes por definir

Ver [docs/00-arquitectura/pendientes.md](docs/00-arquitectura/pendientes.md).
