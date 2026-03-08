#!/usr/bin/env bash

set -Eeuo pipefail

sudo zypper refresh --services
sudo zypper update --no-confirm --recommends
sudo rpm --import https://releases.warp.dev/linux/keys/warp.asc
sudo sh -c 'echo -e "[warpdotdev]\nname=warpdotdev\ntype=rpm-md\nbaseurl=https://releases.warp.dev/linux/rpm/stable\nenabled=1\nautorefresh=1\ngpgcheck=1\ngpgkey=https://releases.warp.dev/linux/keys/warp.asc\nkeeppackages=0" > /etc/zypp/repos.d/warpdotdev.repo'
sudo zypper refresh
sudo zypper install --no-confirm --recommends warp-terminal
