#cloud-config
package_update: true
users:
  - name: root
    ssh_authorized_keys:
      - "${pub_key}"

packages:
  - cloud-guest-utils
  - python3

runcmd:
  - bash -c 'growpart /dev/sda 2; resize2fs /dev/sda2; exit 0'