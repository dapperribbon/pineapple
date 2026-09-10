<?php
/**
 * Siwang Document Control — self-service registration.
 *
 * Left switched on from the UAT phase (checklist item MWS-402, never done).
 *
 * Role IS read from the request here, but only through a fixed non-privileged
 * allowlist ('user', 'auditor'). This is a deliberate breadcrumb for Stage 2:
 * letting the student pick a role at sign-up puts the word "role" in front of
 * them and makes it show up, length-prefixed, inside the serialized
 * siwang_remember cookie -- the exact field they need to tamper. It is NOT a
 * mass-assignment shortcut: anything outside the allowlist, 'admin' included,
 * is coerced back to 'user' server-side, so role=admin / role[]=admin / is_admin=1
 * against this form still achieves exactly nothing. Escalation to admin still
 * has to go through the session-forging flaw -- "exactly one path" is intact.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

if (is_logged_in()) {
    header('Location: /dashboard.php');
    exit;
}

$errors   = [];
$username = '';
$email    = '';

/*
 * Roles a self-service account may choose. Keys are the values stored in the
 * users.role ENUM; the labels are display only. 'admin' is deliberately absent
 * -- see the file header. Keep this in sync with the ENUM in db/schema.sql.
 */
$selectableRoles = [
    'user'    => 'Standard user — register and search documents',
    'auditor' => 'Auditor — read-only reviewer',
];
$role = 'user';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();

    $username = trim(req_str($_POST, 'username'));
    $email    = trim(req_str($_POST, 'email'));
    $password = req_str($_POST, 'password');
    $confirm  = req_str($_POST, 'confirm');
    $role     = req_str($_POST, 'role', 'user');

    // Coerce anything outside the non-privileged allowlist back to 'user'.
    // This is the gate that keeps the dropdown a breadcrumb and not a promotion
    // channel: submitting role=admin lands a plain 'user' account, silently.
    if (!isset($selectableRoles[$role])) {
        $role = 'user';
    }

    if (!preg_match('/\A[A-Za-z0-9_]{3,32}\z/', $username)) {
        $errors[] = 'Username must be 3–32 characters, letters, digits and underscores only.';
    }

    if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $errors[] = 'That does not look like a valid email address.';
    }

    if (strlen($password) < 8) {
        $errors[] = 'Password must be at least 8 characters.';
    }

    if ($password !== $confirm) {
        $errors[] = 'The two passwords do not match.';
    }

    if ($errors === []) {
        $stmt = db()->prepare('SELECT 1 FROM users WHERE username = :username');
        $stmt->execute([':username' => $username]);

        if ($stmt->fetch() !== false) {
            $errors[] = 'That username is already taken.';
        } else {
            // role is bound, but only ever one of the allowlisted, non-admin
            // values validated above -- never raw request data.
            $insert = db()->prepare(
                "INSERT INTO users (username, email, password_hash, role)
                 VALUES (:username, :email, :hash, :role)"
            );
            $insert->execute([
                ':username' => $username,
                ':email'    => ($email === '' ? null : $email),
                ':hash'     => password_hash($password, PASSWORD_BCRYPT),
                ':role'     => $role,
            ]);

            header('Location: /login.php?registered=1');
            exit;
        }
    }
}

page_header('Create an account');
?>

<div class="card card-narrow">
  <h2>Create a staging account</h2>

  <div class="msg msg-warn">
    Staging accounts are for testing the document-control rollout. Do not upload
    live customer paperwork to this environment.
  </div>

  <?php if ($errors !== []): ?>
    <div class="msg msg-bad">
      <?php foreach ($errors as $i => $err): ?>
        <?= $i > 0 ? '<br>' : '' ?><?= e($err) ?>
      <?php endforeach; ?>
    </div>
  <?php endif; ?>

  <form method="post" action="/register.php">
    <?= csrf_field() ?>

    <div class="field">
      <label for="username">Username</label>
      <input id="username" name="username" type="text" autocomplete="username"
             value="<?= e($username) ?>" required autofocus>
      <p class="hint">3–32 characters. Letters, digits and underscores.</p>
    </div>

    <div class="field">
      <label for="email">Email <span class="muted">(optional)</span></label>
      <input id="email" name="email" type="email" autocomplete="email" value="<?= e($email) ?>">
    </div>

    <div class="field">
      <label for="role">Account type</label>
      <select id="role" name="role">
        <?php foreach ($selectableRoles as $value => $label): ?>
          <option value="<?= e($value) ?>"<?= $role === $value ? ' selected' : '' ?>><?= e($label) ?></option>
        <?php endforeach; ?>
      </select>
      <p class="hint">Sets your directory role. Administrator accounts are provisioned by IT, not here.</p>
    </div>

    <div class="field">
      <label for="password">Password</label>
      <input id="password" name="password" type="password" autocomplete="new-password" required>
      <p class="hint">Minimum 8 characters.</p>
    </div>

    <div class="field">
      <label for="confirm">Confirm password</label>
      <input id="confirm" name="confirm" type="password" autocomplete="new-password" required>
    </div>

    <button class="btn" type="submit">Create account</button>
  </form>

  <div class="form-foot">
    Already have an account? <a href="/login.php">Sign in</a>.
  </div>
</div>

<?php page_footer(); ?>
