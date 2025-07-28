# DevOps Setup: Self-Hosted CI/CD Infrastructure

Scripts to automate the setup of a self-hosted CI/CD environment using Multipass and Docker.  
This repository provides the foundation for a secure, private development and production server infrastructure for personal projects.

---

## Architecture Overview

This setup creates a professional "pull over push" CI/CD model, keeping your production environment secure and minimal.

1. **`dev-server` (Build Server):**  
   Acts as a self-hosted CI runner. It is responsible for checking out code from GitHub (via the `automation` user), building Docker images, and pushing them to the production registry.

2. **`prod-server` (Runtime Server):**  
   A minimal, secure server whose only job is to run the Docker registry and the final application containers. It is triggered by a webhook from the `dev-server` to pull and deploy new images.

---

## Scripts in this Repository

This repository provides the scripts to provision and manage the self-hosted CI/CD pipeline.

- **`setup_vm.sh`:**  
  The foundational script. Provisions the `dev-server` and `prod-server` VMs with all necessary tools, security hardening, and configurations.

- **`publish.sh`:**  
  A global command to automate the release process for a project from the `dev-server`.

- **`notify.sh`:**  
  A global notification utility script for sending messages to Slack and Email.

- **`install_docker.sh`:**  
  A standalone utility script to install Docker and Git on a fresh Ubuntu system.

- **`uninstall_docker.sh`:**  
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
   **Set a strong `REGISTRY_PASSWORD` before proceeding.**

2. **Make the script executable:**

   ```bash
   chmod +x setup_vm.sh
   ```

3. **Run the script (in order):**

   - First, set up the production server:

     ```bash
     ./setup_vm.sh prod
     ```

   - Second, set up the development server (replace the path with your own):

     ```bash
     ./setup_vm.sh dev /Users/your-user/Developer
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

- **To publish a new release:**  
  The `publish.sh` script should be installed as a global command on your build server (e.g., `dev-server`).

  - **Installation:**

    ```bash
    sudo cp publish.sh /usr/local/bin/publish && sudo chmod +x /usr/local/bin/publish
    ```

  - **Usage (from a project directory):**

    ```bash
    publish
    ```

- **To send a notification:**  
  The `notify.sh` script should be installed globally on any server that needs to send alerts.

  - **Installation:**

    ```bash
    sudo cp notify.sh /usr/local/bin/notify && sudo chmod +x /usr/local/bin/notify
    ```

  - **Usage:**

    ```bash
    notify --channel slack "Hello!"
    ```

- **To install Docker and Git on any Ubuntu machine:**

  ```bash
  chmod +x install_docker.sh
  ./install_docker.sh
  ```

- **To completely remove Docker and Git:**

  ```bash
  chmod +x uninstall_docker.sh
  ./uninstall_docker.sh
  ```

---

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
