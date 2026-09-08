<?php
/**
 * Siwang Document Control — sign in.
 *
 * Authentication itself is sound: bound query, bcrypt verification, a single
 * generic failure message (so the form cannot be used to enumerate accounts),
 * and a dummy hash comparison on the miss path so a wrong username and a wrong
 * password take comparable time.
 *
 * The weakness is not here. It is in what login_user() writes to the browser
 * when "keep me signed in" is ticked -- see includes/auth.php.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

if (is_logged_in()) {
    header('Location: /dashboard.php');
    exit;
}

$error    = '';
$username = '';
$notice   = isset($_GET['registered']) ? 'Account created. You can sign in now.' : '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();

    $username = trim(req_str($_POST, 'username'));
    $password = req_str($_POST, 'password');
    $remember = isset($_POST['remember']);

    if ($username === '' || $password === '') {
        $error = 'Enter your username and password.';
    } else {
        $stmt = db()->prepare(
            'SELECT id, username, password_hash, role FROM users WHERE username = :username'
        );
        $stmt->execute([':username' => $username]);
        $row = $stmt->fetch();

        if ($row !== false && password_verify($password, (string) $row['password_hash'])) {
            login_user($row, $remember);
            header('Location: /dashboard.php');
            exit;
        }

        // Constant-ish work on the miss path: without this, a non-existent
        // username returns noticeably faster than a wrong password.
        password_verify($password, '$2y$10$usesomesillystringfore7hnbRJHxXVLeakoG8K30M1MvpsUZBu6');

        $error = 'Invalid username or password.';
    }
}

page_header('Sign in');
?>

<div class="card card-narrow">
  <h2>Sign in</h2>

  <?php if ($notice !== ''): ?>
    <div class="msg msg-good"><?= e($notice) ?></div>
  <?php endif; ?>

  <?php if ($error !== ''): ?>
    <div class="msg msg-bad"><?= e($error) ?></div>
  <?php endif; ?>

  <form method="post" action="/login.php">
    <?= csrf_field() ?>

    <div class="field">
      <label for="username">Username</label>
      <input id="username" name="username" type="text" autocomplete="username"
             value="<?= e($username) ?>" required autofocus>
    </div>

    <div class="field">
      <label for="password">Password</label>
      <input id="password" name="password" type="password" autocomplete="current-password" required>
    </div>

    <div class="check">
      <input id="remember" name="remember" type="checkbox" value="1">
      <label for="remember" style="text-transform:none;letter-spacing:0;font-size:0.92rem;font-weight:400;color:inherit;margin:0;">
        Keep me signed in on this device
      </label>
    </div>

    <button class="btn" type="submit">Sign in</button>
  </form>

  <div class="form-foot">
    Staging accounts are self-service during UAT —
    <a href="/register.php">create one</a>.<br>
    Production access is provisioned by the IT helpdesk.
  </div>
</div>

<?php page_footer(); ?>
