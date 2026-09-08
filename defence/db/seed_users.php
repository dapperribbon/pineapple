<?php
/**
 * Siwang lab -- seed the `users` table.
 *
 * Run by db/setup.sh. This exists as PHP rather than SQL for one reason:
 * bcrypt hashes cannot be written by hand, and a hardcoded hash that does not
 * match its documented password fails as a generic "invalid username or
 * password" -- which is genuinely awful to debug at the front of a classroom.
 * Generating them here means the passwords in the docs are always the real
 * passwords.
 *
 * Usage:  php seed_users.php <db-user> <db-pass> [db-host]
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "seed_users.php is a CLI script.\n");
    exit(1);
}

$dbUser = $argv[1] ?? null;
$dbPass = $argv[2] ?? null;
$dbHost = $argv[3] ?? '127.0.0.1';

if ($dbUser === null || $dbPass === null) {
    fwrite(STDERR, "usage: php seed_users.php <db-user> <db-pass> [db-host]\n");
    exit(1);
}

/*
 * The seeded cast.
 *
 * - mchoo  : the "owner" of the staging portal. Admin. Students never need
 *            these credentials -- Stage 2 forges an admin *session* rather
 *            than authenticating as anyone -- but the account has to exist so
 *            the admin UI has something to render and the seeded documents
 *            have an owner.
 * - jtan   : an ordinary colleague. Exists to make the user list look real.
 * - svc_dms: a dormant service account, disabled-looking. Pure set dressing.
 *
 * Passwords are long and random-looking on purpose. They are NOT part of any
 * intended path: there is no credential-guessing stage in this box, and a
 * weak admin password here would be an unintended shortcut straight past
 * Stage 2. Do not "helpfully" make them guessable.
 */
$users = [
    [
        'username' => 'mchoo',
        'email'    => 'm.choo@siwang-trading.example',
        'password' => 'Tq7#vLm2_BerthQ4!raa',
        'role'     => 'admin',
        'created'  => '2024-09-15 08:30:00',
    ],
    [
        'username' => 'jtan',
        'email'    => 'j.tan@siwang-trading.example',
        'password' => 'k4Nw!8sPz_Tuas#0912x',
        'role'     => 'user',
        'created'  => '2024-09-15 08:41:00',
    ],
    [
        'username' => 'svc_dms',
        'email'    => null,
        'password' => 'B2v#Qd91_svcDMS!7wTn',
        'role'     => 'user',
        'created'  => '2024-09-16 13:05:00',
    ],
];

try {
    $pdo = new PDO(
        "mysql:host={$dbHost};dbname=siwang_dev;charset=utf8mb4",
        $dbUser,
        $dbPass,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    fwrite(STDERR, "seed_users.php: cannot connect: " . $e->getMessage() . "\n");
    exit(1);
}

$stmt = $pdo->prepare(
    'INSERT INTO users (username, email, password_hash, role, created_at)
     VALUES (:username, :email, :hash, :role, :created)'
);

foreach ($users as $u) {
    $stmt->execute([
        ':username' => $u['username'],
        ':email'    => $u['email'],
        ':hash'     => password_hash($u['password'], PASSWORD_BCRYPT),
        ':role'     => $u['role'],
        ':created'  => $u['created'],
    ]);
    printf("  seeded %-8s (%s)\n", $u['username'], $u['role']);
}

echo "  " . count($users) . " accounts created.\n";
