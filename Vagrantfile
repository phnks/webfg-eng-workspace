# -*- mode: ruby -*-
# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'base64' # Needed for encoding the private key

# Get the target username from the environment variable
# This will be used to define the specific machine Vagrant manages
dev_username = ENV['DEV_USERNAME']
unless dev_username
  raise "Environment variable DEV_USERNAME must be set!"
end

# Construct the desired VM name for VirtualBox
vm_name = "dev-#{dev_username}-vm"

# --- Define GitHub App Credentials per User ---
# Store credentials in a hash keyed by username
github_creds = {
  "anum" => {
    app_id: "1210600",
    install_id: "64247573",
    key_path: "config/anum-bot-app.2025-04-09.private-key.pem",
    git_name: "anum-bot",
    git_email: "1210600+anum-bot@users.noreply.github.com"
  },
  "homonculus" => {
    app_id: "1210603",
    install_id: "64247782",
    key_path: "config/homonculus-bot-app.2025-04-09.private-key.pem",
    git_name: "homonculus-bot",
    git_email: "1210603+homonculus-bot@users.noreply.github.com"
  }
  # Add more users here if needed
}

# Get the specific credentials for the current dev_username
current_creds = github_creds[dev_username]
unless current_creds
  raise "GitHub credentials not defined in Vagrantfile for user: #{dev_username}"
end

# --- Prepare Environment Variables ---
# We now expect GH_INSTALLATION_TOKEN to be set in the environment
# before Vagrant runs (e.g., by the calling provision_vm.sh script).
gh_installation_token = ENV['GH_INSTALLATION_TOKEN']
unless gh_installation_token
    raise "Environment variable GH_INSTALLATION_TOKEN must be set!"
end

# Get the specific Git author credentials for the current dev_username
current_creds = github_creds[dev_username]
unless current_creds
  raise "GitHub credentials not defined in Vagrantfile for user: #{dev_username}"
end

# Prepare environment variables for the provisioner
provision_env = {
  "DEV_USER" => dev_username,
  "GH_INSTALLATION_TOKEN" => gh_installation_token, # Pass the token from the environment
  "GIT_AUTHOR_NAME" => current_creds[:git_name],
  "GIT_AUTHOR_EMAIL" => current_creds[:git_email]
}
# --- End Environment Setup ---


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
      vb.memory = "8192" # Allocate 8GB RAM
      vb.cpus = "4"      # Allocate 4 CPU cores

      # Set the name that appears in the VirtualBox GUI
      # This uses the vm_name calculated outside the block
      vb.name = vm_name

      # Enable bidirectional shared clipboard
      vb.customize ["modifyvm", :id, "--clipboard-mode", "bidirectional"]
    end

    # --- Networking ---
    # Use Bridged Networking (public_network) to get an IP on the host's LAN
    # Specify the bridge interface directly to avoid interactive prompts.
    # Replace "wlp41s0" if your desired host interface is different.
    machine_config.vm.network "public_network", bridge: "wlp41s0"

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
      # Pass the specific username AND GitHub credentials to the guest script
      env: provision_env, # Use the hash prepared above
      path: "guest_scripts/setup_dev.sh",
      args: "" # Optional arguments to the script if needed

    # Optional: Install Guest Additions if not handled by the box/plugin
    # machine_config.vbguest.auto_update = true # Requires vagrant-vbguest plugin
  end # End of config.vm.define

end
