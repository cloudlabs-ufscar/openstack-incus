#cloud-config
package_update: true
users:
  - name: root
    ssh_authorized_keys:
      - "${pub_key}"

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
  # Expansão e LVM
  - bash -c 'growpart /dev/sda 2; resize2fs /dev/sda2; pvcreate /dev/sdb; vgcreate cinder-volumes /dev/sdb; exit 0'

  # Injeção da Chave Privada do Terraform para acesso aos Computes
  - |
    cat <<'EOF_KEY' > /root/.ssh/id_rsa
    ${priv_key}
    EOF_KEY
  - chmod 600 /root/.ssh/id_rsa

  # Setup do Kolla
  - python3 -m venv /opt/venv
  - /opt/venv/bin/pip install -U pip
  - /opt/venv/bin/pip install pkgconfig dbus-python docker
  - /opt/venv/bin/pip install git+https://opendev.org/openstack/kolla-ansible@master
  - mkdir -p /etc/kolla/config/nova
  - cp -r /opt/venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
  - /opt/venv/bin/kolla-genpwd

  # PATCH: Resolve o bug do Libvirt
  - sed -i "s/libvirt_version_new.stdout/libvirt_version_new.get('stdout', '0.0.0')/g" /opt/venv/share/kolla-ansible/ansible/roles/nova-cell/tasks/version-check.yml || true

  # Inventário Multinode Dinâmico gerado pelo Terraform
  - |
    cat <<EOF > /root/multinode
    [control]
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
    EOF

  # Globals e Nova config
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
    cat <<EOF > /etc/kolla/config/nova/nova-compute.conf
    [libvirt]
    virt_type = qemu
    cpu_mode = none
    EOF

  # Script final (Note o uso do arquivo -i /root/multinode em vez de all-in-one)
  - |
    cat <<'EOF' > /root/run_deploy.sh
    #!/bin/bash
    set -e
    source /opt/venv/bin/activate
    export ANSIBLE_HOST_KEY_CHECKING=False
    echo "========================================="
    echo "Baixando dependencias..."
    kolla-ansible install-deps
    echo "========================================="
    echo "Aguardando os nós compute iniciarem o SSH..."
    sleep 30
    echo "Iniciando a instalacao Multinode do OpenStack..."
    echo "========================================="
    kolla-ansible bootstrap-servers -i /root/multinode
    kolla-ansible prechecks -i /root/multinode
    kolla-ansible deploy -i /root/multinode
    kolla-ansible post-deploy -i /root/multinode
    pip install python-openstackclient
    echo "====================================================="
    echo " Deploy Finalizado! Acesse com: "
    echo " source /etc/kolla/admin-openrc.sh"
    echo "====================================================="
    EOF
  - chmod +x /root/run_deploy.sh