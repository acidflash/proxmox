#!/usr/bin/env bash
set -euo pipefail

# -------- CONFIG --------
CI_USER="jonas"
SSHKEYS_PATH="/tmp/authorized_keys"
SNIPPETS_DIR="/var/lib/vz/snippets"

# Sätt din SSH key här
SSH_KEY_LINE="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC31njzrS9qlngUMsWR7HKYnkj7E7mJjIMlOjCIJWAwX9aQ5D6AERBF8g5UgINzjhHFo1Zr+eDbfd4bh/aCHZbiGB1k8TdQFwrmOwKTVPJ/uxSimhFStKHUpw9C7VuD8blmr/a96qlexWzjs+ZF1Pnsp40oFeMMPn3ovNUXCCtrZbvpYpg3onik39h0INTp9obCI+GGPkC6B9Kk5pUsYx9FTLe+0/KVhp/uvM2BT9OcvXgEezmiABGetFXyNeDNJ9bRBKfIUqANzhZ6zRXcCW7/UP7vlzlFtR2uM+4zqNTT5qYXC2teSQfxoNcO1faddlrV/vlHshNtd3nMlrzAfTKT OpenShift-Key"
# ------------------------

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Kör som root."
    exit 1
  fi
}

prompt_password() {
  read -r -s -p "Sätt lösenord för cloud-init user '${CI_USER}': " CLEARTEXT_PASSWORD
  echo
  read -r -s -p "Bekräfta lösenord: " CLEARTEXT_PASSWORD_CONFIRM
  echo

  if [[ -z "${CLEARTEXT_PASSWORD}" ]]; then
    echo "ERROR: Tomt lösenord är inte ok."
    exit 1
  fi
  if [[ "${CLEARTEXT_PASSWORD}" != "${CLEARTEXT_PASSWORD_CONFIRM}" ]]; then
    echo "ERROR: Lösenorden matchar inte."
    exit 1
  fi
}

derive_hostnum_2d() {
  local hn
  hn="$(hostname -s | tr '[:upper:]' '[:lower:]')"
  local num
  num="$(echo "$hn" | sed -n 's/.*\([0-9]\+\)$/\1/p')"
  if [[ -z "${num}" ]]; then
    echo "ERROR: Hostname måste sluta med siffror, ex pve01."
    exit 1
  fi
  local n
  n=$((10#$num))
  if (( n < 1 || n > 99 )); then
    echo "ERROR: Host number out of range (1-99): ${n}"
    exit 1
  fi
  printf "%02d" "$n"
}

choose_version() {
  echo "Välj Ubuntu template:"
  echo "  1) 22.04 (Jammy)"
  echo "  2) 24.04 (Noble)"
  echo
  read -r -p "Val (1-2): " choice

  case "${choice}" in
    1)
      UBUNTU_VERSION="22.04"
      CODENAME="jammy"
      SUFFIX="1"
      URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
      IMG="jammy-server-cloudimg-amd64.img"
      SNIPPET_PATH="${SNIPPETS_DIR}/vendor-22.04.yaml"
      ;;
    2)
      UBUNTU_VERSION="24.04"
      CODENAME="noble"
      SUFFIX="2"
      URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
      IMG="noble-server-cloudimg-amd64.img"
      SNIPPET_PATH="${SNIPPETS_DIR}/vendor-24.04.yaml"
      ;;
    *)
      echo "ERROR: Ogiltigt val."
      exit 1
      ;;
  esac
}

write_sshkeys() {
  echo "${SSH_KEY_LINE}" > "${SSHKEYS_PATH}"
  chmod 600 "${SSHKEYS_PATH}"
}

