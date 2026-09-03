<?php
/**
 * Create the panel's administrator, and re-apply the credential on every boot.
 *
 * Pterodactyl ships `p:user:make`, `p:user:delete` and `p:user:disable2fa` and
 * no command that changes an existing user's credential; the only recovery path
 * in the product is an emailed reset link, which a fresh deploy has no mail
 * transport for. Re-applying it here makes a redeploy a working reset.
 *
 * Runs after upstream's entrypoint has migrated the database and before
 * supervisord starts nginx, so the first request the public port ever serves is
 * against a panel that already has an owner. It doubles as the schema check the
 * boot sequence otherwise lacks: upstream does not stop when the migration
 * fails, so without this a panel with no tables reaches supervisord, answers 500
 * on every page, and is reported as a healthy deployment.
 */

require '/app/vendor/autoload.php';

$app = require_once '/app/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$email = getenv('PTERODACTYL_ADMIN_EMAIL');
$username = getenv('PTERODACTYL_ADMIN_USERNAME') ?: 'admin';
$secret = getenv('PTERODACTYL_ADMIN_PASSWORD');
$first = getenv('PTERODACTYL_ADMIN_FIRST_NAME') ?: 'Panel';
$last = getenv('PTERODACTYL_ADMIN_LAST_NAME') ?: 'Administrator';

if ($email === false || $email === '' || $secret === false || $secret === '') {
    fwrite(STDERR, "[railway] FATAL: administrator email or credential is empty\n");
    exit(1);
}

try {
    if (! Illuminate\Support\Facades\Schema::hasTable('users')) {
        throw new RuntimeException('the panel schema is missing; the migration did not run');
    }

    $user = Pterodactyl\Models\User::query()
        ->where('email', $email)
        ->orWhere('username', $username)
        ->first();

    if ($user === null) {
        $exit = Illuminate\Support\Facades\Artisan::call('p:user:make', [
            '--email' => $email,
            '--username' => $username,
            '--name-first' => $first,
            '--name-last' => $last,
            '--password' => $secret,
            '--admin' => 1,
        ]);
        echo trim(Illuminate\Support\Facades\Artisan::output()), "\n";
        if ($exit !== 0) {
            throw new RuntimeException("p:user:make exited {$exit}");
        }
        echo "[railway] administrator {$email} created\n";
        exit(0);
    }

    // Existing account: re-apply the credential so a redeploy resets it, and
    // make sure the account is still an administrator and still reachable.
    $user->forceFill([
        'email' => $email,
        'username' => $username,
        'password' => Illuminate\Support\Facades\Hash::make($secret),
        'root_admin' => true,
        'use_totp' => false,
        'totp_secret' => null,
    ])->saveOrFail();

    echo "[railway] administrator {$email} credential re-applied\n";
} catch (Throwable $e) {
    fwrite(STDERR, '[railway] FATAL: ' . $e->getMessage() . "\n");
    exit(1);
}
