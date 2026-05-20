#cloud-config
package_update: true
packages:
  - cloud-guest-utils
  - python3

users:
  - name: root
    ssh_authorized_keys:
      - "${trimspace(pub_key)}"

runcmd:
  - bash -c 'growpart /dev/sda 2 || true; resize2fs /dev/sda2 || true; exit 0'