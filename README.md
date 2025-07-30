# DevOps Setup: Self-Hosted CI/CD Infrastructure

Scripts to automate the setup of a self-hosted CI/CD environment using Multipass and Docker.  
This repository provides the foundation for a secure, private development and production server infrastructure for personal projects.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Scripts in this Repository](#scripts-in-this-repository)
- [End-to-End Setup and Usage](#end-to-end-setup-and-usage)
  - [Step 1: Provision the Infrastructure](#step-1-provision-the-infrastructure-one-time-setup)
  - [Step 2: Configure Your Projects](#step-2-configure-your-projects)
  - [Step 3: Using the Pipeline](#step-3-using-the-pipeline)
- [Standalone Utility Scripts](#standalone-utility-scripts)
- [License](#license)

## Architecture Overview

This setup creates a professional "pull-based" CI/CD model, where the `docker-compose.yml` is treated as version-controlled application code, ensuring consistent deployments while keeping your production environment secure and minimal.

1. **`dev-server` (Build Server):**  
   Acts as a self-hosted CI runner. It checks out code from a Git remote, builds Docker images, pushes them to the production registry, and securely copies the project's configuration (including `docker-compose.yml`) to the production server.

2. **`prod-server` (Runtime Server):**  
   A minimal, secure server whose only job is to run the Docker registry and the final application containers.  
   It actively monitors the registry for new images and automatically pulls and deploys them when found.

## Scripts in this Repository

This repository contains a collection of scripts that work together to create and manage the CI/CD pipeline.  
The main `setup_vm.sh` script automatically deploys and configures all the other scripts.

- `scripts/provision/setup_vm.sh`:  
  The master orchestration script. It provisions the VMs and deploys the entire CI/CD toolchain.

- `scripts/ci/ci_runner.sh`:  
  The self-hosted CI service that runs on the `dev-server`.

- `scripts/cd/deployment_poller.sh`:  
  The self-hosted CD service that runs on the `prod-server`.

- `scripts/cd/deploy.sh`:  
  The script that performs the zero-downtime deployment.

- `scripts/utils/project-init.sh`:  
  A global command to set up a new project.

- `scripts/utils/publish.sh`:  
  A global command to publish a new release.

- `scripts/utils/notify.sh`:  
  A global command for sending notifications.

- `scripts/install/install_docker.sh` & `uninstall_docker.sh`:  
  Standalone utility scripts for manual Docker management.

## End-to-End Setup and Usage

### Step 1: Provision the Infrastructure (One-Time Setup)

The first and only setup step is to run the master `setup_vm.sh` script.

1. **Prerequisites:**  
   Ensure you have [Multipass](https://canonical.com/multipass/install) installed on your local machine.

2. **Configure:**  
   The script is configured using a `.env` file. If one doesn't exist, the script will create a template for you.  
   **Fill this file with your secrets** (especially `REGISTRY_PASSWORD` and `SLACK_BOT_TOKEN`) before proceeding.

3. **Execute:**

```bash
chmod +x scripts/provision/setup_vm.sh

# First, set up the production server:
./scripts/provision/setup_vm.sh prod

# Second, set up the development server:
./scripts/provision/setup_vm.sh dev /Users/your-user/Developer
````

This single script will provision the VMs, harden the production server, and install/configure all the necessary scripts and background services.

### Step 2: Configure Your Projects

After the setup script is complete, your CI/CD pipeline is running. The final step is to tell it which projects to manage.

1. **Add Projects to the CI Runner:**

   * Connect to the `dev-server` as the automation user:
     `ssh dev-server-automation`
   * Edit the project list:
     `vim ~/ci-runner/projects.list`
   * Add the full Git SSH URLs for the repositories you want to monitor.

2. **Add Projects to the CD Poller:**

   * Connect to the `prod-server`:
     `ssh prod-server`
   * Edit the project list:
     `vim ~/deploy-runner/projects-prod.list`
   * Add the `project_name` for each repository you want to deploy.

3. **Add Project Secrets:**

   * On the `dev-server` as the `automation` user, create a directory for each project's secrets:
     `mkdir -p ~/secrets/my-project-name`
   * Place the production configuration files (e.g., `.env`, `prod-config.json`) inside this directory.
     The CI runner will automatically sync them to the `prod-server`.

### Step 3: Using the Pipeline

Once configured, the workflow is simple:

1. **Initialize a new project** using the `project-init` command on the `dev-server`.
2. **Develop your application.**
3. **Publish a new release** using the `publish` command from your project directory on the `dev-server`.

The rest of the process is fully automated.

## Standalone Utility Scripts

For manual administration or use outside the main pipeline, the following scripts can be run directly.

* **To initialize a new project:**

```bash
# Run this from an empty project directory
chmod +x scripts/utils/project-init.sh
./scripts/utils/project-init.sh
```

* **To publish a new release:**

```bash
# This script should be installed as a global command.
# Installation:
sudo cp scripts/utils/publish.sh /usr/local/bin/publish && sudo chmod +x /usr/local/bin/publish

# Usage (from a project directory):
publish
```

* **To send a notification:**

```bash
# This script should be installed as a global command.
# Installation:
sudo cp scripts/utils/notify.sh /usr/local/bin/notify && sudo chmod +x /usr/local/bin/notify

# Usage:
notify --channel slack "Hello!"
```

* **To install Docker and Git on any Ubuntu machine:**

```bash
chmod +x scripts/install/install_docker.sh
./scripts/install/install_docker.sh
```

* **To completely remove Docker and Git:**

```bash
chmod +x scripts/install/uninstall_docker.sh
./scripts/install/uninstall_docker.sh
```

## License

This project is licensed under the MIT License.
See the `LICENSE` file for details.
