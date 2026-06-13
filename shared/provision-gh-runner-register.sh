#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or using sudo!"
    exit 13
fi

if [ -f /shared/github-runner.env ]; then
    set -a
    # shellcheck disable=SC1091
    . /shared/github-runner.env
    set +a
fi

if [ ! -f /shared/github-runner.env ] && [ -z "${GH_RUNNER_URL:-}" ] && [ -z "${GH_RUNNER_TOKEN:-}" ] && [ -z "${GH_RUNNER_API_TOKEN:-}" ]; then
    cat <<'EOF' >&2
Runner configuration is missing inside the guest.
If you created vagrant/shared/github-runner.env on the host after the VM was already running,
sync it first with:
  vagrant rsync github-runner
Or bypass the shared file and pass GH_RUNNER_URL plus GH_RUNNER_API_TOKEN or GH_RUNNER_TOKEN in the host environment.
EOF
fi

: "${GH_RUNNER_URL:?Set GH_RUNNER_URL in /shared/github-runner.env or the host environment.}"

if [ -z "${GH_RUNNER_TOKEN:-}" ] && [ -z "${GH_RUNNER_API_TOKEN:-}" ]; then
    echo "Set GH_RUNNER_API_TOKEN (preferred) or GH_RUNNER_TOKEN in /shared/github-runner.env or the host environment." >&2
    exit 1
fi

if [ ! -x /opt/actions-runner/config.sh ]; then
    echo "GitHub runner is not installed. Run the base provisioner first." >&2
    exit 1
fi

runner_url="${GH_RUNNER_URL%/}"
case "$runner_url" in
    https://*)
        runner_scheme="https"
        ;;
    http://*)
        runner_scheme="http"
        ;;
    *)
        echo "GH_RUNNER_URL must start with http:// or https:// and point to a repository or organization root." >&2
        exit 1
        ;;
esac

runner_url_no_scheme="${runner_url#*://}"
runner_host="${runner_url_no_scheme%%/*}"
runner_path=""
if [ "$runner_url_no_scheme" != "$runner_host" ]; then
    runner_path="/${runner_url_no_scheme#*/}"
fi
runner_path="${runner_path%%\?*}"
runner_path="${runner_path%%\#*}"
runner_path="${runner_path%/}"

IFS='/' read -r runner_segment1 runner_segment2 runner_segment3 _runner_extra <<< "${runner_path#/}"

if [ -z "${runner_segment1:-}" ]; then
    echo "GH_RUNNER_URL must point to a repository or organization root, for example https://github.com/OWNER/REPOSITORY." >&2
    exit 1
fi

if [ -n "${runner_segment3:-}" ] || [ -n "${_runner_extra:-}" ]; then
    echo "GH_RUNNER_URL must be a repository or organization root URL, not a deeper settings page." >&2
    exit 1
fi

runner_scope="organization"
runner_owner="$runner_segment1"
runner_repo=""
if [ -n "${runner_segment2:-}" ]; then
    runner_scope="repository"
    runner_repo="${runner_segment2%.git}"
fi

runner_api_base="${GH_RUNNER_API_URL:-}"
if [ -z "$runner_api_base" ]; then
    if [ "$runner_host" = "github.com" ]; then
        runner_api_base="https://api.github.com"
    else
        runner_api_base="${runner_scheme}://${runner_host}/api/v3"
    fi
fi
runner_api_base="${runner_api_base%/}"

