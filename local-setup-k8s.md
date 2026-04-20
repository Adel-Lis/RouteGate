# RouteGate - Local Setup with Kubernetes

This guide explains how to deploy RouteGate on your local machine using Docker Desktop with Kubernetes enabled. The entire process takes approximately 5-10 minutes.

> **Windows users:** We recommend using WSL (Windows Subsystem for Linux) with Docker Desktop. All commands below should be run inside a WSL terminal.

---

#### Prerequisites

Before starting, make sure you have:

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- Kubernetes enabled in Docker Desktop: **Settings → Kubernetes → Enable Kubernetes**
- WSL installed (Windows only): `wsl --install` in PowerShell, then restart

---

#### Step 1 - Clone the Repository

Open a WSL terminal and run:

```bash
git clone https://github.com/Adel13Lis/INFS3208-ROUTEGATE.git
cd INFS3208-ROUTEGATE
```

#### Step 2 - Make the Scripts Executable

```bash
chmod +x ./*.sh
```

#### Step 3 - Run the Setup Script

```bash
./setup-local.sh
```

Confirm by pressing `y` when prompted.

The script will:

- Build the Docker images locally
- Deploy all services to your local Kubernetes cluster

#### Step 4 - Access the Application

When the script finishes you will see:

```
========================================
Setup Complete!
========================================

Access your app:
  Frontend: http://localhost

Demo Credentials:
  Email: demo@routegate.com
  Password: demo123
```

Open `http://localhost` in your browser and log in with the demo credentials.

If the page does not load, check that all pods are running:

```bash
kubectl get pods
```

All pods should show status `Running`.

---

#### Step 5 - (Optional) Clean Up

To stop the application and remove all local resources, run:

```bash
./cleanup-local.sh
```

Confirm by pressing `y` when prompted.
