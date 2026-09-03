#!/bin/ash
# Railway boot shim for the Pterodactyl Panel.
#
# Runs before upstream's own entrypoint, then hands over to it. Everything here
# is a Railway-specific fix; the panel itself is untouched.
set -e

log() { echo "[railway] $*"; }
die() { echo "[railway] FATAL: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Required credentials. Refuse to boot rather than come up unusable.
# ---------------------------------------------------------------------------
[ -n "$PTERODACTYL_ADMIN_EMAIL" ] || die "PTERODACTYL_ADMIN_EMAIL is empty. Set it and redeploy."
[ -n "$PTERODACTYL_ADMIN_PASSWORD" ] || die "PTERODACTYL_ADMIN_PASSWORD is empty. Set it and redeploy."
case "$PTERODACTYL_ADMIN_EMAIL" in
  *@*.*) : ;;
  *) die "PTERODACTYL_ADMIN_EMAIL ($PTERODACTYL_ADMIN_EMAIL) is not a valid address." ;;
esac
# Pterodactyl's own password rule: at least 8 characters, mixed case and a digit.
if [ "$(printf %s "$PTERODACTYL_ADMIN_PASSWORD" | wc -c)" -lt 8 ]; then
  die "PTERODACTYL_ADMIN_PASSWORD must be at least 8 characters."
fi

: "${PTERODACTYL_ADMIN_USERNAME:=admin}"
: "${PTERODACTYL_ADMIN_FIRST_NAME:=Panel}"
: "${PTERODACTYL_ADMIN_LAST_NAME:=Administrator}"
export PTERODACTYL_ADMIN_USERNAME PTERODACTYL_ADMIN_FIRST_NAME PTERODACTYL_ADMIN_LAST_NAME

# ---------------------------------------------------------------------------
# 2. The volume. Upstream keeps APP_KEY and HASHIDS_SALT in /app/var/.env and
#    assumes something has created that directory; with no volume mounted the
#    file writes fail, the symlink at /app/.env dangles, and the salt that
#    encodes every allocation, subuser, schedule, database and task id is
#    regenerated on every boot.
# ---------------------------------------------------------------------------
mkdir -p /app/var
if [ ! -w /app/var ]; then
  die "/app/var is not writable. A volume must be mounted there."
fi

# ---------------------------------------------------------------------------
# 3. Public URL. Without APP_URL the panel builds every asset, redirect and
#    e-mail link from http://localhost.
# ---------------------------------------------------------------------------
if [ -z "$APP_URL" ] && [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
  APP_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
  export APP_URL
fi
log "APP_URL=${APP_URL:-<unset>}"

# ---------------------------------------------------------------------------
# 4. Listen port. Upstream's nginx config hardcodes `listen 80;` and Railway's
#    HTTP healthcheck dials the port it injected, not the domain's target port.
# ---------------------------------------------------------------------------
LISTEN_PORT="${PORT:-80}"
mkdir -p /etc/nginx/http.d
sed "s/listen 80;/listen ${LISTEN_PORT};/" /app/.github/docker/default.conf \
  > /etc/nginx/http.d/panel.conf
grep -q "listen ${LISTEN_PORT};" /etc/nginx/http.d/panel.conf \
  || die "could not rewrite the nginx listen port"
rm -f /etc/nginx/http.d/default.conf
log "nginx listening on ${LISTEN_PORT}"

# ---------------------------------------------------------------------------
# 5. Dependencies. Upstream waits for the database only. When Redis is not
#    resolvable yet, `php artisan migrate --seed --force` aborts on the cache
#    connection, the schema is never created, and every page then answers 500
#    on a container the platform reports healthy.
# ---------------------------------------------------------------------------
wait_for() {
  name="$1"; host="$2"; port="$3"; tries=0
  [ -n "$host" ] || { log "no host for $name, skipping wait"; return 0; }
  while [ "$tries" -lt 90 ]; do
    if nc -z "$host" "$port" 2>/dev/null; then
      log "$name reachable at $host:$port"
      return 0
    fi
    tries=$((tries + 1))
    sleep 2
  done
  die "$name at $host:$port did not become reachable within 180s"
}
wait_for database "$DB_HOST" "${DB_PORT:-3306}"
wait_for redis "$REDIS_HOST" "${REDIS_PORT:-6379}"

# Upstream's own wait loop runs next and is now a no-op.
exec /bin/ash /app/.github/docker/entrypoint.sh /usr/local/bin/railway-start.sh "$@"
