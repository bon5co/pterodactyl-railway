# pterodactyl-railway

A thin wrapper around the official [Pterodactyl Panel](https://pterodactyl.io) image
(`ghcr.io/pterodactyl/panel`, pinned to v1.15.1 by digest) that makes it deploy correctly on
Railway. The panel itself is unmodified; everything here is a platform fix.

Published as `ghcr.io/bon5co/pterodactyl-railway:v1.15.1`.

## What the wrapper adds

| Fix | Why it is needed |
| --- | --- |
| nginx listens on the injected `$PORT` | Upstream's `default.conf` hardcodes `listen 80;`, and Railway's HTTP healthcheck dials the port it injected rather than the domain's target port. |
| Waits for Redis as well as the database | Upstream's entrypoint waits for the database only. With `CACHE_DRIVER=redis` and `SESSION_DRIVER=redis`, `php artisan migrate --seed --force` aborts on the cache connection if Redis is not resolvable yet, and the schema is never created. |
| Fails the deploy when the migration fails | Upstream's entrypoint does not stop on a failed migration: the container reaches supervisord, serves HTTP 500 on every page, and the platform reports the deployment healthy. |
| Seeds an administrator before nginx binds | The panel has no signup page and no seeding variable of its own, so a stock deploy has no account and no way to create one. |
| Re-applies the credential on every boot | Pterodactyl ships `p:user:make`, `p:user:delete` and `p:user:disable2fa` and no command that changes an existing user's credential; recovery is an emailed reset link, which a fresh deploy has no mail transport for. Re-applying it makes a redeploy a working reset. |
| `APP_URL` derived from `RAILWAY_PUBLIC_DOMAIN` | Without it the panel builds every asset, redirect and e-mail link from `http://localhost`. |
| `TRUSTED_PROXIES=*` | Railway terminates TLS at the edge and forwards plain HTTP. |
| reCAPTCHA off | `config/recaptcha.php` defaults `enabled` to true with Pterodactyl's shipped shared keys and `verify_domain => true`, which does not match a `*.up.railway.app` hostname. |
| Telemetry off | `config/pterodactyl.php` defaults `telemetry.enabled` to true and the console kernel schedules a daily push. |
| Literals baked in | `templateGenerate` drops a literal `defaultValue`, so a literal-valued template variable publishes as a blank required field on the deploy form. |

## Environment

Required:

- `PTERODACTYL_ADMIN_EMAIL` — administrator address; the container refuses to boot without it.
- `PTERODACTYL_ADMIN_PASSWORD` — at least 8 characters; the container refuses to boot without it.
- `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`
- `APP_KEY` (32 characters) and `HASHIDS_SALT` — written to `/app/var/.env` on first boot and read
  from there afterwards, so they must survive on the volume.

Optional: `PTERODACTYL_ADMIN_USERNAME` (default `admin`), `PTERODACTYL_ADMIN_FIRST_NAME`,
`PTERODACTYL_ADMIN_LAST_NAME`, `APP_URL`.

A volume must be mounted at `/app/var`.

## Use MariaDB, not MySQL

The upstream panel image ships MariaDB's client binaries. Laravel's migration loads
`database/schema/mysql-schema.sql` by shelling out to that client, and a recent MariaDB client
verifies the server certificate by default, so against the official MySQL image — whose
auto-generated certificate is self-signed — the schema load fails:

```
database/schema/mysql-schema.sql .............................. FAIL
ERROR 2026 (HY000): TLS/SSL error: self-signed certificate in certificate chain
```

Measured against `mysql:9`: zero tables in the database afterwards. Pair the panel with MariaDB.

## The panel is not a game server host

Pterodactyl separates the panel from Wings, the daemon that actually runs game servers. Wings
needs privileged Docker access, which Railway does not grant, so this deployment is the panel and
its API — point it at a Wings node you run elsewhere.
