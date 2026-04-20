#!/bin/bash

# This script performs local setup: Docker image building and deployment via Docker Desktop (Kubernetes)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}RouteGate - Local Docker Desktop Setup...${NC}"
echo
echo "This script will:"
echo "  1. Build Docker images locally"
echo "  2. Deploy the application to local Kubernetes (Docker Desktop)"
echo
echo -e "${YELLOW}Prerequisites:${NC}"
echo "  - Docker Desktop installed and running"
echo "  - Kubernetes enabled in Docker Desktop settings"
echo "  - kubectl configured to use docker-desktop context"
echo

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

# Check kubectl is available
if ! command -v kubectl > /dev/null 2>&1; then
    echo -e "${RED}Error: kubectl not found. Please install kubectl or enable Kubernetes in Docker Desktop.${NC}"
    exit 1
fi

# Switch to docker-desktop context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
if [ "$CURRENT_CONTEXT" != "docker-desktop" ]; then
    echo -e "${YELLOW}Switching kubectl context to docker-desktop...${NC}"
    if ! kubectl config use-context docker-desktop 2>/dev/null; then
        echo -e "${RED}Error: Could not switch to docker-desktop context.${NC}"
        echo "Please enable Kubernetes in Docker Desktop: Settings > Kubernetes > Enable Kubernetes"
        exit 1
    fi
fi

echo -e "${GREEN}Using Kubernetes context: docker-desktop${NC}"
echo

read -p "Do you want to proceed? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi


echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Building Docker Images${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Use a local image prefix instead of GCR
IMAGE_PREFIX="routegate"

# Build API Service
echo -e "${YELLOW}[1/3] Building API Service...${NC}"
docker build -t ${IMAGE_PREFIX}/api-service:v1 \
    -t ${IMAGE_PREFIX}/api-service:latest \
    ./api-service
echo -e "${GREEN}API Service built successfully${NC}"
echo

# Build Weather Service
echo -e "${YELLOW}[2/3] Building Weather Service...${NC}"
docker build -t ${IMAGE_PREFIX}/weather-service:v1 \
    -t ${IMAGE_PREFIX}/weather-service:latest \
    ./weather-service
echo -e "${GREEN}Weather Service built successfully${NC}"
echo

# Build Frontend
echo -e "${YELLOW}[3/3] Building Frontend...${NC}"
docker build -t ${IMAGE_PREFIX}/frontend:v1 \
    -t ${IMAGE_PREFIX}/frontend:latest \
    ./frontend
echo -e "${GREEN}Frontend built successfully${NC}"
echo

echo -e "${GREEN}All images built locally (no push needed for Docker Desktop)${NC}"
echo


echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploying to Local Kubernetes${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Create temporary directory for processed manifests
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

echo -e "${YELLOW}Preparing Kubernetes manifests for local use...${NC}"

# Process each manifest: replace GCR image paths with local image names
# and set imagePullPolicy to Never (use locally built images)
for file in k8s/*.yaml; do
    filename=$(basename "$file")
    # Replace gcr.io/${GCP_PROJECT_ID}/ prefix with local routegate/ prefix
    # and add imagePullPolicy: Never so Kubernetes uses local images
    sed \
        -e 's|gcr\.io/[^/]*/\(.*\):\(.*\)|routegate/\1:\2|g' \
        "$file" > "$TMP_DIR/$filename"

    # Inject imagePullPolicy: Never after each image: line (for local dev)
    sed -i 's|\(.*image: routegate/.*\)|\1\n\0|' "$TMP_DIR/$filename" 2>/dev/null || true
    python3 - "$TMP_DIR/$filename" <<'EOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# Insert imagePullPolicy: Never after any local image reference if not already present
lines = content.split('\n')
result = []
for i, line in enumerate(lines):
    result.append(line)
    if re.match(r'\s*image:\s*routegate/', line):
        # Check if next line already sets imagePullPolicy
        next_line = lines[i+1] if i+1 < len(lines) else ''
        if 'imagePullPolicy' not in next_line:
            indent = len(line) - len(line.lstrip())
            result.append(' ' * indent + 'imagePullPolicy: Never')

with open(path, 'w') as f:
    f.write('\n'.join(result))
EOF

    echo "  Processed $filename"
done

echo
echo -e "${GREEN}Deploying to Kubernetes...${NC}"
echo

# Step 1: MySQL PersistentVolume and Secret
echo -e "${YELLOW}[1/7] Creating MySQL PersistentVolume and Secret...${NC}"
kubectl apply -f "$TMP_DIR/1-mysql-pv.yaml"
echo -e "${GREEN}MySQL PV and Secret created${NC}"
sleep 2
echo

# Step 2: MySQL Deployment
echo -e "${YELLOW}[2/7] Deploying MySQL...${NC}"
kubectl apply -f "$TMP_DIR/2-mysql-deployment.yaml"
kubectl wait --for=condition=ready pod -l app=mysql --timeout=300s || {
    echo -e "${RED}MySQL pod failed to become ready${NC}"
    kubectl get pods -l app=mysql
    kubectl logs -l app=mysql --tail=50
    exit 1
}
echo -e "${GREEN}MySQL is ready${NC}"
sleep 5
echo

# Step 3: Initialize Database
echo -e "${YELLOW}[3/7] Initializing Database...${NC}"
kubectl apply -f "$TMP_DIR/3-init-db-job.yaml"
kubectl wait --for=condition=complete job/init-db --timeout=300s || {
    echo -e "${RED}Database initialization job failed${NC}"
    kubectl logs job/init-db --tail=100
    exit 1
}
echo -e "${GREEN}Database initialized successfully${NC}"
echo

# Step 4: Deploy Weather Service
echo -e "${YELLOW}[4/7] Deploying Weather Service...${NC}"
kubectl apply -f "$TMP_DIR/4-weather-deployment.yaml"
kubectl wait --for=condition=available deployment/weather-service --timeout=180s
echo -e "${GREEN}Weather Service deployed${NC}"
echo

# Step 5: Deploy API Service
echo -e "${YELLOW}[5/7] Deploying API Service...${NC}"
kubectl apply -f "$TMP_DIR/5-api-deployment.yaml"
kubectl wait --for=condition=available deployment/api-service --timeout=180s
echo -e "${GREEN}API Service deployed${NC}"
echo

# Step 6: Deploy Frontend
echo -e "${YELLOW}[6/7] Deploying Frontend...${NC}"
kubectl apply -f "$TMP_DIR/6-frontend-deployment.yaml"
kubectl wait --for=condition=available deployment/frontend --timeout=180s
echo -e "${GREEN}Frontend deployed${NC}"
echo

# Step 7: Deploy HPA
echo -e "${YELLOW}[7/7] Deploying Horizontal Pod Autoscaler...${NC}"
kubectl apply -f "$TMP_DIR/7-hpa.yaml"
echo -e "${GREEN}HPA configured${NC}"
echo

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Display deployment status
echo -e "${BLUE}Deployment Status:${NC}"
kubectl get deployments
echo

echo -e "${BLUE}Service Status:${NC}"
kubectl get services
echo

# For Docker Desktop, services are accessed via localhost
echo -e "${BLUE}Access your app:${NC}"
FRONTEND_PORT=$(kubectl get svc frontend -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
if [ -n "$FRONTEND_PORT" ]; then
    echo "  Frontend: http://localhost:${FRONTEND_PORT}"
else
    # LoadBalancer on Docker Desktop maps to localhost
    echo "  Frontend: http://localhost"
    echo "  (If using LoadBalancer type, Docker Desktop routes it to localhost automatically)"
fi

echo
echo -e "${BLUE}Demo Credentials:${NC}"
echo "  Email: demo@routegate.com"
echo "  Password: demo123"
echo

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo

echo -e "${YELLOW}Useful commands:${NC}"
echo "  kubectl get pods                  # Check pod status"
echo "  kubectl get services              # Check service endpoints"
echo "  kubectl logs -l app=api-service   # View API logs"
echo "  kubectl delete -f k8s/            # Tear down everything"
echo
