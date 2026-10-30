# remarkable2-backup

Automatic, zero-install backups of a **reMarkable 2** tablet to any Docker host: a NAS, a Raspberry Pi, a Linux server or a Mac.

- **Nothing to install on the tablet.** It uses the tablet's built-in SSH server.
- **Set and forget.** The container waits quietly for the tablet to wake up, then takes a backup. No cron jobs, no remembering.
- **Safe archives.** Each backup is checked before it's kept, and the last _N_ are retained.
- **Survives firmware updates.** reMarkable updates change the tablet's SSH host key; the container detects this and carries on.
- **Quiet logs.** One line when a backup starts, one when it finishes. Nothing while the tablet sleeps.

It backs up the tablet's complete document store (`~/.local/share/remarkable/xochitl`): every notebook, PDF, ebook and annotation, in the tablet's own format. That's the format you need to **restore** to the tablet. It is not a folder of PDFs.

> Tested on a reMarkable 2 running firmware 3.28. The original reMarkable will probably work the same way. The Paper Pro requires developer mode for SSH and is untested.

## How it works

Every minute (while a backup is due), the container pings the tablet. The tablet turns its Wi-Fi off when it sleeps, so a reply means it's awake. It then streams a `tar` of the document store over SSH into a dated archive such as `remarkable-2026-10-30_1043.tar`, checks the archive is readable, and deletes the oldest archives beyond `KEEP`. After a successful backup it does nothing until the next one is due (`INTERVAL_HOURS`).

A full backup of about 1 GB takes around 3 minutes over Wi-Fi. Keep the tablet awake for that long. A backup interrupted by the tablet sleeping is discarded and retried later.

## Setup

### 1. Give the tablet a fixed IP address

Reserve an IP address for the tablet in your router (DHCP reservation / fixed IP), so the container can always find it.

### 2. Turn on SSH over Wi-Fi

On firmware 3.x, SSH over Wi-Fi is off by default and can only be enabled from a USB connection.

1. On the tablet, go to **Settings → General → About → Copyrights and licenses** and note the **root password**.
2. Connect the tablet to your computer with its USB-C cable and unlock it. It appears as a network adapter, and the tablet answers at `10.11.99.1`.
3. From a terminal: `ssh root@10.11.99.1`, enter the root password, then run:
   ```
   rm-ssh-over-wlan on
   ```
4. `exit`, unplug, and check it works over Wi-Fi: `ssh root@<tablet-ip>`.

> If your computer warns that the host identification has changed, run `ssh-keygen -R 10.11.99.1` (or the Wi-Fi IP) and try again. reMarkable firmware updates generate a new host key.

### 3. Start the container

Use the [`docker-compose.yml`](docker-compose.yml) from this repo: set `RM_HOST` to your tablet's IP and `TZ` to your time zone, then start it with `docker compose up -d` or paste it into your Docker UI as a new stack (Portainer, Dockge, Dockhand, Synology/UGREEN/QNAP Container Manager, etc.).

```yaml
services:
  remarkable2-backup:
    image: ghcr.io/ianwestergithub/remarkable2-backup:latest
    container_name: remarkable2-backup
    restart: unless-stopped
    environment:
      - RM_HOST=192.168.1.50
      - KEEP=8
      - INTERVAL_HOURS=24
      - TZ=Europe/London
      - TEST_RUN=0
    volumes:
      - ./ssh:/ssh
      - ./archives:/archives
```

On a NAS, use full paths for the volumes, e.g. `/volume1/docker/remarkable2-backup/ssh:/ssh`. **Make sure the folders exist and the paths are right.** If Docker can't find a path it silently creates a different one, and you'll get a new SSH key every time the container is redeployed.

### 4. Add the container's key to the tablet

On first start, the container creates its own SSH key and prints the public half in its logs:

```
=== Public key to add to the tablet's ~/.ssh/authorized_keys ===
ssh-ed25519 AAAAC3Nza...  remarkable2-backup
================================================================
```

Copy that whole `ssh-ed25519 ... remarkable2-backup` line, then on the tablet (`ssh root@<tablet-ip>`):

```
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAAC3Nza... remarkable2-backup' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Restart the container, wake the tablet, and watch the logs:

```
2026-10-30 10:43:00 Tablet online - backup starting...
2026-10-30 10:46:01 Backup OK: remarkable-2026-10-30_1043.tar (923.9M)
```

Redeploy the container and the logs should say **"Existing SSH key found - reusing it"**. If they say a new key was generated, your `/ssh` volume isn't persisting (see step 3).

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `RM_HOST` | _(required)_ | The tablet's IP address |
| `KEEP` | `8` | Number of archives to keep |
| `INTERVAL_HOURS` | `24` | Minimum time between backups |
| `TZ` | UTC | Time zone for logs and archive names |
| `RM_USER` | `root` | SSH user on the tablet |
| `SSH_PORT` | `22` | SSH port on the tablet |
| `TEST_RUN` | `0` | Set to `1` to simulate a firmware update (see below) |

## Testing the firmware-update recovery

Set `TEST_RUN=1` and redeploy with the tablet awake. The container plants a fake host key and forces a backup. You should see:

```
TEST_RUN: planting a fake tablet host key and forcing a backup
Tablet online - backup starting...
Tablet SSH host key changed (normal after a firmware update) - accepted new key, retrying
Tablet online - backup starting...
Backup OK: ...
```

Then set `TEST_RUN=0` and redeploy.

## Restoring

The archives contain the tablet's raw `xochitl` folder: files named by UUID (`.metadata`, `.content`, page folders of `.rm` files, etc.). Each document's name is in its `.metadata` file.

**To restore a single notebook:**

1. Extract an archive that contains it on your computer (`tar xf remarkable-....tar`, or double-click it on a Mac).
2. Find its UUID:
   ```
   grep -l '"visibleName": "My Notebook"' xochitl/*.metadata
   ```
3. Copy all of that UUID's files and folders back, then restart the tablet's interface:
   ```
   scp -r xochitl/<UUID>* root@<tablet-ip>:/home/root/.local/share/remarkable/xochitl/
   ssh root@<tablet-ip> systemctl restart xochitl
   ```

This was tested on firmware 3.28 by permanently deleting a notebook, restoring it this way, and confirming it reappeared intact and survived a cloud sync.

**To restore everything** (e.g. after a factory reset), copy the whole folder back the same way:

```
scp -r xochitl/* root@<tablet-ip>:/home/root/.local/share/remarkable/xochitl/
ssh root@<tablet-ip> systemctl restart xochitl
```

## Troubleshooting

| Log message | Likely cause |
|---|---|
| `Permission denied (publickey,password)` | The key in the logs isn't in the tablet's `authorized_keys`, or the container generated a new key because `/ssh` isn't persisting |
| `Connection refused` | SSH over Wi-Fi is off. Firmware updates can turn it off; repeat step 2 |
| Nothing after "Watching for tablet" | Normal. A backup isn't due yet, or the tablet hasn't been awake |
| A Docker host that blocks ping | The container needs to ping the tablet; make sure ICMP isn't blocked between them |

On a Mac, Docker Desktop must be running and the Mac awake for backups to happen. An always-on machine is a better home for it.

## What this doesn't do

It doesn't sync anything to reMarkable's apps, and it doesn't convert notebooks to PDF. Without a Connect subscription, files you haven't used for 50 days drop out of reMarkable's cloud; this keeps a complete, independent copy of everything on the tablet regardless.

## License

MIT
