<?php
/**
 * Siwang Document Control — self-service registration.
 *
 * Left switched on from the UAT phase (checklist item MWS-402, never done).
 *
 * Note what this does NOT do: it never reads a role from the request. The
 * INSERT hardcodes 'user', so there is no mass-assignment shortcut here --
 * submitting role=admin, role[]=admin or is_admin=1 to this form achieves
 * exactly nothing. Escalation has to go through the session-forging flaw.
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

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();

    $username = trim(req_str($_POST, 'username'));
    $email    = trim(req_str($_POST, 'email'));
    $password = req_str($_POST, 'password');
    $confirm  = req_str($_POST, 'confirm');

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
            // role is hardcoded. It is not, and must not become, request data.
            $insert = db()->prepare(
                "INSERT INTO users (username, email, password_hash, role)
                 VALUES (:username, :email, :hash, 'user')"
            );
            $insert->execute([
                ':username' => $username,
                ':email'    => ($email === '' ? null : $email),
                ':hash'     => password_hash($password, PASSWORD_BCRYPT),
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
