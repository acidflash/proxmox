#!/bin/bash

url=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
img="noble-server-cloudimg-amd64.img"
id="8002"
version="24.04"

cat << EOF | tee /tmp/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC31njzrS9qlngUMsWR7HKYnkj7E7mJjIMlOjCIJWAwX9aQ5D6AERBF8g5UgINzjhHFo1Zr+eDbfd4bh/aCHZbiGB1k8TdQFwrmOwKTVPJ/uxSimhFStKHUpw9C7VuD8blmr/a96qlexWzjs+ZF1Pnsp40oFeMMPn3ovNUXCCtrZbvpYpg3onik39h0INTp9obCI+GGPkC6B9Kk5pUsYx9FTLe+0/KVhp/uvM2BT9OcvXgEezmiABGetFXyNeDNJ9bRBKfIUqANzhZ6zRXcCW7/UP7vlzlFtR2uM+4zqNTT5qYXC2teSQfxoNcO1faddlrV/vlHshNtd3nMlrzAfTKT OpenShift-Key
EOF


#### Only if file is gone ####
cat << EOF | tee /var/lib/vz/snippets/vendor.yaml
#cloud-config
write_files:
  - path: /etc/sysctl.d/10-disable-ipv6.conf
    permissions: 0644
    owner: root
    content: |
      net.ipv6.conf.eth0.disable_ipv6 = 1

  - path: /etc/duo/pam_duo.conf
    content: |
      [duo]
      ikey = DIQRKVUG80SBU7T8Z8N1     # <-- Sätt din Duo Integration Key
      skey = iLimZ7dFSpseTy8K4eRFjQFzJYgf82Ne1BDfBgm1    # <-- Sätt din Duo Secret Key
      host = api-3b18cb17.duosecurity.com  # <-- Sätt din Duo API Hostname
      failmode = secure
      pushinfo = yes

  - path: /etc/fail2ban/jail.local
    owner: root:root
    permissions: '0644'
    content: |
      [sshd]
      enabled = true
      port = ssh
      logpath = %(sshd_log)s
      backend = systemd

runcmd:
  - systemctl restart systemd-sysctl
runcmd:
  - cp /dev/null /etc/fail2ban/jail.local
  - apt update
  - apt install -y qemu-guest-agent net-tools
  - systemctl start qemu-guest-agent
  - apt-get install -y fail2ban curl gnupg2 apt-transport-https build-essential libpam-dev

  # Duo PAM install
  - curl -sSL https://dl.duosecurity.com/duo_unix-latest.tar.gz -o /tmp/duo.tar.gz
  - tar -xzf /tmp/duo.tar.gz -C /tmp/
  - cd /tmp/duo_unix-* && ./configure --with-pam && make && make install

  # Aktivera PAM Duo
  - sed -i '1iauth requisite pam_duo.so' /etc/pam.d/sshd

  # Testa och starta
  - sshd -t
  - fail2ban-client -d
  - systemctl restart ssh
  - systemctl enable fail2ban
  - systemctl restart fail2ban
  - fail2ban-client ping
  - reboot
# Taken from https://forum.proxmox.com/threads/combining-custom-cloud-init-with-auto-generated.59008/page-3#post-428772
EOF
#### END ####

cd /tmp/
rm *-server-cloudimg-amd64.img*
wget -q $url
qemu-img resize $img 32G
qm create $id --name "ubuntu-$version-cloudinit-template" --ostype l26 \
    --memory 1024 \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 vm:0,pre-enrolled-keys=0 \
    --cpu host --socket 1 --cores 1 \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=vmbr0
qm importdisk $id $img vm
qm set $id --scsihw virtio-scsi-pci --virtio0 vm:vm-$id-disk-1,discard=on
qm set $id --boot order=virtio0
qm set $id --ide2 vm:cloudinit
qm set $id --cicustom "vendor=local:snippets/vendor.yaml"
qm set $id --tags ubuntu-template,$version,cloudinit
qm set $id --ciuser jonas
qm set $id --cipassword $(openssl passwd -6 $CLEARTEXT_PASSWORD)
qm set $id --sshkeys /tmp/authorized_keys
qm set $id --ipconfig0 ip=dhcp
qm template $id


