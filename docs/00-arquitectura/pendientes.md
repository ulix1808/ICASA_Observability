# Pendientes por definir — ICASA Observability DEV

Elementos marcados como pendientes que deben completarse antes o durante la implementación en producción.

## Red e infraestructura

| # | Item | Responsable | Notas |
|---|------|-------------|-------|
| 1 | FQDN definitivo del proxy | Infraestructura ICASA | Actualmente IP `10.250.5.12`; recomendado DNS interno |
| 2 | URL Splunk Cloud (HEC + UF) | Splunk / ICASA | Diagrama indica "PENDIENTE URL POR LICENCIA" |
| 3 | Reglas firewall detalladas | Seguridad ICASA | Permisos confirmados a nivel alto |

## SQL Server

| # | Item | Responsable | Notas |
|---|------|-------------|-------|
| 4 | IP/hostname SQL Server | DBA | Database Agent en `10.2.32.179` conecta por JDBC |
| 5 | Usuario SQL con permisos GRANT | DBA | Según documentación AppDynamics DB permissions |
| 6 | Tipo autenticación SQL | DBA | SQL Auth vs Windows Auth — pendiente |

## Windows / IIS

| # | Item | Responsable | Notas |
|---|------|-------------|-------|
| 7 | Cantidad servidores IIS | Apps | Instrumentación automática |
| 8 | Versión .NET Framework / Core | Apps | Validar compatibilidad .NET Agent |
| 9 | Nombres de aplicación AppDynamics | Apps | Por sitio IIS |

## SAP

| # | Item | Responsable | Notas |
|---|------|-------------|-------|
| 10 | Versión NetWeaver | BASIS | Define carpeta ABAP Agent (740 vs anterior) |
| 11 | Sistemas SAP (SID, ambientes) | BASIS | DEV/QAS/PRD |
| 12 | SO app servers SAP | BASIS | Afecta Machine Agent e HTTP SDK |
| 13 | Descarga instaladores SAP | ICASA | Portal accounts.appdynamics.com/downloads |
| 14 | Ventana mantenimiento TMS | BASIS | Imports fuera de horario pico |

## Splunk

| # | Item | Responsable | Notas |
|---|------|-------------|-------|
| 15 | Índices y sourcetypes | Splunk admin | Syslog, SNMP, OS |
| 16 | Inventario dispositivos SNMP | Red | Número finito — definir IPs y comunidades/v3 |
| 17 | Credenciales SNMPv3 | Red | Vault o archivo cifrado |
| 18 | Token HEC Splunk Cloud | Splunk admin | Para SC4SNMP y UF |

## Certificados

| # | Item | Responsable | Notas |
|---|------|-------------|-------|
| 19 | CA corporativa vs autofirmado | Seguridad | Documentadas ambas opciones |
| 20 | Procedimiento distribución CA a agentes | Infra | Java truststore + Windows cert store |