ensure_snippet_2204() {
  if [[ -f "${SNIPPET_PATH}" ]]; then
    echo "Kept existing ${SNIPPET_PATH}"
    return
  fi

  cat << 'EOF' > "${SNIPPET_PATH}"
#cloud-config
write_files:
  - path: /etc/sysctl.d/10-disable-ipv6.conf
    permissions: 0644
    owner: root
    content: |
      net.ipv6.conf.eth0.disable_ipv6 = 1

runcmd:
  - systemctl restart systemd-sysctl
  - apt-get update
  - apt-get install -y qemu-guest-agent net-tools
  - systemctl enable qemu-guest-agent
  - reboot
EOF

  echo "Created ${SNIPPET_PATH}"
}

ensure_snippet_2404() {
  if [[ -f "${SNIPPET_PATH}" ]]; then
    echo "Kept existing ${SNIPPET_PATH}"
    return
  fi

  cat << 'EOF' > "${SNIPPET_PATH}"
#cloud-config
write_files:
  - path: /etc/sysctl.d/10-disable-ipv6.conf
    permissions: 0644
    owner: root
    content: |
      net.ipv6.conf.eth0.disable_ipv6 = 1

  - path: /etc/fail2ban/jail.local
    owner: root:root
    permissions: '0644'
    content: |
      [sshd]
      enabled = true
      port = ssh
      backend = systemd

runcmd:
  - systemctl restart systemd-sysctl
  - apt-get update
  - apt-get install -y qemu-guest-agent net-tools
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - apt-get install -y fail2ban curl gnupg2 apt-transport-https build-essential libpam-dev
  - sshd -t
  - systemctl restart ssh
  - systemctl enable fail2ban
  - systemctl restart fail2ban
  - fail2ban-client ping
  - reboot
EOF

  echo "Created ${SNIPPET_PATH}"
}

create_template() {
  local hostnum_2d="$1"
  local id="8${hostnum_2d}${SUFFIX}"

  echo "Bygger template: Ubuntu ${UBUNTU_VERSION} (${CODENAME}), VMID=${id}"

  if qm status "${id}" >/dev/null 2>&1; then
    echo "VM ${id} finns redan, förstör..."
    qm destroy "${id}" --purge 1
  fi

  cd /tmp
  rm -f ./*-server-cloudimg-amd64.img* 2>/dev/null || true
  wget -q "${URL}" -O "${IMG}"

  qemu-img resize "${IMG}" 32G

  qm create "${id}" --name "ubuntu-${UBUNTU_VERSION}-cloudinit-template" --ostype l26 \
    --memory 1024 \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 local-lvm:0,pre-enrolled-keys=0 \
    --cpu host --socket 1 --cores 1 \
    --vga serial0 --serial0 socket \
    --net0 virtio,bridge=vmbr0

  qm importdisk "${id}" "${IMG}" local-lvm
  qm set "${id}" --scsihw virtio-scsi-pci --virtio0 "local-lvm:vm-${id}-disk-1,discard=on"
  qm set "${id}" --boot order=virtio0
  qm set "${id}" --ide2 local-lvm:cloudinit
  qm set "${id}" --cicustom "vendor=local:snippets/$(basename "${SNIPPET_PATH}")"
  qm set "${id}" --tags "ubuntu-template,${UBUNTU_VERSION},cloudinit"
  qm set "${id}" --ciuser "${CI_USER}"
  qm set "${id}" --cipassword "$(openssl passwd -6 "${CLEARTEXT_PASSWORD}")"
  qm set "${id}" --sshkeys "${SSHKEYS_PATH}"
  qm set "${id}" --ipconfig0 ip=dhcp
  qm template "${id}"

  echo "Klar: VMID ${id}"
}

main() {
  require_root
  choose_version
  prompt_password

  mkdir -p "${SNIPPETS_DIR}"
  write_sshkeys

  local hostnum_2d
  hostnum_2d="$(derive_hostnum_2d)"

  case "${UBUNTU_VERSION}" in
    "22.04") ensure_snippet_2204 ;;
    "24.04") ensure_snippet_2404 ;;
    *) echo "ERROR: Unsupported version"; exit 1 ;;
  esac

  create_template "${hostnum_2d}"

  unset CLEARTEXT_PASSWORD CLEARTEXT_PASSWORD_CONFIRM
}

main "$@"
