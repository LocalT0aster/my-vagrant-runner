# GitHub Runner Vagrant VM

Standalone Vagrant/libvirt setup for a self-hosted GitHub Actions runner.

- Box: `alvistack/ubuntu-24.04`
- Machine: `github-runner`
- Default hostname: `github-runner-s26`
- Default static IP: `192.168.121.51`
- Default resources: 4 vCPUs, 8192 MB RAM

## Requirements

- `vagrant`
- `libvirt` + `qemu`/`kvm`
- Vagrant plugin: `vagrant-libvirt`

## Usage

From this repository root:

```bash
vagrant plugin install vagrant-libvirt
vagrant up
vagrant ssh
```

Provisioning is split into two stages:

- `shared/provision.sh` (kernel/package update stage)
- automatic reboot between stages
- `shared/provision-post-kernel.sh` (post-kernel stage with ansible install)
- `shared/provision-gh-runner.sh` (runner VM only; installs the GitHub runner binaries)
- `shared/provision-gh-runner-register.sh` (runner VM only; manual registration step)

SSH key setup:

- host private key path: `~/.ssh/vagrant`
- host public key path: `~/.ssh/vagrant.pub`
- public key is added to `/home/vagrant/.ssh/authorized_keys` during provisioning

Static VM IP:

- default: `192.168.121.51`
- override: `RUNNER_VM_IP=192.168.121.61 vagrant up`

This setup uses:

- management NIC (`eth0`, DHCP) for Vagrant internals
- static NIC (`eth1`, fixed IP above) for your direct SSH usage

`~/.ssh/config` example:

```sshconfig
Host github-runner-s26
	HostName 192.168.121.51
	User vagrant
	IdentityFile ~/.ssh/vagrant
```

Base runner provisioning installs:

- `ansible`
- `git`, `curl`, `jq`, `tar`, `unzip`
- the GitHub Actions runner under `/opt/actions-runner`
- a dedicated `github-runner` user

Registration is a separate manual step because GitHub registration tokens are
short-lived.

1. Copy the example environment file:

```bash
cp shared/github-runner.env.example shared/github-runner.env
```

2. Edit `shared/github-runner.env` and fill in:

- `GH_RUNNER_URL`
- `GH_RUNNER_API_TOKEN` or `GH_RUNNER_TOKEN`
- optional runner name / labels / group / workdir

`GH_RUNNER_API_TOKEN` is the safer option because the provisioner will exchange it for a fresh one-hour runner registration token every time it runs. For a repository runner, GitHub's REST API requires a token that can create registration tokens for that repository. For a fine-grained PAT, that means repository `Administration: write`. A manually copied `GH_RUNNER_TOKEN` still works, but it expires after one hour and must be refreshed before provisioning.

If the runner VM is already running, sync updated shared files into the guest:

```bash
vagrant rsync github-runner
```

3. Run the registration provisioner:

```bash
vagrant provision github-runner --provision-with github-runner-register
```

You can also pass the same values through host environment variables instead of
using `shared/github-runner.env`.

Useful commands:

```bash
vagrant ssh github-runner
sudo systemctl list-units 'actions.runner.*'
sudo systemctl status 'actions.runner.*'
```

Notes:

- The registration step is idempotent for an already configured runner; it
  starts the service again if needed.
- The runner VM does not install Docker by default. For this lab's Ansible
  workflow, that is sufficient. If you later add container actions, install
  Docker on the runner VM as well.
