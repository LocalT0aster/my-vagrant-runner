#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or using sudo!"
    exit 13
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    tar \
    unzip

if ! id -u github-runner >/dev/null 2>&1; then
    useradd --create-home --home-dir /home/github-runner --shell /bin/bash github-runner
fi

install -d -o github-runner -g github-runner /opt/actions-runner
install -d -o github-runner -g github-runner /opt/actions-runner/_work

runner_version="${GH_RUNNER_VERSION:-}"
if [ -z "$runner_version" ]; then
    runner_version="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name | ltrimstr("v")')"
fi

runner_arch="$(dpkg --print-architecture)"
case "$runner_arch" in
    amd64)
        runner_arch="x64"
        ;;
    arm64)
        runner_arch="arm64"
        ;;
    *)
        echo "Unsupported runner architecture: $runner_arch" >&2
        exit 1
        ;;
esac

install_marker="/opt/actions-runner/.runner-version"
installed_version=""
if [ -f "$install_marker" ]; then
    installed_version="$(cat "$install_marker")"
fi

runner_is_configured="false"
if [ -f /opt/actions-runner/.runner ]; then
    runner_is_configured="true"
fi

if [ "$installed_version" != "$runner_version" ] || [ ! -x /opt/actions-runner/bin/Runner.Listener ]; then
    if [ "$runner_is_configured" = "true" ] && [ -x /opt/actions-runner/bin/Runner.Listener ]; then
        cat <<EOF
Runner already configured with version ${installed_version:-unknown}.
Skipping binary replacement to avoid breaking the existing registration.
If you want to rebuild the runner, remove it from GitHub first and re-run provisioning.
EOF
        exit 0
    fi

    archive_path="/tmp/actions-runner-linux-${runner_arch}-${runner_version}.tar.gz"
    download_url="https://github.com/actions/runner/releases/download/v${runner_version}/actions-runner-linux-${runner_arch}-${runner_version}.tar.gz"

    rm -rf /opt/actions-runner/*
    curl -fsSL "$download_url" -o "$archive_path"
    tar -xzf "$archive_path" -C /opt/actions-runner
    rm -f "$archive_path"

    (
        cd /opt/actions-runner
        ./bin/installdependencies.sh
    )

    echo "$runner_version" > "$install_marker"
    chown -R github-runner:github-runner /opt/actions-runner
fi

if [ ! -f /shared/github-runner.env ]; then
    cat <<'EOF'
GitHub runner base installation complete.
Create /shared/github-runner.env from /shared/github-runner.env.example,
fill in GH_RUNNER_URL and either GH_RUNNER_API_TOKEN (preferred) or GH_RUNNER_TOKEN, then run:
  vagrant provision github-runner --provision-with github-runner-register
EOF
fi
