FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends squid \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/spool/squid /var/log/squid \
    && chown -R proxy:proxy /var/spool/squid /var/log/squid

COPY squid.conf /etc/squid/squid.conf

# Squid necesita inicializar estructura de cache aunque cache deny all
RUN squid -z -f /etc/squid/squid.conf 2>/dev/null || true

EXPOSE 3128
CMD ["sh", "-c", "squid -N -f /etc/squid/squid.conf & tail -F /var/log/squid/access.log /var/log/squid/cache.log"]
