<?php
/**
 * Siwang Document Control — entry point.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

header('Location: ' . (is_logged_in() ? '/dashboard.php' : '/login.php'));
exit;
