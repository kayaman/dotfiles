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
