<?php
/**
 * Siwang Document Control — sign out.
 *
 * Clears the session and the "keep me signed in" cookie. Worth noting for the
 * debrief: signing out cannot undo a forged session, because the attacker
 * simply re-sends their own cookie. Server-side session invalidation does not
 * help when the server trusts the client's copy of the identity.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

logout_user();

header('Location: /login.php');
exit;
