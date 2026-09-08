<?php
/**
 * Siwang Document Control — signed-in account.
 *
 * A plain data holder. It is passed to serialize() by the "keep me signed in"
 * feature in auth.php, which is why it stays deliberately boring.
 *
 * -------------------------------------------------------------------------
 * LAB NOTE (not visible to students — this file is not served over HTTP;
 * see the <Directory /var/www/dev/includes> deny rule in the Apache vhost).
 *
 * This class MUST NOT gain any magic method — no __wakeup(), __destruct(),
 * __toString(), __call(), __get() or __set(). It is reachable from
 * unserialize() with attacker-controlled input, so any magic method here
 * becomes a POP gadget, and a gadget that touches the filesystem or the shell
 * would hand students arbitrary file access as www-data without ever solving
 * Stage 3. That is exactly the unintended path this box is built to avoid.
 *
 * isAdmin() is a normal method and is never invoked during deserialization,
 * so it is safe.
 * -------------------------------------------------------------------------
 */

declare(strict_types=1);

class User
{
    /** @var int */
    public $id;

    /** @var string */
    public $username;

    /** @var string 'user' or 'admin' */
    public $role;

    public function __construct(int $id = 0, string $username = '', string $role = 'user')
    {
        $this->id       = $id;
        $this->username = $username;
        $this->role     = $role;
    }

    public function isAdmin(): bool
    {
        return $this->role === 'admin';
    }
}
