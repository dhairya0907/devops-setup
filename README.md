# DevOps Setup: Self-**Hosted** CI/CD Infrastructure

Scripts to automate the setup of a self-hosted CI/CD environment using Multipass and Docker. This repository provides the foundation for a secure, private development and production server infrastructure for personal projects.

## Architecture Overview

This setup creates a professional "pull over push" CI/CD model, keeping your production environment secure and minimal.

1. **`dev-server` (Build Server):** Acts as a self-hosted CI runner. It is responsible for checking out code from GitHub (via the `automation` user), building Docker images, and pushing them to the production registry.
2. **`prod-server` (Runtime Server):** A minimal, secure server whose only job is to run the Docker registry and the final application containers. It is triggered by a webhook from the `dev-server` to pull and deploy new images.

## Scripts in this Repository

This repository provides the scripts to provision and manage the self-hosted CI/CD pipeline.

- **`setup_vm.sh`:** The foundational script. Provisions the `dev-server` and `prod-server` VMs with all necessary tools, security hardening, and configurations.

## Getting Started

### 1. Prerequisites

Before running the setup script, you must have the following installed on your local machine:

- [Multipass](https://canonical.com/multipass/install)

### 2. Provision the Infrastructure

The first step is to use the `setup_vm.sh` script to create your servers.

1. **Configure the Environment:** The script is configured using a `.env` file. If you run the script without one, it will automatically generate a template for you. **Set a strong `REGISTRY_PASSWORD` before proceeding.**

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

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
