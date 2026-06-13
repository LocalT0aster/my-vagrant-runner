Vagrant.configure("2") do |config|
  box_name = "alvistack/ubuntu-24.04"
  runner_vm_ip = ENV.fetch("RUNNER_VM_IP", "192.168.121.51")

  host_ssh_key = File.expand_path("~/.ssh/vagrant")
  host_ssh_pub = "#{host_ssh_key}.pub"
  fallback_ssh_key = File.expand_path("~/.vagrant.d/insecure_private_key")

  runner_env = {
    "GH_RUNNER_VERSION" => ENV.fetch("GH_RUNNER_VERSION", ""),
    "GH_RUNNER_URL" => ENV.fetch("GH_RUNNER_URL", ""),
    "GH_RUNNER_TOKEN" => ENV.fetch("GH_RUNNER_TOKEN", ""),
    "GH_RUNNER_API_TOKEN" => ENV.fetch("GH_RUNNER_API_TOKEN", ""),
    "GH_RUNNER_API_URL" => ENV.fetch("GH_RUNNER_API_URL", ""),
    "GH_RUNNER_NAME" => ENV.fetch("GH_RUNNER_NAME", ""),
    "GH_RUNNER_LABELS" => ENV.fetch("GH_RUNNER_LABELS", ""),
    "GH_RUNNER_GROUP" => ENV.fetch("GH_RUNNER_GROUP", ""),
    "GH_RUNNER_WORKDIR" => ENV.fetch("GH_RUNNER_WORKDIR", ""),
    "GH_RUNNER_DISABLE_UPDATE" => ENV.fetch("GH_RUNNER_DISABLE_UPDATE", "")
  }

  configure_common_vm = lambda do |machine, hostname:, ip:, cpus:, memory:|
    machine.vm.box = box_name
    machine.vm.box_check_update = false
    machine.vm.hostname = hostname

    machine.ssh.insert_key = false
    machine.ssh.private_key_path = [host_ssh_key, fallback_ssh_key]

    machine.vm.synced_folder ".", "/vagrant", disabled: true
    machine.vm.synced_folder "./shared", "/shared"
    machine.vm.network "private_network", ip: ip

    if File.exist?(host_ssh_pub)
      machine.vm.provision "file", source: host_ssh_pub, destination: "/tmp/vagrant.pub"
      machine.vm.provision "shell",
        name: "install-host-ssh-key",
        inline: <<-SHELL
          set -euo pipefail
          if [ ! -f /tmp/vagrant.pub ]; then
            echo "Skipping host SSH key install: /tmp/vagrant.pub not found."
            exit 0
          fi
          install -d -m 700 /home/vagrant/.ssh
          touch /home/vagrant/.ssh/authorized_keys
          pub_key="$(cat /tmp/vagrant.pub)"
          grep -qxF "$pub_key" /home/vagrant/.ssh/authorized_keys || echo "$pub_key" >> /home/vagrant/.ssh/authorized_keys
          chown -R vagrant:vagrant /home/vagrant/.ssh
          chmod 700 /home/vagrant/.ssh
          chmod 600 /home/vagrant/.ssh/authorized_keys
          rm -f /tmp/vagrant.pub
        SHELL
    end

    machine.vm.provider :libvirt do |libvirt|
      libvirt.cpus = cpus.to_i
      libvirt.memory = memory.to_i
    end
  end

  config.vm.define "github-runner", primary: true do |runner|
    configure_common_vm.call(
      runner,
      hostname: "github-runner-s26",
      ip: runner_vm_ip,
      cpus: ENV.fetch("RUNNER_VM_CPUS", "4"),
      memory: ENV.fetch("RUNNER_VM_MEMORY", "8192")
    )

    runner.vm.provision "shell",
      name: "kernel-update",
      path: "shared/provision.sh",
      reboot: true
    runner.vm.provision "shell", name: "post-kernel", path: "shared/provision-post-kernel.sh"
    runner.vm.provision "shell",
      name: "github-runner-base",
      path: "shared/provision-gh-runner.sh",
      env: runner_env
    runner.vm.provision "shell",
      name: "github-runner-register",
      path: "shared/provision-gh-runner-register.sh",
      env: runner_env,
      run: "never"
  end
end
