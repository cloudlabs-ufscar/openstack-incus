# Deploying Openstack

## Current VM: Inc5-stratus

### Initial state

```bash
> ubuntu@inc5-stratus:~$ cat /sys/module/kvm_intel/parameters/nested

Y
```

```bash
> ubuntu@inc5-stratus:~$ sudo cat /etc/netplan/50-cloud-init.yaml

network:
  version: 2
  ethernets:
    eno1:
      match:
        macaddress: 78:2b:cb:02:4f:c6
      addresses:
      - 192.168.69.36/24
      nameservers:
        addresses:
        - 192.168.69.1
        search:
        - maas
        - cloudlabs
      gateway4: 192.168.69.1
      set-name: eno1
      mtu: 1500
    eno2:
      match:
        macaddress: 78:2b:cb:02:4f:c8
      set-name: eno2
      mtu: 1500
      dhcp4: false
      dhcp6: false
      optional: true
    eno3:
      match:
        macaddress: 78:2b:cb:02:4f:ca
      addresses:
      - 192.168.200.83/24
      nameservers:
        addresses:
        - 192.168.200.1
        - 192.168.100.1
        search:
        - maas
        - cloudlabs
      set-name: eno3
      mtu: 1500
      routes:
      - table: 1
        to: 0.0.0.0/0
        via: 192.168.200.1
      routing-policy:
      - table: 1
        priority: 1000
        from: 192.168.200.0/24
      - table: 254
        from: 192.168.200.0/24
        to: 192.168.200.0/24
    eno4:
      match:
        macaddress: 78:2b:cb:02:4f:cc
      set-name: eno4
      mtu: 1500
```

```bash
> ubuntu@inc5-stratus:~$ sudo incus network list

+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
|      NAME      |   TYPE   | MANAGED |      IPV4       |           IPV6            |            DESCRIPTION             | USED BY |  STATE  |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| LOCAL          | physical | YES     |                 |                           | Directly attach to host networking | 0       | CREATED |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| UPLINK         | physical | YES     |                 |                           | Physical network for OVN routers   | 1       | CREATED |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| br-int         | bridge   | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| default        | ovn      | YES     | 10.246.225.1/24 | fd42:192c:d679:f4d5::1/64 | Initial OVN network                | 1       | CREATED |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| eno1           | physical | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| eno2           | physical | NO      |                 |                           |                                    | 1       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| eno3           | physical | NO      |                 |                           |                                    | 1       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| eno4           | physical | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| enp67s0f0      | physical | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| enp67s0f1      | physical | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| ens5f0         | physical | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| ens5f1         | physical | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| genev_sys_6081 | unknown  | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| incusovn2      | bridge   | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| lo             | loopback | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
| ovs-system     | unknown  | NO      |                 |                           |                                    | 0       |         |
+----------------+----------+---------+-----------------+---------------------------+------------------------------------+---------+---------+
```

### Network

OpenStack requires two networks (one for management/APIs and another for floating/external IPs)

eth0 is the default managed by OVN in band `10.246.225.1/24`

Creation of an external network managed by Incus (without altering the netplan) - this will act as the external network, where the OpenStack floating IPs are located

```bash
> ubuntu@inc4-stratus:~$ sudo incus network create br-ex --target inc4-stratus
Network br-ex pending on member inc4-stratus

> ubuntu@inc5-stratus:~$ sudo incus network create br-ex --target inc5-stratus
Network br-ex pending on member inc4-stratus

> ubuntu@inc6-stratus:~$ sudo incus network create br-ex --target inc6-stratus
Network br-ex pending on member inc6-stratus
```

```bash
> ubuntu@inc5-stratus:~$ sudo incus network create br-ex --type=bridge ipv4.address=10.10.10.1/24 ipv4.nat=true ipv6.address=none

Network br-ex created
```

- If there are any errors on the network that already exist, or if you try to use any creation in the wrong order, just delete it using `sudo incus network delete br-ex`

### Create VM profile

```bash
> ubuntu@inc5-stratus:~$ sudo incus profile create openstack-aio

Profile openstack-aio created
```

```bash
# Habilita a virtualização aninhada
> ubuntu@inc5-stratus:~$ sudo incus profile set openstack-aio security.nesting=true
```

```bash
# Adiciona a segunda placa de rede (eth1)
> ubuntu@inc5-stratus:~$ sudo incus profile device add openstack-aio eth1 nic nictype=bridged parent=br-ex name=eth1

Device eth1 added to openstack-aio
```

### Start VM and disc

