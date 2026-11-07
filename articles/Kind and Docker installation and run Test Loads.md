
Running Kubernetes inside Docker on an **ARM64 VM** (such as AWS Graviton, Apple Silicon Linux VM, Raspberry Pi 64-bit, or Ampere instances) can be accomplished using **`kind` (Kubernetes in Docker)** or **`minikube`** with the Docker driver.

Below is a step-by-step guide to installing **`kind`** (or **`minikube`**) and **`kubectl`** compiled for ARM64 architectures, followed by deploying and testing sample workloads.

---

### Step 1: Install Prerequisites (`kubectl` & `kind`)

Run these commands inside your ARM64 VM terminal:

#### 1. Install `kubectl` (ARM64 binary)

```bash
# Download ARM64 kubectl binary
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"

# Make it executable and move to /usr/local/bin
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client

```

#### 2. Install `kind` (Kubernetes in Docker for ARM64)

```bash
# Download ARM64 kind binary
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-arm64

# Make it executable and move to /usr/local/bin
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Verify installation
kind version

```

*(Alternatively, if you prefer `minikube` over `kind`, install minikube ARM64 via `curl -LO [https://storage.googleapis.com/minikube/releases/latest/minikube-linux-arm64](https://storage.googleapis.com/minikube/releases/latest/minikube-linux-arm64) && sudo install minikube-linux-arm64 /usr/local/bin/minikube` and run `minikube start --driver=docker`).*

---

### Step 2: Create a Kubernetes Cluster in Docker

Make sure Docker is installed and your user has permission to run `docker` commands without `sudo` (`sudo usermod -aG docker $USER` and log back in).

##### Install Docker

```bash
sudo apt-get update
# Remove any conflicting or older container runtime packages and install the required tools for adding repositories.
sudo apt-get remove -y docker docker-engine docker.io containerd runc
sudo apt-get install -y ca-certificates curl gnupg

#Add Docker's official GPG key and set up the stable repository matching your system architecture (`arm64`).
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

#Add your current user to the `docker` group so you can execute `docker` and `kind` commands without prepending `sudo`.
sudo usermod -aG docker $USER

docker run --rm hello-world

#in-case of error - permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
newgrp docker

# then run docker run --rm hello-world again



```

```bash

#### Create a Cluster with `kind`
kind create cluster --name arm64-cluster

```

Verify your cluster status:

```bash
kubectl get nodes -o wide

```

*Note: In the output, you will see `Architecture: arm64` listed for the node.*

---

### Step 3: Run Test Workloads

Since you are running on ARM64, ensure the container images you test support the `linux/arm64` platform (most popular official images like NGINX, Redis, and Apache echo-server do).

#### Test Workload 1: Deploying a Multi-Architecture NGINX Web Server

1. **Create the Deployment:**
```bash
kubectl create deployment nginx-test --image=nginx:alpine --replicas=2

```


2. **Verify Pod Status & Node Placement:**
```bash
kubectl get pods -l app=nginx-test -o wide

```


3. **Expose the Deployment as a Service:**
```bash
kubectl expose deployment nginx-test --type=NodePort --port=80

```


4. **Verify the Service & Test Connectivity:**
```bash
kubectl get svc nginx-test

# Test internal pod response directly using port-forwarding
# If you just want the port-forward to survive after you close your current terminal window or log out of your SSH session, use `nohup` combined with redirection to suppress output logs.
nohup kubectl port-forward svc/nginx-test 8080:80 > /dev/null 2>&1 &
curl http://localhost:8080
pkill -f "kubectl port-forward"
```



---

#### Test Workload 2: Deploying a Stateless Microservice (Echo Server)

1. **Deploy an HTTP Echo app:**
```bash
kubectl create deployment echo-app --image=ealen/echo-server:latest
kubectl expose deployment echo-app --type=ClusterIP --port=80 --target-port=80

```


2. **Test End-to-End Routing via `kubectl exec`:**
```bash
# Run a temporary curl container inside the cluster to query the service
# Run a temporary curl container inside the cluster to query the service
kubectl run test-curl --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s http://echo-app.default.svc.cluster.local

```



---

### Step 4: Cleanup

When you are finished testing, delete your local Docker Kubernetes cluster:

```bash
kind delete cluster --name arm64-cluster
# to retain cluster and remove workloads
kubectl delete all --all -n default
```

---
