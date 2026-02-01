# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "flatrun-test"

  # Network configuration
  config.vm.network "forwarded_port", guest: 80, host: 8800
  config.vm.network "forwarded_port", guest: 443, host: 8443
  config.vm.network "forwarded_port", guest: 8080, host: 8880
  config.vm.network "forwarded_port", guest: 8090, host: 8890

  # Private network for easier access
  config.vm.network "private_network", ip: "192.168.56.10"

  # VM resources
  config.vm.provider "virtualbox" do |vb|
    vb.name = "flatrun-test"
    vb.memory = "2048"
    vb.cpus = 2
  end

  # Sync the installer directory
  config.vm.synced_folder ".", "/vagrant", type: "virtualbox"

  # Sync the agent and UI source for local dev testing
  config.vm.synced_folder "../agent", "/src/agent", type: "virtualbox"
  config.vm.synced_folder "../ui", "/src/ui", type: "virtualbox"

  # Provisioning script
  config.vm.provision "shell", inline: <<-SHELL
    set -e

    echo "==> Updating system packages..."
    apt-get update -qq
    export DEBIAN_FRONTEND=noninteractive
    apt-get upgrade -y -qq

    echo "==> Installing build dependencies..."
    apt-get install -y -qq curl git build-essential

    # Install Go
    if ! command -v go &> /dev/null; then
      echo "==> Installing Go..."
      curl -fsSL https://go.dev/dl/go1.23.4.linux-amd64.tar.gz -o /tmp/go.tar.gz
      rm -rf /usr/local/go
      tar -C /usr/local -xzf /tmp/go.tar.gz
      rm /tmp/go.tar.gz
      echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh
      source /etc/profile.d/go.sh
    fi
    export PATH=$PATH:/usr/local/go/bin

    # Install Node.js
    if ! command -v node &> /dev/null; then
      echo "==> Installing Node.js..."
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
      apt-get install -y -qq nodejs
    fi

    echo "==> Vagrant provisioning complete!"
    echo ""
    echo "To test the FlatRun installer:"
    echo "  vagrant ssh"
    echo "  sudo /vagrant/scripts/install.sh"
    echo ""
    echo "To test local dev build:"
    echo "  vagrant ssh"
    echo "  sudo /vagrant/scripts/install-dev.sh run"
    echo ""
    echo "Access FlatRun at:"
    echo "  http://192.168.56.10:8080/setup"
    echo "  http://localhost:8880/setup"
  SHELL
end
