#!/bin/ash
# Runs after upstream's entrypoint has migrated the database and before
# supervisord starts nginx. Seeding here rather than afterwards means the first
# request the public port ever serves is against a claimed panel.
set -e

# Upstream's entrypoint does not stop when `php artisan migrate --seed --force`
# fails, so a panel whose schema was never created still reaches supervisord,
# serves 500 on every page, and is reported as a healthy deployment. Fail the
# deploy instead.
echo "[railway] verifying schema"
if ! php /app/artisan migrate --force --no-interaction; then
    echo "[railway] FATAL: database migration failed" >&2
    exit 1
fi

echo "[railway] seeding administrator"
if ! php /usr/local/bin/seed-admin.php; then
    echo "[railway] FATAL: could not seed the administrator" >&2
    exit 1
fi

echo "[railway] handing over to supervisord"
exec "$@"
