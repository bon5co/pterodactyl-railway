# Pterodactyl Panel, packaged for Railway.
#
# Pinned to upstream v1.15.1 by digest. The upstream image is unchanged; this
# wrapper only adds the boot sequence Railway needs:
#
#   * nginx listens on the injected $PORT instead of the baked-in port 80
#   * the panel waits for BOTH MySQL and Redis before running migrations
#   * an administrator is created before nginx opens the public port, and the
#     password is re-applied on every boot so a redeploy is a working reset
#   * literals that would otherwise publish as blank required template fields
#     are baked in here
FROM ghcr.io/pterodactyl/panel:v1.15.1@sha256:e27a06cfcd078691ddf9805ae0dee2ee529b35ce18e427ef970de4d503602f2c

# Railway terminates TLS at the edge and forwards over plain HTTP, so the panel
# has to trust the proxy or every generated URL comes back as http:// and the
# client IP in the audit log is the edge address.
ENV TRUSTED_PROXIES="*" \
    APP_ENV="production" \
    APP_DEBUG="false" \
    APP_ENVIRONMENT_ONLY="false" \
    APP_TIMEZONE="UTC" \
    LOG_CHANNEL="stderr" \
    CACHE_DRIVER="redis" \
    SESSION_DRIVER="redis" \
    QUEUE_CONNECTION="redis" \
    DB_CONNECTION="mysql" \
    MAIL_MAILER="log" \
    RECAPTCHA_ENABLED="false" \
    PTERODACTYL_TELEMETRY_ENABLED="false"

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY railway-start.sh /usr/local/bin/railway-start.sh
COPY seed-admin.php /usr/local/bin/seed-admin.php

RUN chmod +x /usr/local/bin/railway-entrypoint.sh /usr/local/bin/railway-start.sh \
 && test -f /app/.github/docker/entrypoint.sh \
 && test -f /app/.github/docker/default.conf \
 && grep -q 'listen 80;' /app/.github/docker/default.conf \
 && test -f /app/app/Console/Commands/User/MakeUserCommand.php

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisord.conf"]
