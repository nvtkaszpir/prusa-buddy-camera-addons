# Minimal settings

Set these before the first boot with the add-ons. Everything else has working defaults; the feature pages list the
optional settings.

Required on the card:

- **Your ssh public keys** in `/mnt/sdcard/bin/authorized_keys`. Needed for [ssh](../features/ssh.md),
  [rsync](../features/rsync.md) and `task buddy:sync`. Without it nobody can log in: password login is compiled out.
  `task buddy:stage` builds it from `SSH_PUBKEYS`.
- **A boot hook that still starts `lp_app`**, `/mnt/sdcard/lp_app.sh`. The hook runs instead of `lp_app`; without
  a final `lp_app` line there is no video, no Wi-Fi and so no add-on access. See
  [Installation](3-installation.md#4-add-the-boot-hook).
- **No active `telnetd` line** in `/mnt/sdcard/lp_app.sh`. If your hook starts `telnetd`, port 23 stays open with
  root login next to ssh. Comment it out once ssh works.
- **Basic auth users** in `/mnt/sdcard/bin/htpasswd`, only for [HTTPS](../features/https.md) with basic auth
  turned on. The shipped `lighttpd.conf` serves plain HTTP without a password and does not need it.
- **Syslog server address**, `target=` in `/mnt/sdcard/bin/rsyslog.conf`, only for
  [remote rsyslog](../features/rsyslog.md). rsyslog refuses to start while the `REMOTE_HOST` placeholder is there.

Required on the host, for the `task` helpers:

- **`CAMERA_HOST`** in `Taskfile.yml` (default `192.168.1.75`), or `task buddy:sync CAMERA_HOST=...`.
  Used by `task buddy:sync`.
- **`REMOTE_HOST`** in `Taskfile.yml` (default `192.168.1.10`), or `task buddy:stage REMOTE_HOST=...`.
  `task buddy:stage` writes it into the staged `rsyslog.conf`.
- **`SSH_PUBKEYS`** in `Taskfile.yml`, or `task buddy:stage SSH_PUBKEYS=...`: the public key files that
  `task buddy:stage` writes into the staged `authorized_keys`. Default: every `~/.ssh/*.pub` of the current user.
  It must cover **every** key that should keep access.

The [microSD fsck](../features/sdcard-fsck.md) and [logrotate](../features/logrotate.md) features need no settings.

## ssh key

Use existing keys or create one. By default `task buddy:stage` takes every `~/.ssh/*.pub`; set `SSH_PUBKEYS` in
`Taskfile.yml` or per call to use only some of them:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/buddy3d          # only if you have no key yet
task buddy:stage                                  # all ~/.ssh/*.pub
task buddy:stage SSH_PUBKEYS="$HOME/.ssh/buddy3d.pub"   # only this key
```

`task buddy:stage` concatenates them into `buddy-addons/build/device-stage/authorized_keys` and fails if a file is
missing, contains a private key or has a line that is not a public key. The staged file goes to the card in
[Installation](3-installation.md#3-copy-to-the-microsd-card), and `task buddy:sync` copies it too.

!!! warning "The staged list replaces the camera's keys"
    The card copy always wins: `start-sshd.sh` installs it on every boot. After `task buddy:sync` and a reboot,
    only the keys in `SSH_PUBKEYS` can log in; any other key on the card is gone. Never list a private key.

## Basic auth users (HTTPS)

From the repo root, `task buddy:htpasswd` asks for the user name and the password (twice) and adds or updates that
user in `buddy-addons/secrets/htpasswd`. Run it again for more users or to change a password.

```sh
task buddy:htpasswd                         # prompts for user and password
task buddy:htpasswd HTPASSWD_USER=camera    # prompts for the password only
```

The script it wraps also has non-interactive modes:

```sh
cd buddy-addons
./gen-htpasswd.sh --random USER    # generate a password and print it once
./gen-htpasswd.sh --delete USER    # remove a user
```

Then copy the file to the card, from the card root:

```sh
cp "$ADDONS/secrets/htpasswd" bin/htpasswd    # ADDONS = the repo's buddy-addons/ directory
```

`secrets/` is gitignored. Keep it out of the repo.

## Syslog server address

Set it when staging, so the `rsyslog.conf` copied to the card already has it:

```sh
task buddy:stage REMOTE_HOST=192.168.1.10
grep 'target=' buddy-addons/build/device-stage/rsyslog.conf
```

Or edit `target="REMOTE_HOST"` in `/mnt/sdcard/bin/rsyslog.conf` by hand.

## Camera address for `task buddy:sync`

Either edit `CAMERA_HOST` in `Taskfile.yml`, or pass it per call:

```sh
task buddy:sync CAMERA_HOST=192.0.2.20 REMOTE_HOST=192.168.1.10
```

`buddy:sync` stages first, so pass `REMOTE_HOST` too, or the staged `rsyslog.conf` gets the default.
