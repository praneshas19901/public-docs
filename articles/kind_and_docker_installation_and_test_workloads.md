# 🚀 Running Kubernetes in Docker on ARM64 Architecture

This guide provides a step-by-step walkthrough for installing **Docker**, **`kind` (Kubernetes in Docker)**, and **`kubectl`** tailored for **ARM64 VMs** (such as AWS Graviton, Apple Silicon Linux VMs, Raspberry Pi 64-bit, or Ampere instances), followed by deploying and testing sample multi-architecture workloads.

---

> [!NOTE]
> **Prerequisites:** 
> - An ARM64 Linux virtual machine or instance (e.g., Ubuntu 22.04 / 24.04 LTS).
> - User account with `sudo` privileges.

---

## 🛠️ Step 1: Install Docker Engine

Ensure Docker is installed and configured to run without requiring `sudo` for every command.

```bash
# 1. Update package index and remove conflicting legacy packages
sudo apt-get update
sudo apt-get remove -y docker docker-engine docker.io containerd runc
sudo apt-get install -y ca-certificates curl gnupg

# 2. Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 3. Add the Docker repository for ARM64
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Install Docker Engine and related plugins
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Manage Docker as a non-root user
sudo usermod -aG docker $USER
```

> [!TIP]
> **Permission Resolution:** If you encounter `permission denied while trying to connect to the Docker daemon socket`, refresh your group membership without logging out:
> ```bash
> newgrp docker
> ```

Verify the installation by running:
```bash
docker run --rm hello-world
```

---

## 📦 Step 2: Install `kubectl` & `kind` (ARM64 Binaries)

Run the following commands inside your ARM64 VM terminal:

### 1. Install `kubectl`
```bash
# Download the latest stable ARM64 kubectl binary
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"

# Make it executable and move it to system path
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client
```

### 2. Install `kind`
```bash
# Download ARM64 kind binary
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-arm64

# Make it executable and move it to system path
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Verify installation
kind version
```

> [!INFO]
> **Alternative Engine (`minikube`):**
> If you prefer `minikube` over `kind`, install the ARM64 binary:
> ```bash
> curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-arm64
> sudo install minikube-linux-arm64 /usr/local/bin/minikube
> minikube start --driver=docker
> ```

---

## ☸️ Step 3: Create a Local Kubernetes Cluster

### 1. Provision Cluster with `kind`
```bash
kind create cluster --name arm64-cluster
```

### 2. Verify Cluster Status
```bash
kubectl get nodes -o wide
```

> [!CHECK]
> Inspect the output column `ARCHITECTURE`. It should explicitly display **`arm64`**.

---

## 🧪 Step 4: Deploy & Test Sample Workloads

> [!IMPORTANT]
> **Architecture Compatibility:** When targeting ARM64 nodes, verify that your container images support the `linux/arm64` platform. Official images such as NGINX, Redis, and Curl natively support multi-architecture manifests.

---

### Workload 1: NGINX Web Server Deployment

#### 1. Create Deployment & Expose Service
```bash
# Create a 2-replica NGINX deployment
kubectl create deployment nginx-test --image=nginx:alpine --replicas=2

# Expose deployment internally
kubectl expose deployment nginx-test --type=NodePort --port=80
```

#### 2. Verify Pod Status
```bash
kubectl get pods -l app=nginx-test -o wide
```

#### 3. Test Connectivity via Port Forwarding
```bash
# Run port-forwarding in the background (survives SSH session drop)
nohup kubectl port-forward svc/nginx-test 8080:80 > /dev/null 2>&1 &

# Query the web server
curl http://localhost:8080

# Clean up background port-forward process
pkill -f "kubectl port-forward"
```

---

### Workload 2: Stateless Microservice (`echo-server`)

#### 1. Deploy the Application
```bash
# Deploy an HTTP Echo application
kubectl create deployment echo-app --image=ealen/echo-server:latest

# Expose via ClusterIP
kubectl expose deployment echo-app --type=ClusterIP --port=80 --target-port=80
```

#### 2. Test End-to-End Cluster Internal Routing
```bash
# Spin up an ephemeral container to query the internal service DNS
kubectl run test-curl --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s http://echo-app.default.svc.cluster.local
```

---

## 🧹 Step 5: Cleanup Resources

When you are finished testing, clean up your environment using one of the following methods:

### Option A: Complete Teardown (Delete Cluster)
```bash
kind delete cluster --name arm64-cluster
```

### Option B: Reset Default Namespace (Retain Cluster)
```bash
kubectl delete all --all -n default
```
