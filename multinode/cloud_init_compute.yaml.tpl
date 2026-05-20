#cloud-config
package_update: true
packages:
  - cloud-guest-utils
  - python3
  - openssh-server

users:
  - name: root
    ssh_authorized_keys:
      - "${trimspace(pub_key)}"

runcmd:
  - systemctl disable --now ssh.socket || true
  - systemctl enable --now ssh.service || true
  - bash -c 'growpart /dev/sda 2 || true; resize2fs /dev/sda2 || true; exit 0'