# GPG keys

## formatting the media

LUKS2 is the standard full-disk encryption on Linux and well-supported on both openSUSE and Ubuntu. Here's the process:

1. Identify the USB device:

```bash
lsblk
# or
dmesg | tail -20
```

2. Wipe and encrypt with LUKS2:

```bash
# replace /dev/sdX with your actual device
# overwrite with random data first
sudo dd if=/dev/urandom of=/dev/sdX bs=4M status=progress

# create LUKS2 container with strong settings
sudo cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 5000 \
    --use-random \
    /dev/sdX
```

3. Mount

```bash
# unlock the LUKS container
sudo cryptsetup open /dev/sdX gpg-backup

# check what's actually inside the opened LUKS container
sudo file -s /dev/mapper/gpg-backup

# mount it
sudo mkdir -p /mnt/gpg-backup
sudo mkfs.ext4 -L "GPG-BACKUP" /dev/mapper/gpg-backup
sudo mount /dev/mapper/gpg-backup /mnt/gpg-backup



# check /mnt/gpg-backup/
ls -la /mnt/gpg-backup/
```

## delete

```bash
# remove the old broken key (use the email or key ID)
gpg2 --delete-secret-and-public-key YOUR_EMAIL

# Also delete the old GPG key from GitHub:
# Settings → SSH and GPG keys → find the old GPG key → Delete
```

## backup / restore to USB

`gpg-usb-sync.sh` is a non-destructive snapshot tool. It never deletes keys from
your local keyring — it just copies the whole `~/.gnupg` to a mounted (ideally
LUKS2-encrypted) USB drive and can put it back on a new machine.

Each `backup` writes a timestamped snapshot dir under `<dest>/gnupg-<ts>/`:

- `gnupg-full.tar.gz.gpg` — full `~/.gnupg`, wrapped with `gpg --symmetric`
  (AES-256). Defense-in-depth on top of LUKS2.
- `public-keys.asc`, `secret-keys.asc`, `secret-subkeys.asc` — armored exports
  for partial imports / inspection.
- `ownertrust.txt`, `revocs/*.rev` — trust DB and revocation certificates.
- `MANIFEST.txt` — SHA-256 of every file plus fingerprints; checked on restore.

A `latest` symlink points at the newest snapshot.

```bash
# Back up to an auto-detected USB drive (default --to usb)
./gpg/gpg-usb-sync.sh backup

# See what's on the USB
./gpg/gpg-usb-sync.sh status

# Restore the latest snapshot (merge into existing ~/.gnupg by default)
./gpg/gpg-usb-sync.sh restore

# Replace ~/.gnupg entirely (existing dir is moved to ~/.gnupg.bak-<ts>)
./gpg/gpg-usb-sync.sh restore --replace

# Pin a specific snapshot
./gpg/gpg-usb-sync.sh restore --snapshot gnupg-20260515-101530

# Use a custom path (e.g. for testing or non-standard mount)
./gpg/gpg-usb-sync.sh backup  --to local --path /tmp/gpg-usb-test
./gpg/gpg-usb-sync.sh restore --from local --path /tmp/gpg-usb-test
```

Safety gates: writes to `/mnt/*`, `/media/*`, `/run/media/*` are refused unless
those paths are on a separate mounted device (catches "forgot to mount the USB"
mistakes). Restore aborts before any import if any file's SHA-256 doesn't match
the manifest.

### relation to the offline-master scripts

| Script | What it does |
|---|---|
| `gpg-usb-sync.sh` | Plain snapshot/restore of the entire keyring. Non-destructive. |
| `gpg-offline-master-key.sh` | **Destructive** migration: backs up, then deletes the master key locally, leaving only subkeys. |
| `gpg-restore-master-key.sh` | Temporarily re-imports the master from a backup for admin work. |

Use `gpg-usb-sync.sh` for everyday backups and machine moves. Use the
offline-master pair only when you specifically want the master-key-offline
posture.