create_registration_token() {
    local endpoint response http_code body token expires_at message

    if [ -n "${GH_RUNNER_API_TOKEN:-}" ]; then
        case "$runner_scope" in
            repository)
                endpoint="${runner_api_base}/repos/${runner_owner}/${runner_repo}/actions/runners/registration-token"
                ;;
            organization)
                endpoint="${runner_api_base}/orgs/${runner_owner}/actions/runners/registration-token"
                ;;
            *)
                echo "Unsupported runner scope: $runner_scope" >&2
                exit 1
                ;;
        esac

        response="$(
            curl -sS -X POST \
                -H "Accept: application/vnd.github+json" \
                -H "Authorization: Bearer ${GH_RUNNER_API_TOKEN}" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "$endpoint" \
                -w $'\n%{http_code}'
        )"

        http_code="${response##*$'\n'}"
        body="${response%$'\n'*}"

        if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
            message="$(printf '%s' "$body" | jq -r '.message // empty' 2>/dev/null || true)"
            echo "Failed to create a runner registration token from ${endpoint} (HTTP ${http_code})." >&2
            if [ -n "$message" ]; then
                echo "GitHub API message: ${message}" >&2
            fi
            echo "Check that GH_RUNNER_API_TOKEN has admin access to the target and the required runner permissions." >&2
            exit 1
        fi

        token="$(printf '%s' "$body" | jq -r '.token // empty')"
        expires_at="$(printf '%s' "$body" | jq -r '.expires_at // empty')"
        if [ -z "$token" ]; then
            echo "GitHub did not return a runner registration token." >&2
            exit 1
        fi

        export RUNNER_TOKEN="$token"
        if [ -n "$expires_at" ]; then
            echo "Generated a fresh runner registration token via the GitHub API (expires at ${expires_at})."
        else
            echo "Generated a fresh runner registration token via the GitHub API."
        fi
        return 0
    fi

    export RUNNER_TOKEN="${GH_RUNNER_TOKEN}"
    echo "Using GH_RUNNER_TOKEN from the environment. GitHub runner registration tokens expire after one hour."
}

runner_name="${GH_RUNNER_NAME:-$(hostname -s)}"
runner_labels="${GH_RUNNER_LABELS:-self-hosted,linux,vagrant}"
runner_group="${GH_RUNNER_GROUP:-Default}"
runner_workdir="${GH_RUNNER_WORKDIR:-_work}"
runner_disable_update="${GH_RUNNER_DISABLE_UPDATE:-false}"

export RUNNER_URL="$GH_RUNNER_URL"
export RUNNER_NAME="$runner_name"
export RUNNER_LABELS="$runner_labels"
export RUNNER_GROUP="$runner_group"
export RUNNER_WORKDIR="$runner_workdir"
export RUNNER_DISABLE_UPDATE="$runner_disable_update"

if [ ! -f /opt/actions-runner/.runner ]; then
    create_registration_token
    sudo -u github-runner --preserve-env=RUNNER_URL,RUNNER_TOKEN,RUNNER_NAME,RUNNER_LABELS,RUNNER_GROUP,RUNNER_WORKDIR,RUNNER_DISABLE_UPDATE bash <<'EOF'
set -euo pipefail
cd /opt/actions-runner

config_args=(
    ./config.sh
    --unattended
    --url "$RUNNER_URL"
    --token "$RUNNER_TOKEN"
    --name "$RUNNER_NAME"
    --labels "$RUNNER_LABELS"
    --work "$RUNNER_WORKDIR"
    --replace
)

if [ "$RUNNER_GROUP" != "Default" ]; then
    config_args+=(--runnergroup "$RUNNER_GROUP")
fi

if [ "$RUNNER_DISABLE_UPDATE" = "true" ]; then
    config_args+=(--disableupdate)
fi

"${config_args[@]}"
EOF
fi

install -d /etc/needrestart/conf.d
cat <<'EOF' > /etc/needrestart/conf.d/actions_runner_services.conf
$nrconf{override_rc}{qr(^actions\.runner\..+\.service$)} = 0;
EOF

if ! compgen -G "/etc/systemd/system/actions.runner.*.service" >/dev/null; then
    (
        cd /opt/actions-runner
        ./svc.sh install github-runner
    )
fi

systemctl daemon-reload

service_units=(/etc/systemd/system/actions.runner.*.service)
if [ "${service_units[0]}" = "/etc/systemd/system/actions.runner.*.service" ]; then
    echo "Runner service unit was not created." >&2
    exit 1
fi

for service_unit in "${service_units[@]}"; do
    systemctl enable --now "$(basename "$service_unit")"
done

echo "GitHub runner configured and started successfully."
#
