#!/bin/bash

sudo apt-get update
sudo apt install -y nfs-kernel-server
sudo mkdir -p /export/data
sudo chown nobody:nogroup /export/data
sudo chmod 777 /export/data
sudo bash -c  "echo '/export/data    *(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports"
sudo exportfs -a
sudo systemctl restart nfs-kernel-server
