# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Use the Bento Ubuntu 24.04 LTS 64-bit server image
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_check_update = true # Check for box updates on 'vagrant up'

  # Configure the VirtualBox provider
  config.vm.provider "virtualbox" do |vb|
    # Enable the GUI for the VM
    vb.gui = true

    # Customize VM resources (adjust as needed)
    vb.memory = "4096" # Allocate 4GB RAM
    vb.cpus = "2"      # Allocate 2 CPU cores
    vb.name = "dev-#{ENV['DEV_USERNAME'] || 'default'}-vm" # Name the VM in VirtualBox GUI
  end

  # Forward a port for potential SSH access (optional, but good practice)
  # config.vm.network "forwarded_port", guest: 22, host: 2222, id: "ssh"

  # Share the project directory into the VM at /vagrant
  # config.vm.synced_folder ".", "/vagrant", disabled: true # Often enabled by default

  # Provision the VM using the setup script
  config.vm.provision "shell",
    env: {"DEV_USER" => ENV['DEV_USERNAME'] || 'devuser'}, # Pass host env var, provide default 'devuser'
    path: "guest_scripts/setup_dev.sh",
    args: "" # Optional arguments to the script if needed

  # Optional: Install Guest Additions if not handled by the box/plugin
  # config.vbguest.auto_update = true # Requires vagrant-vbguest plugin: vagrant plugin install vagrant-vbguest
end
