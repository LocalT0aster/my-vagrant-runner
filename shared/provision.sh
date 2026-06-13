#!/usr/bin/env bash
if [ $(id -u) -ne 0 ]; then
    echo "Please run this script as root or using sudo!"
    exit 13
fi
rm /etc/apt/sources.list.d/cappelikan.sources /etc/apt/sources.list.d/home-alvistack.sources
apt-get update
apt-get purge -y --allow-change-held-packages ansible mainline sosreport
# upgrade kernel
apt-get autoremove -y --allow-change-held-packages
apt full-upgrade -y
