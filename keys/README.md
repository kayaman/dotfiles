# keys

## format

LUKS2 is the way to go — it's the standard full-disk encryption on Linux and well-supported on both openSUSE and Ubuntu. Here's the process:

1. Identify the USB device (be very careful here — wrong device = data loss):

```bash
lsblk

# or
dmesg | tail -20
```

2. Wipe and encrypt with LUKS2:

```bash
# Replace /dev/sdX with your actual device — triple-check this
# This destroys ALL data on the drive

# Optional: overwrite with random data first (slow but more secure)
sudo dd if=/dev/urandom of=/dev/sdX bs=4M status=progress

# Create LUKS2 container with strong settings
sudo cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 5000 \
    --use-random \
    /dev/sdX
```
