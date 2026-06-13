#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or using sudo!"
    exit 13
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
conflicting_packages=(
    docker.io \
    docker-compose \
    docker-compose-v2 \
    docker-doc \
    podman-docker \
    containerd \
    runc
)
installed_conflicts=()
for package_name in "${conflicting_packages[@]}"; do
    if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "install ok installed"; then
        installed_conflicts+=("$package_name")
    fi
done

if [ "${#installed_conflicts[@]}" -gt 0 ]; then
    apt-get remove -y "${installed_conflicts[@]}"
fi

apt-get install -y --no-install-recommends \
    ca-certificates \
    curl

install -m 0755 -d /etc/apt/keyrings

docker_keyring="/etc/apt/keyrings/docker.asc"
tmp_keyring="$(mktemp)"
trap 'rm -f "$tmp_keyring"' EXIT
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$tmp_keyring"
install -m 0644 "$tmp_keyring" "$docker_keyring"

# shellcheck disable=SC1091
. /etc/os-release
docker_suite="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
if [ -z "$docker_suite" ]; then
    echo "Unable to determine the Ubuntu codename for Docker's apt repository." >&2
    exit 1
fi
docker_arch="$(dpkg --print-architecture)"

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${docker_suite}
Components: stable
Architectures: ${docker_arch}
Signed-By: ${docker_keyring}
EOF

apt-get update
apt-get install -y --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

groupadd -f docker

for docker_user in vagrant github-runner; do
    if id -u "$docker_user" >/dev/null 2>&1; then
        usermod -aG docker "$docker_user"
    fi
done

systemctl enable --now containerd.service
systemctl enable --now docker.service

service_units=(/etc/systemd/system/actions.runner.*.service)
if [ "${service_units[0]}" != "/etc/systemd/system/actions.runner.*.service" ]; then
    for service_unit in "${service_units[@]}"; do
        systemctl restart "$(basename "$service_unit")"
    done
fi

docker info >/dev/null
docker version
docker compose version
