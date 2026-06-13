#!/usr/bin/env bash
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or using sudo!"
    exit 13
fi
apt-get autoremove -y --allow-change-held-packages
apt-get install -y ansible
