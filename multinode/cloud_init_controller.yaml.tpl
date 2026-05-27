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
  - openssh-server

users:
  - name: root
    ssh_authorized_keys:
      - "${trimspace(pub_key)}"

write_files:
  - path: /root/.ssh/id_rsa
    permissions: '0600'
    owner: root:root
    encoding: b64
    content: ${base64encode(priv_key)}
  
  - path: /etc/kolla/config/mariadb/galera.cnf
    permissions: '0644'
    content: |
      [mysqld]
      innodb_use_native_aio = 0
      
  - path: /etc/kolla/globals.yml
    permissions: '0644'
    content: |
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
      docker_use_test_images: "yes"
      cinder_enabled_backends:
        - name: "lvm"
          type: "lvm"
  
  - path: /etc/kolla/config/nova/nova-compute.conf
    permissions: '0644'
    content: |
      [libvirt]
      virt_type = qemu
      cpu_mode = none
  
  - path: /root/multinode
    permissions: '0644'
    content: |
      [control]
      ${cluster_name}-controller
      
      [loadbalancer]
      ${cluster_name}-controller
      
      [network]
      ${cluster_name}-controller
      
      [storage]
      ${cluster_name}-controller
      
      [compute]
      %{ for i in range(compute_count) ~}
      ${cluster_name}-compute-${i + 1}
      %{ endfor ~}
      
      [monitoring]
      ${cluster_name}-controller
      
      [deployment]
      localhost ansible_connection=local
  
  - path: /root/run_deploy.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      source /opt/venv/bin/activate
      export ANSIBLE_HOST_KEY_CHECKING=False
      
      echo "========================================="
      echo "Baixando dependencias do Ansible..."
      kolla-ansible install-deps
      echo "========================================="
      echo "Aguardando os nodes Computes subirem o SSH..."
      sleep 20
      
      echo "Iniciando Instalacao Multinode do OpenStack..."
      kolla-ansible bootstrap-servers -i /root/multinode
      kolla-ansible prechecks -i /root/multinode --use-test-images
      kolla-ansible deploy -i /root/multinode
      kolla-ansible post-deploy -i /root/multinode
      pip install python-openstackclient
      
      echo "====================================================="
      echo " Deploy Finalizado com Sucesso! "
      echo "====================================================="

runcmd:
  - systemctl disable --now ssh.socket || true
  - systemctl enable --now ssh.service || true
  - bash -c 'growpart /dev/sda 2 || true; resize2fs /dev/sda2 || true; exit 0'
  - pvcreate /dev/sdb || true
  - vgcreate cinder-volumes /dev/sdb || true
  - python3 -m venv /opt/venv
  - /opt/venv/bin/pip install -U pip
  - /opt/venv/bin/pip install pkgconfig dbus-python docker
  - /opt/venv/bin/pip install git+https://opendev.org/openstack/kolla-ansible@master
  - mkdir -p /etc/kolla/config/nova
  - cp /opt/venv/share/kolla-ansible/etc_examples/kolla/passwords.yml /etc/kolla/passwords.yml
  - /opt/venv/bin/kolla-genpwd
  - sed -i "s/libvirt_version_new.stdout/libvirt_version_new.get('stdout', '0.0.0')/g" /opt/venv/share/kolla-ansible/ansible/roles/nova-cell/tasks/version-check.yml || true
  - cat /opt/venv/share/kolla-ansible/ansible/inventory/multinode >> /root/multinode
  - chmod 600 /root/.ssh/id_rsa
  - chmod +x /root/run_deploy.sh