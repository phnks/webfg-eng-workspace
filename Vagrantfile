# -*- mode: ruby -*-
# vi: set ft=ruby :

# Get the target username from the environment variable
# This will be used to define the specific machine Vagrant manages
dev_username = ENV['DEV_USERNAME']
unless dev_username
  raise "Environment variable DEV_USERNAME must be set!"
end

# Construct the desired VM name for VirtualBox
vm_name = "dev-#{dev_username}-vm"

Vagrant.configure("2") do |config|
  # Define the specific machine based on the username environment variable
  # This makes Vagrant aware of 'homonculus', 'anum', etc. as distinct machines
  config.vm.define dev_username do |machine_config|
    # Use the Bento Ubuntu 24.04 LTS 64-bit server image
    machine_config.vm.box = "bento/ubuntu-24.04"
    machine_config.vm.box_check_update = true # Check for box updates on 'vagrant up'

    # Configure the VirtualBox provider
    machine_config.vm.provider "virtualbox" do |vb|
      # Enable the GUI for the VM
      vb.gui = true

      # Customize VM resources (adjust as needed)
      vb.memory = "4096" # Allocate 4GB RAM
      vb.cpus = "2"      # Allocate 2 CPU cores

      # Set the name that appears in the VirtualBox GUI
      # This uses the vm_name calculated outside the block
      vb.name = vm_name
    end

    # --- Port Forwarding ---
    # IMPORTANT: Simple port forwarding like guest: 22, host: 2222 will conflict
    # in a multi-machine setup. Vagrant can auto-correct, but it's better
    # to define a strategy if consistent ports are needed (e.g., user-specific ports).
    # For now, let Vagrant handle SSH port auto-correction if needed.
    # machine_config.vm.network "forwarded_port", guest: 22, host_ip: "127.0.0.1", host: 2222, auto_correct: true, id: "ssh"

    # Share the project directory into the VM at /vagrant
    # machine_config.vm.synced_folder ".", "/vagrant", disabled: true # Often enabled by default

    # Provision the VM using the setup script
    machine_config.vm.provision "shell",
      # Pass the specific username to the guest script via DEV_USER env var
      env: {"DEV_USER" => dev_username},
      path: "guest_scripts/setup_dev.sh",
      args: "" # Optional arguments to the script if needed

    # Optional: Install Guest Additions if not handled by the box/plugin
    # machine_config.vbguest.auto_update = true # Requires vagrant-vbguest plugin
  end # End of config.vm.define

end
