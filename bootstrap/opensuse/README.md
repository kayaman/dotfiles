# just notes

## OpenSSH Server

```bash
# chech SSH service current status
systemctl status sshd

# check OpenSSH server installation
rpm -qa | grep openssh-server

# check firewall status
systemctl status firewalld

# start and enable the SSH daemon
sudo systemctl enable --now sshd

# check the status to confirm SSH is working properly
systemctl is-active sshd && systemctl is-enabled sshd

# check firewall rules
sudo firewall-cmd --list-services

# configure firewall to allow SSH
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload

# check what port SSH will listen on
grep -E "^#?Port" /etc/ssh/sshd_config

# check if sshd_config exists
find /etc -name "*ssh*" -type d 2>/dev/null
ls -la /etc/ssh

# check if there is a default configuration file
rpm -ql openssh-server | grep sshd_config

# add SSH service to firewall (enable)
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload
```

## IP

```bash
# get my current IP address
ip addr show | grep -E "inet.*scope global" | head -1

# get my current IP address
ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1
```

## Remote Desktop (RDP)

```bash
# install xrdp and dependencies
sudo zypper install -y xrdp xorgxrdp

# enable and start the service
sudo systemctl enable --now xrdp

# check firewall status
sudo firewall-cmd --state

# configure the firewall to allow RDP connections
sudo firewall-cmd --add-port=3389/tcp --permanent
sudo firewall-cmd --reload

# verify firewall status
sudo firewall-cmd --list-ports

# check if a desktop environment is installed
echo $XDG_CURRENT_DESKTOP

# verify that xrdp is listening on the default port
sudo ss -tlnp | grep :3389
```

## Docker

```bash
sudo zypper refresh
sudo zypper update
sudo zypper install --no-recommends --no-confirm docker docker-compose

sudo systemctl enable docker --now

sudo usermod -aG docker $USER
newgrp docker
```


