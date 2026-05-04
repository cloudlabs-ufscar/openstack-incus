## Docker

```bash
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && y
sudo systemctl status docker
```

```bash
# start docker
sudo systemctl start docker
```

Save Incus group ID

```bash
INCUS_GID=$(getent group incus-admin | cut -d: -f3)
```

Initialize terraform, downloading the image and mouting the directory into container /workspace folder, mapping the incus socket with the permission group

```bash
sudo docker run --rm -it -v $(pwd):/workspace -w /workspace -v /var/lib/incus/unix.socket:/var/lib/incus/unix.socket --group-add $INCUS_GID hashicorp/terraform init
```

Apply

```bash
sudo docker run --rm -it -v $(pwd):/workspace -w /workspace -v /var/lib/incus/unix.socket:/var/lib/incus/unix.socket --group-add $INCUS_GID hashicorp/terraform apply
```

After some minutes (about 5 minutes), access the VM

```bash
sudo incus shell lab-openstack-b
```

Run the deploy script

```bash
./run_deploy.sh
```

Load credentials

```bash
source /opt/venv/bin/activate
source /etc/kolla/admin-openrc.sh
```

Verify

```bash
openstack compute service list
```

## Destroy instance

```bash
sudo docker run --rm -it -v $(pwd):/workspace -w /workspace -v /var/lib/incus/unix.socket:/var/lib/incus/unix.socket --group-add $INCUS_GID hashicorp/terraform destroy
```