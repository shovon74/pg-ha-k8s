# ADR-003: official Postgres plus exact PGDG Patroni and pgBackRest. Inputs come from versions.env.
ARG POSTGRES_BASE_IMAGE
FROM ${POSTGRES_BASE_IMAGE}

ARG PATRONI_DEB_VERSION
ARG PGBACKREST_DEB_VERSION

USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        "patroni=${PATRONI_DEB_VERSION}" "pgbackrest=${PGBACKREST_DEB_VERSION}"; \
    rm -rf /var/lib/apt/lists/*; \
    install -d -o postgres -g postgres -m 0750 \
        /etc/patroni /etc/pgbackrest /etc/pgbackrest/conf.d \
        /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest

# Numeric UID so Kubernetes runAsNonRoot can verify it. Bypasses the root entrypoint.
USER 999:999
ENTRYPOINT ["/usr/bin/patroni"]
CMD ["/etc/patroni/patroni.yml"]
