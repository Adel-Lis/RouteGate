#!/bin/bash

# This script removes all deployed resources from the local Docker (no Kubernetes) setup

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo
echo -e "${RED}WARNING: This will delete all RouteGate local resources including containers, Docker images, volumes, and network !!!${NC}"
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo
echo -e "${YELLOW}Stopping and removing containers...${NC}"

docker rm -f frontend 2>/dev/null || true
docker rm -f api-service 2>/dev/null || true
docker rm -f weather-service 2>/dev/null || true
docker rm -f mysql 2>/dev/null || true

echo
echo -e "${GREEN}All containers have been removed${NC}"
echo

echo
echo -e "${YELLOW}Deleting Docker images...${NC}"

docker rmi -f routegate/frontend:v1 routegate/frontend:latest 2>/dev/null || true
docker rmi -f routegate/api-service:v1 routegate/api-service:latest 2>/dev/null || true
docker rmi -f routegate/weather-service:v1 routegate/weather-service:latest 2>/dev/null || true

echo
echo -e "${GREEN}All Docker images have been deleted${NC}"
echo

echo
echo -e "${YELLOW}Deleting Docker volume...${NC}"

docker volume rm routegate-mysql-data 2>/dev/null || true

echo
echo -e "${GREEN}Docker volume has been deleted${NC}"
echo

echo
echo -e "${YELLOW}Deleting Docker network...${NC}"

docker network rm routegate-net 2>/dev/null || true

echo
echo -e "${GREEN}Docker network has been deleted${NC}"
echo

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup finished successfully${NC}"
echo -e "${GREEN}========================================${NC}"
