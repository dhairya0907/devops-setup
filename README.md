# DevOps Setup: Self-Hosted CI/CD Infrastructure

Scripts to automate the setup of a self-hosted CI/CD environment using Multipass and Docker.  
This repository provides the foundation for a secure, private development and production server infrastructure for personal projects.

---

## Architecture Overview

This setup creates a professional "pull-based" CI/CD model, where the `docker-compose.yml` is treated as version-controlled application code, ensuring consistent deployments, keeping your production environment secure and minimal.

1. **`dev-server` (Build Server):**  
   Acts as a self-hosted CI runner. It checks out code from a Git remote, builds Docker images, pushes them to the production registry, and securely copies the project's configuration (including `docker-compose.yml`) to the production server.

2. **`prod-server` (Runtime Server):**  
   A minimal, secure server whose only job is to run the Docker registry and the final application containers.  
   It actively monitors the registry for new images and automatically pulls and deploys them when found.

---

## Scripts in this Repository

This repository provides the scripts to provision and manage the self-hosted CI/CD pipeline.

- **`scripts/provision/setup_vm.sh`:**  
  The foundational script. Provisions the `dev-server` and `prod-server` VMs with all necessary tools, security hardening, and configurations.

- **`scripts/ci/ci_runner.sh`:**  
  The self-hosted CI script that runs on the `dev-server` to monitor, build, and push new releases.

- **`scripts/cd/deployment_poller.sh`:**  
  The self-hosted CD script that runs on the `prod-server` to monitor the registry and trigger deployments.

- **`scripts/cd/deploy.sh`:**  
  The script that performs the zero-downtime deployment on the `prod-server`.

- **`scripts/utils/project-init.sh`:**  
  An interactive utility script to set up a new project with the required CI/CD configuration files.

- **`scripts/utils/publish.sh`:**  
  A global command to automate the release process for a project from the `dev-server`.

- **`scripts/utils/notify.sh`:**  
  A global notification utility script for sending messages to Slack and Email.

- **`scripts/install/install_docker.sh`:**  
  A standalone utility script to install Docker and Git on a fresh Ubuntu system.

- **`scripts/install/uninstall_docker.sh`:**  
  A standalone utility script to completely remove Docker and Git from a system.

---

## Getting Started: Provisioning the Infrastructure

The first step is to use the `setup_vm.sh` script to create your servers.

### 1. Prerequisites

Before running the setup script, you must have the following installed on your local machine:

- [Multipass](https://canonical.com/multipass/install)

### 2. Provision the VMs

1. **Configure the Environment:**  
   The script is configured using a `.env` file. If you run the script without one, it will automatically generate a template for you.  
   **Set a strong `REGISTRY_PASSWORD`** before proceeding.

2. **Make the script executable:**

   ```bash
   chmod +x scripts/provision/setup_vm.sh
   ```

3. **Run the script (in order):**

   - First, set up the production server:

     ```bash
     ./scripts/provision/setup_vm.sh prod
     ```

   - Second, set up the development server (replace the path with your own):

     ```bash
     ./scripts/provision/setup_vm.sh dev /Users/your-user/Developer
     ```

### 3. Connect to Your VMs

The setup script automatically adds aliases to your local `~/.ssh/config` file. You can connect to your new servers with these simple commands:

- **Connect to the Dev Server (as the developer user):**

  ```bash
  ssh dev-server
  ```

- **Connect to the Dev Server (as the automation user):**

  ```bash
  ssh dev-server-automation
  ```

- **Connect to the Prod Server:**

  ```bash
  ssh prod-server
  ```

---

## Utility Scripts

This repository also contains standalone scripts for system administration and development workflows.

- **To initialize a new project:**

  ```bash
  # Run this from an empty project directory on your dev-server
  chmod +x scripts/utils/project-init.sh
  ./scripts/utils/project-init.sh
  ```

- **To publish a new release:**

  ```bash
  # Installation:
  sudo cp scripts/utils/publish.sh /usr/local/bin/publish && sudo chmod +x /usr/local/bin/publish

  # Usage (from a project directory):
  publish
  ```

- **To run the CI process (as the automation user on `dev-server`):**

  ```bash
  # This script monitors for new releases and builds/pushes images.
  # It should be configured and run in the background.
  chmod +x scripts/ci/ci_runner.sh
  nohup ./scripts/ci/ci_runner.sh <prod_ip> <port> <interval> &
  ```

- **To run the CD process (on `prod-server`):**

  ```bash
  # This script monitors the registry and deploys new images.
  # It should be configured and run in the background.
  chmod +x scripts/cd/deployment_poller.sh scripts/cd/deploy.sh
  nohup ./scripts/cd/deployment_poller.sh <port> <interval> &
  ```

- **To send a notification (requires manual setup of `/etc/notify.conf`):**

  ```bash
  # Installation:
  sudo cp scripts/utils/notify.sh /usr/local/bin/notify && sudo chmod +x /usr/local/bin/notify

  notify --channel slack "Hello!"
  ```

- **To install Docker and Git on any Ubuntu machine:**

  ```bash
  chmod +x scripts/install/install_docker.sh
  ./scripts/install/install_docker.sh
  ```

- **To completely remove Docker and Git:**

  ```bash
  chmod +x scripts/install/uninstall_docker.sh
  ./scripts/install/uninstall_docker.sh
  ```

---

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