Instantiate the VM using the `default` (which will connect to `eth0` on the OVN network `10.246.225.x` and the `openstack-aio` - which connects to `eth1` and allows nesting

```bash
> ubuntu@inc5-stratus:~$ sudo incus launch images:ubuntu/24.04 lab-openstack --vm -p default -p openstack-aio -c limits.cpu=8 -c limits.memory=16GiB --target inc5-stratus

Launching lab-openstack
```

OpenStack requires a raw block partition for CEPH/Cinder. Check the available storage options and create one on the same physical server where the VM is created, in this case inc5-stratus.

```bash
> ubuntu@inc5-stratus:~$ sudo incus storage list

+--------+--------+-----------------------------------------+---------+---------+
|  NAME  | DRIVER |               DESCRIPTION               | USED BY |  STATE  |
+--------+--------+-----------------------------------------+---------+---------+
| local  | btrfs  | Local storage pool                      | 0       | CREATED |
+--------+--------+-----------------------------------------+---------+---------+
| remote | ceph   | Distributed storage pool (cluster-wide) | 3       | CREATED |
+--------+--------+-----------------------------------------+---------+---------+
```

```bash
> ubuntu@inc5-stratus:~$ sudo incus storage volume create local disco-ceph size=100GiB --type=block

Storage volume disco-ceph created
```

```bash
> ubuntu@inc5-stratus:~$ sudo incus storage volume attach local disco-ceph lab-openstack sdb
```

### Access VM and install Kolla-Ansible ([https://docs.openstack.org/kolla-ansible/latest/user/quickstart.html](https://docs.openstack.org/kolla-ansible/latest/user/quickstart.html))

```bash
> ubuntu@inc5-stratus:~$ sudo incus shell lab-openstack
root@lab-openstack:~#
```

Installing dependencies

```bash
> root@lab-openstack:~ sudo apt update && sudo apt install -y git python3-dev libffi-dev gcc libssl-dev python3-venv lvm2 pkg-config libdbus-1-dev libdbus-glib-1-dev 
```

Prepare the disc for Cinder.

```bash
> (venv) root@lab-openstack:~ sudo pvcreate /dev/sdb
Physical volume "/dev/sdb" successfully created.
> (venv) root@lab-openstack:~ sudo vgcreate cinder-volumes /dev/sdb
Volume group "cinder-volumes" successfully created
```

Creating the Python virtual environment and installing Kolla-Ansible.

```bash
> root@lab-openstack:~ python3 -m venv /opt/venv
> root@lab-openstack:~ source /opt/venv/bin/activate
(venv) root@lab-openstack:~#

> (venv) root@lab-openstack:~ pip install -U pip
Successfully installed pip-26.1

> (venv) root@lab-openstack:~ pip install docker pkgconfig dbus-python
```

```bash
> (venv) root@lab-openstack:~ pip install git+https://opendev.org/openstack/kolla-ansible@master
Successfully installed...
```

Copy default settings to the correct directory.

```bash
> (venv) root@lab-openstack:~ sudo mkdir -p /etc/kolla
> (venv) root@lab-openstack:~ sudo chown $USER:$USER /etc/kolla
> (venv) root@lab-openstack:~ cp -r /opt/venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
> (venv) root@lab-openstack:~ cp /opt/venv/share/kolla-ansible/ansible/inventory/all-in-one .
```

### Deploy configuration (`globals.yml`)

```bash
> (venv) root@lab-openstack:~ ip a

1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: enp5s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1442 qdisc mq state UP group default qlen 1000
    link/ether 10:66:6a:78:08:4d brd ff:ff:ff:ff:ff:ff
    inet 10.246.225.2/24 metric 100 brd 10.246.225.255 scope global dynamic enp5s0
       valid_lft 2826sec preferred_lft 2826sec
    inet6 fd42:192c:d679:f4d5:1266:6aff:fe78:84d/64 scope global mngtmpaddr noprefixroute
       valid_lft forever preferred_lft forever
    inet6 fe80::1266:6aff:fe78:84d/64 scope link
       valid_lft forever preferred_lft forever
3: enp6s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 10:66:6a:82:ea:44 brd ff:ff:ff:ff:ff:ff
```

Use a free IP address in the `10.246.225.x` range, in this case

```bash
> (venv) root@lab-openstack:~ sudo apt update && sudo apt install nano
> (venv) root@lab-openstack:~ nano /etc/kolla/globals.yml
```

Within the file, the lines should be uncommented and their values ​​changed.

- `kolla_base_distro: "ubuntu"`
- `network_interface: "enp5s0"`
- `neutron_external_interface: "enp6s0"`
- `kolla_internal_vip_address: "10.246.225.200"`
- `enable_cinder: true`
- `enable_cinder_backend_lvm: true`
- `cinder_volume_group: "cinder-volumes"`
- `nova_compute_virt_type: "qemu”`
- `libvirt_enable_sasl: false`

### Deploy

Inside the venv (`source /opt/venv/bin/activate`)

```bash
# Generates OpenStack passwords
> (venv) root@lab-openstack:~ kolla-genpwd
WARNING: Passwords file "/etc/kolla/passwords.yml" is world-readable. The permissions will be changed.
```

```bash
> (venv) root@lab-openstack:~ kolla-ansible install-deps
```

```bash
# Prepare the server
> (venv) root@lab-openstack:~ kolla-ansible bootstrap-servers -i ./all-in-one
```

```bash
# Check if everything is correct with the configuration
> kolla-ansible prechecks -i ./all-in-one
PLAY RECAP *******************************************************************************************************************************
localhost                  : ok=116  changed=0    unreachable=0    failed=0    skipped=156  rescued=0    ignored=0
```

```bash
# Starts deploying OpenStack containers
> (venv) root@lab-openstack:~ kolla-ansible deploy -i ./all-in-one --tags nova
```

### Post Deploy

```bash
> (venv) root@lab-openstack:~ pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/master
```

```bash
# Generate credentials
> (venv) root@lab-openstack:~ kolla-ansible post-deploy -i ./all-in-one
```

```bash
# Load the credentials
> (venv) root@lab-openstack:~ source /etc/kolla/admin-openrc.sh
```

```bash
> (venv) root@lab-openstack:~ openstack compute service list

+-----------------+----------------+---------------+----------+---------+-------+-----------------+
| ID              | Binary         | Host          | Zone     | Status  | State | Updated At      |
+-----------------+----------------+---------------+----------+---------+-------+-----------------+
| 28cf6b46-846b-  | nova-scheduler | lab-openstack | internal | enabled | up    | 2026-05-        |
| 4da9-943c-      |                |               |          |         |       | 04T02:35:45.000 |
| 140180cd76bd    |                |               |          |         |       | 000             |
| d81522b2-e368-  | nova-conductor | lab-openstack | internal | enabled | up    | 2026-05-        |
| 4b82-bc8a-      |                |               |          |         |       | 04T02:35:43.000 |
| fc115069ed6c    |                |               |          |         |       | 000             |
| 43461f3e-478f-  | nova-compute   | lab-openstack | nova     | enabled | up    | 2026-05-        |
| 4155-8cc8-      |                |               |          |         |       | 04T02:35:44.000 |
| a87b10ef55cc    |                |               |          |         |       | 000             |
+-----------------+----------------+---------------+----------+---------+-------+-----------------+
```

# Done!

## Delete VM
```
sudo incus delete lab-openstack --force
```
(change `local` and `disco-ceph`)
```
sudo incus storage volume delete local disco-ceph
```
---
## Errors

- Libvirt

```bash
 TASK [nova-cell : Cache new Libvirt version] *********************************************************************************************

[ERROR]: Task failed: Finalization of task args for 'ansible.builtin.set_fact' failed: Error while resolving value for 'libvirt_new_version': object of type 'dict' has no attribute 'stdout'

Task failed.

Origin: /opt/venv/share/kolla-ansible/ansible/roles/nova-cell/tasks/version-check.yml:29:7

27       delegate_to: "{{ groups[service.group] | first }}"

28

29     - name: Cache new Libvirt version

         ^ column 7

<<< caused by >>>

Finalization of task args for 'ansible.builtin.set_fact' failed.

Origin: /opt/venv/share/kolla-ansible/ansible/roles/nova-cell/tasks/version-check.yml:30:7

28

29     - name: Cache new Libvirt version

30       ansible.builtin.set_fact:

         ^ column 7

<<< caused by >>>

Error while resolving value for 'libvirt_new_version': object of type 'dict' has no attribute 'stdout'

Origin: /opt/venv/share/kolla-ansible/ansible/roles/nova-cell/tasks/version-check.yml:31:30

29     - name: Cache new Libvirt version

30       ansible.builtin.set_fact:

31         libvirt_new_version: "{{ libvirt_version_new.stdout | regex_search('[0-9]+\\.[0-9]+\\.[0-9]+') }}"

                                ^ column 30

fatal: [localhost]: FAILED! => {"changed": false, "msg": "Task failed: Finalization of task args for 'ansible.builtin.set_fact' failed: Error while resolving value for 'libvirt_new_version': object of type 'dict' has no attribute 'stdout'"} 
```

Fix

```bash
sudo systemctl stop libvirtd 2>/dev/null
sudo systemctl disable libvirtd 2>/dev/null
sudo rm -f /var/run/libvirt/libvirt-sock*
docker rm -f nova_libvirt
```

```bash
(venv) root@lab-openstack:~ cat /opt/venv/share/kolla-ansible/ansible/roles/nova-cell/tasks/version-check.yml
---
- name: Check Libvirt version compatibility
  when: enable_nova_libvirt_container | bool and (groups[service.group] | length) > 0
  vars:
    service_name: "nova-libvirt"
    service: "{{ nova_cell_services[service_name] }}"
  tags: nova-libvirt-version-check
  block:
    - name: Get new Libvirt version
      become: true
      kolla_container:
        action: "start_container"
        command: "libvirtd --version"
        common_options: "{{ docker_common_options }}"
        container_engine: "{{ kolla_container_engine }}"
        detach: false
        environment:
          KOLLA_CONFIG_STRATEGY: "{{ config_strategy }}"
        image: "{{ service.image }}"
        name: "libvirt_version_check"
        restart_policy: oneshot
        remove_on_exit: true
      register: libvirt_version_new
      failed_when: false
      check_mode: false
      run_once: true
      delegate_to: "{{ groups[service.group] | first }}"

    - name: Cache new Libvirt version
      ansible.builtin.set_fact:
        libvirt_new_version: "{{ libvirt_version_new.stdout | regex_search('[0-9]+\\.[0-9]+\\.[0-9]+') }}"
      run_once: true
      delegate_facts: true
      delegate_to: "{{ groups[service.group] | first }}"

    - name: Get nova_libvirt image info
      ansible.builtin.include_role:
        name: service-image-info
      run_once: true

    - name: Get container facts
      become: true
      kolla_container_facts:
        action: get_containers
        container_engine: "{{ kolla_container_engine }}"
        name:
          - "{{ service.container_name }}"
      register: container_facts_per_host
      when: inventory_hostname in groups[service.group]

    - name: Get current Libvirt version
      any_errors_fatal: true
      become: true
      ansible.builtin.command: "{{ kolla_container_engine }} exec {{ service.container_name }} libvirtd --version"
      register: libvirt_version_current_results
      changed_when: false
      when:
        - container_facts_per_host is not skipped
        - container_facts_per_host.containers[service.container_name] is defined
        - (hostvars[groups[service.group] | first].service_image_info.images | default([]) | length) > 0
        - container_facts_per_host.containers[service.container_name].Image
          != hostvars[groups[service.group] | first].service_image_info.images[0].Id

    - name: Check that the new Libvirt version is >= current
      any_errors_fatal: true
      vars:
        current_version: "{{ libvirt_version_current_results.stdout | regex_search('[0-9]+\\.[0-9]+\\.[0-9]+') }}"
        new_version: "{{ hostvars[groups[service.group] | first].libvirt_new_version }}"
      ansible.builtin.assert:
        that: "{{ new_version is version(current_version, '>=', strict=true) }}"
        fail_msg: >
          It looks like you're about to downgrade Libvirt in the nova_libvirt container from
          version {{ current_version }} to version {{ new_version }}. If you're absolutely certain
          that you want to do this, please skip the tag `nova-libvirt-version-check`.
        success_msg: >
          Libvirt version check successful: target {{ new_version }} >= current {{ current_version }}.
      when: libvirt_version_current_results is not skipped
```

---
- Storage
```
 TASK [service-image-info : Get Docker image info] ****************************************************************************************

[ERROR]: Task failed: mkdir: cannot create directory ‘/root/.ansible/tmp/ansible-tmp-1777850912.7249718-398683-113739928775689’: No space left on device

Origin: /opt/venv/share/kolla-ansible/ansible/roles/service-image-info/tasks/main.yml:7:7


5   when: kolla_container_engine == 'docker'

6   block:

7     - name: Get Docker image info

        ^ column 7


fatal: [localhost]: UNREACHABLE! => {"changed": false, "msg": "Task failed: mkdir: cannot create directory ‘/root/.ansible/tmp/ansible-tmp-1777850912.7249718-398683-113739928775689’: No space left on device", "unreachable": true} 
```
Fix
Outside the VM, execute
```
> sudo incus config device override lab-openstack root size=100GiB
```
```
> sudo incus restart lab-openstack
> sudo incus shell lab-openstack
> growpart /dev/sda 2
> resize2fs /dev/sda2
```
Verify
```
> df -h
```
