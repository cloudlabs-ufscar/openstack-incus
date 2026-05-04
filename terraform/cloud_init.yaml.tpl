#cloud-config
package_update: true
packages:
  - git
  - python3-dev
  - libffi-dev
  - gcc
  - libssl-dev
  - python3-venv
  - lvm2
  - pkg-config
  - libdbus-1-dev
  - libdbus-glib-1-dev
  - cloud-guest-utils

runcmd:
  - [ sh, -c, "growpart /dev/sda 2 || true" ]
  - [ sh, -c, "resize2fs /dev/sda2 || true" ]

  - pvcreate /dev/sdb
  - vgcreate cinder-volumes /dev/sdb

  - python3 -m venv /opt/venv
  - /opt/venv/bin/pip install -U pip
  - /opt/venv/bin/pip install pkgconfig dbus-python docker
  - /opt/venv/bin/pip install git+https://opendev.org/openstack/kolla-ansible@master

  - mkdir -p /etc/kolla/config/nova
  - cp -r /opt/venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
  - cp /opt/venv/share/kolla-ansible/ansible/inventory/all-in-one /root/all-in-one
  - /opt/venv/bin/kolla-genpwd

  - sed -i "s/libvirt_version_new.stdout/libvirt_version_new.get('stdout', '0.0.0')/g" /opt/venv/share/kolla-ansible/ansible/roles/nova-cell/tasks/version-check.yml

  - |
    cat <<EOF > /etc/kolla/globals.yml
    kolla_base_distro: "ubuntu"
    network_interface: "enp5s0"
    neutron_external_interface: "enp6s0"
    kolla_internal_vip_address: "${vip_address}"
    keepalived_virtual_router_id: ${router_id}
    enable_cinder: true
    enable_cinder_backend_lvm: true
    cinder_volume_group: "cinder-volumes"
    nova_compute_virt_type: "qemu"
    libvirt_enable_sasl: false
    EOF

  - |
    cat <<EOF > /etc/kolla/config/nova/nova.conf
    [libvirt]
    virt_type = qemu
    cpu_mode = none
    EOF

  - |
    cat <<'EOF' > /root/run_deploy.sh
    #!/bin/bash
    set -e
    source /opt/venv/bin/activate
    kolla-ansible install-deps
    kolla-ansible bootstrap-servers -i /root/all-in-one
    kolla-ansible prechecks -i /root/all-in-one
    kolla-ansible deploy -i /root/all-in-one
    kolla-ansible post-deploy -i /root/all-in-one
    pip install python-openstackclient
    echo "====================================================="
    echo " Deploy Finalizado! Acesse com: "
    echo " source /etc/kolla/admin-openrc.sh"
    echo "====================================================="
    EOF
  - chmod +x /root/run_deploy.sh