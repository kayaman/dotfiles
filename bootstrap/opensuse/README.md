# notes

## nodejs

```bash
# Download and install nvm:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

# in lieu of restarting the shell
\. "$HOME/.nvm/nvm.sh"

# Download and install Node.js:
nvm install 24

# Verify the Node.js version:
node -v # Should print "v24.14.0".

# Verify npm version:
npm -v # Should print "11.9.0".
```

## go

```bash
sudo zypper install --no-recommends --no-confirm go
```

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

## helm

```bash
git clone https://github.com/helm/helm.git
cd helm
make
```

## mongodb on docker

```bash
# NOTE: Replace <MONGO_INITDB_ROOT_USERNAME> and <MONGO_INITDB_ROOT_PASSWORD>
# with your own secure credentials. These values are intended for local
# development only and MUST NOT be reused in production.
docker run --name mongodb \
  -d \
  -p 27017:27017 \
  -v mongodb-data:/data/db \
  -e MONGO_INITDB_ROOT_USERNAME=<MONGO_INITDB_ROOT_USERNAME> \
  -e MONGO_INITDB_ROOT_PASSWORD=<MONGO_INITDB_ROOT_PASSWORD> \
  mongo
```

```bash
# connection string (match the username/password you configured above)
mongodb://<MONGO_INITDB_ROOT_USERNAME>:<MONGO_INITDB_ROOT_PASSWORD>@localhost:27017

# stop
docker stop mongodb

# start
docker start mongodb

# logs
docker logs -f mongodb
```

## VNC (Wayland)

```bash
echo $XDG_SESSION_TYPE

sudo zypper install gnome-remote-desktop

rm -rf ~/.local/share/gnome-remote-desktop/certificates
mkdir -p ~/.local/share/gnome-remote-desktop/certificates

# Generate a self-signed certificate
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
  -subj "/CN=gnome-remote-desktop" \
  -keyout ~/.local/share/gnome-remote-desktop/certificates/rdp-tls.key \
  -out ~/.local/share/gnome-remote-desktop/certificates/rdp-tls.crt


chmod 600 ~/.local/share/gnome-remote-desktop/certificates/rdp-tls.key
chmod 644 ~/.local/share/gnome-remote-desktop/certificates/rdp-tls.crt

grdctl rdp set-tls-cert ~/.local/share/gnome-remote-desktop/certificates/rdp-tls.crt
grdctl rdp set-tls-key ~/.local/share/gnome-remote-desktop/certificates/rdp-tls.key

systemctl --user restart gnome-remote-desktop
systemctl --user daemon-reload

grdctl rdp enable
grdctl rdp set-credentials YOUR_USERNAME YOUR_PASSWORD

# validating
systemctl --user status gnome-remote-desktop
grdctl status

# firewall
sudo firewall-cmd --add-port=3389/tcp --permanent && sudo firewall-cmd --reload
```

