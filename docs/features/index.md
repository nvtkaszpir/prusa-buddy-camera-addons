# Features

Currently implemented:

- [SSH](ssh.md): instead of telnet there is an access via ssh with authorized keys
- [rsync](rsync.md): rsync to allow easier file fetching
- [HTTPS](https.md): http server (lightttpd) over TLS access with basic auth, so you can use wget/curl
  instead of rsync

- [Remote rsyslog](rsyslog.md): write to remote rsyslog server
- [microSD fsck](sdcard-fsck.md): run fsck sdcard on system start and remount it as read/write, improve the
  system settings to minimize sdcard corruptions in the future
- [logrotate](logrotate.md): logrotate - rotate logs every day, keep last 7
