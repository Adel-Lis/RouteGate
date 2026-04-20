#!/bin/bash

# This script performs local setup: Docker image building and deployment via Docker (without Kubernetes)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}RouteGate - Local Docker Setup (No Kubernetes)...${NC}"
echo
echo "This script will:"
echo "  1. Build Docker images locally"
echo "  2. Deploy the application using Docker containers"
echo
echo -e "${YELLOW}Prerequisites:${NC}"
echo "  - Docker installed and running"
echo

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker.${NC}"
    exit 1
fi

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

echo -e "${GREEN}All images built locally${NC}"
echo


echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploying with Docker${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Step 1: Create Docker network
echo -e "${YELLOW}[1/6] Creating Docker network...${NC}"
docker network create routegate-net 2>/dev/null || true
echo -e "${GREEN}Docker network ready${NC}"
sleep 2
echo

# Step 2: Start MySQL
echo -e "${YELLOW}[2/6] Starting MySQL...${NC}"
docker rm -f mysql 2>/dev/null || true
docker run -d \
    --name mysql \
    --network routegate-net \
    -e MYSQL_ROOT_PASSWORD=RouteGate2024! \
    -e MYSQL_DATABASE=routegate \
    -v routegate-mysql-data:/var/lib/mysql \
    mysql:8.0
until docker exec -e MYSQL_PWD=RouteGate2024! mysql mysql -u root -e "SELECT 1" > /dev/null 2>&1; do
    echo "MySQL not ready, waiting..."
    sleep 5
done
echo -e "${GREEN}MySQL is ready${NC}"
sleep 5
echo

# Step 3: Initialize Database
echo -e "${YELLOW}[3/6] Initializing Database...${NC}"
docker exec -i -e MYSQL_PWD=RouteGate2024! mysql mysql -u root routegate <<'SQLINIT'
CREATE TABLE IF NOT EXISTS airports (
    airport_code VARCHAR(4) PRIMARY KEY,
    airport_name VARCHAR(100) NOT NULL,
    city VARCHAR(100),
    country VARCHAR(100),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    timezone VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    home_airport VARCHAR(4),
    role ENUM('admin', 'staff', 'viewer') DEFAULT 'staff',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (home_airport) REFERENCES airports(airport_code)
);

CREATE TABLE IF NOT EXISTS flights (
    flight_id INT AUTO_INCREMENT PRIMARY KEY,
    flight_number VARCHAR(20) NOT NULL,
    origin_airport VARCHAR(4),
    destination_airport VARCHAR(4),
    departure_date DATE,
    departure_time TIME,
    arrival_date DATE,
    arrival_time TIME,
    status ENUM('scheduled', 'departed', 'arrived', 'cancelled') DEFAULT 'scheduled',
    aircraft_type VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (origin_airport) REFERENCES airports(airport_code),
    FOREIGN KEY (destination_airport) REFERENCES airports(airport_code)
);

INSERT IGNORE INTO airports (airport_code, airport_name, city, country, latitude, longitude, timezone) VALUES
('BNE', 'Brisbane International', 'Brisbane', 'Australia', -27.3842, 153.1175, 'Australia/Brisbane'),
('LAX', 'Los Angeles International', 'Los Angeles', 'USA', 33.9416, -118.4085, 'America/Los_Angeles'),
('JFK', 'John F Kennedy International', 'New York', 'USA', 40.6413, -73.7781, 'America/New_York'),
('LHR', 'London Heathrow', 'London', 'UK', 51.4700, -0.4543, 'Europe/London'),
('DXB', 'Dubai International', 'Dubai', 'UAE', 25.2532, 55.3657, 'Asia/Dubai'),
('SYD', 'Sydney Kingsford Smith', 'Sydney', 'Australia', -33.9461, 151.1772, 'Australia/Sydney'),
('CDG', 'Charles de Gaulle', 'Paris', 'France', 49.0097, 2.5479, 'Europe/Paris'),
('NRT', 'Narita International', 'Tokyo', 'Japan', 35.7720, 140.3929, 'Asia/Tokyo'),
('SIN', 'Singapore Changi', 'Singapore', 'Singapore', 1.3644, 103.9915, 'Asia/Singapore'),
('AMS', 'Amsterdam Schiphol', 'Amsterdam', 'Netherlands', 52.3105, 4.7683, 'Europe/Amsterdam'),
('KUL', 'Kuala Lumpur International', 'Kuala Lumpur', 'Malaysia', 2.7456, 101.7099, 'Asia/Kuala_Lumpur');

INSERT IGNORE INTO users (username, email, password_hash, first_name, last_name, home_airport, role) VALUES
('demo-1234-bne', 'demo@routegate.com', 'd3ad9315b7be5dd53b31a273b3b3aba5defe700808305aa16a3062b76658a791', 'Demo', 'User', 'BNE', 'staff');

INSERT IGNORE INTO flights (flight_number, origin_airport, destination_airport, departure_date, departure_time, arrival_date, arrival_time, status, aircraft_type) VALUES
-- Brisbane (BNE) departures
('QF15', 'BNE', 'LAX', DATE_ADD(CURDATE(), INTERVAL 1 DAY), '09:30:00', DATE_ADD(CURDATE(), INTERVAL 1 DAY), '07:45:00', 'scheduled', 'Boeing 787-9'),
('QF9', 'BNE', 'LHR', DATE_ADD(CURDATE(), INTERVAL 1 DAY), '19:00:00', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '05:30:00', 'scheduled', 'Boeing 787-9'),
('QF19', 'BNE', 'SIN', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '10:15:00', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '16:00:00', 'scheduled', 'Airbus A330-300'),
('VA41', 'BNE', 'AMS', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '21:00:00', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '06:45:00', 'scheduled', 'Boeing 777-300ER'),
('QF51', 'BNE', 'SYD', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '06:00:00', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '07:30:00', 'scheduled', 'Boeing 737-800'),
('MH125', 'BNE', 'KUL', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '22:45:00', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '04:30:00', 'scheduled', 'Airbus A330-300'),
('QF127', 'BNE', 'NRT', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '11:00:00', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '19:45:00', 'scheduled', 'Boeing 787-8'),
('EK434', 'BNE', 'DXB', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '22:00:00', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '04:50:00', 'scheduled', 'Airbus A380-800'),
('QF51', 'BNE', 'SYD', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '07:30:00', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '09:00:00', 'scheduled', 'Boeing 737-800'),
('UA863', 'BNE', 'LAX', DATE_ADD(CURDATE(), INTERVAL 7 DAY), '10:00:00', DATE_ADD(CURDATE(), INTERVAL 7 DAY), '08:15:00', 'scheduled', 'Boeing 787-9'),
('QF19', 'BNE', 'SIN', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '10:15:00', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '16:00:00', 'scheduled', 'Airbus A330-300'),
('AF465', 'BNE', 'CDG', DATE_ADD(CURDATE(), INTERVAL 9 DAY), '20:30:00', DATE_ADD(CURDATE(), INTERVAL 10 DAY), '06:15:00', 'scheduled', 'Boeing 777-300ER'),
('QF127', 'BNE', 'NRT', DATE_ADD(CURDATE(), INTERVAL 10 DAY), '11:00:00', DATE_ADD(CURDATE(), INTERVAL 10 DAY), '19:45:00', 'scheduled', 'Boeing 787-8'),
('MH125', 'BNE', 'KUL', DATE_ADD(CURDATE(), INTERVAL 11 DAY), '22:45:00', DATE_ADD(CURDATE(), INTERVAL 12 DAY), '04:30:00', 'scheduled', 'Airbus A330-300'),
('QF51', 'BNE', 'SYD', DATE_ADD(CURDATE(), INTERVAL 12 DAY), '14:30:00', DATE_ADD(CURDATE(), INTERVAL 12 DAY), '16:00:00', 'scheduled', 'Boeing 737-800'),
('VA41', 'BNE', 'AMS', DATE_ADD(CURDATE(), INTERVAL 13 DAY), '21:00:00', DATE_ADD(CURDATE(), INTERVAL 14 DAY), '06:45:00', 'scheduled', 'Boeing 777-300ER'),

-- Sydney (SYD) departures
('QF11', 'SYD', 'LAX', DATE_ADD(CURDATE(), INTERVAL 1 DAY), '10:45:00', DATE_ADD(CURDATE(), INTERVAL 1 DAY), '08:30:00', 'scheduled', 'Airbus A380-800'),
('QF1', 'SYD', 'LHR', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '18:15:00', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '05:45:00', 'scheduled', 'Airbus A380-800'),
('SQ231', 'SYD', 'SIN', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '09:00:00', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '15:30:00', 'scheduled', 'Airbus A350-900'),
('MH141', 'SYD', 'KUL', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '21:30:00', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '03:15:00', 'scheduled', 'Airbus A330-300'),
('KL809', 'SYD', 'AMS', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '20:00:00', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '06:30:00', 'scheduled', 'Boeing 777-300ER'),
('EK413', 'SYD', 'DXB', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '22:30:00', DATE_ADD(CURDATE(), INTERVAL 7 DAY), '05:20:00', 'scheduled', 'Airbus A380-800'),
('QF25', 'SYD', 'NRT', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '12:30:00', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '20:15:00', 'scheduled', 'Boeing 787-9'),
('UA839', 'SYD', 'LAX', DATE_ADD(CURDATE(), INTERVAL 10 DAY), '11:15:00', DATE_ADD(CURDATE(), INTERVAL 10 DAY), '09:00:00', 'scheduled', 'Boeing 787-9'),

-- Singapore (SIN) departures
('SQ232', 'SIN', 'SYD', DATE_ADD(CURDATE(), INTERVAL 1 DAY), '23:55:00', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '09:30:00', 'scheduled', 'Airbus A350-900'),
('MH604', 'SIN', 'KUL', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '08:30:00', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '09:35:00', 'scheduled', 'Boeing 737-800'),
('SQ322', 'SIN', 'AMS', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '23:40:00', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '06:45:00', 'scheduled', 'Airbus A350-900'),
('QF20', 'SIN', 'BNE', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '18:30:00', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '04:15:00', 'scheduled', 'Airbus A330-300'),
('SQ26', 'SIN', 'JFK', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '23:30:00', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '06:00:00', 'scheduled', 'Airbus A350-900ULR'),
('BA12', 'SIN', 'LHR', DATE_ADD(CURDATE(), INTERVAL 7 DAY), '23:00:00', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '05:55:00', 'scheduled', 'Airbus A380-800'),
('MH604', 'SIN', 'KUL', DATE_ADD(CURDATE(), INTERVAL 9 DAY), '08:30:00', DATE_ADD(CURDATE(), INTERVAL 9 DAY), '09:35:00', 'scheduled', 'Boeing 737-800'),

-- Amsterdam (AMS) departures
('KL835', 'AMS', 'SYD', DATE_ADD(CURDATE(), INTERVAL 1 DAY), '18:00:00', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '19:30:00', 'scheduled', 'Boeing 787-10'),
('KL1023', 'AMS', 'LHR', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '09:15:00', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '09:35:00', 'scheduled', 'Boeing 737-800'),
('VA42', 'AMS', 'BNE', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '19:30:00', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '21:15:00', 'scheduled', 'Boeing 777-300ER'),
('KL875', 'AMS', 'SIN', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '21:00:00', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '16:45:00', 'scheduled', 'Boeing 777-300ER'),
('KL643', 'AMS', 'JFK', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '17:30:00', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '20:15:00', 'scheduled', 'Boeing 787-10'),
('MH17', 'AMS', 'KUL', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '20:15:00', DATE_ADD(CURDATE(), INTERVAL 7 DAY), '15:30:00', 'scheduled', 'Airbus A350-900'),
('KL641', 'AMS', 'LAX', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '15:45:00', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '18:30:00', 'scheduled', 'Boeing 787-10'),
('EK147', 'AMS', 'DXB', DATE_ADD(CURDATE(), INTERVAL 10 DAY), '14:30:00', DATE_ADD(CURDATE(), INTERVAL 10 DAY), '23:45:00', 'scheduled', 'Boeing 777-300ER'),

-- Kuala Lumpur (KUL) departures
('MH126', 'KUL', 'BNE', DATE_ADD(CURDATE(), INTERVAL 1 DAY), '06:00:00', DATE_ADD(CURDATE(), INTERVAL 1 DAY), '16:45:00', 'scheduled', 'Airbus A330-300'),
('MH605', 'KUL', 'SIN', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '11:00:00', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '12:05:00', 'scheduled', 'Boeing 737-800'),
('MH142', 'KUL', 'SYD', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '08:30:00', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '19:15:00', 'scheduled', 'Airbus A330-300'),
('MH18', 'KUL', 'AMS', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '22:30:00', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '06:15:00', 'scheduled', 'Airbus A350-900'),
('MH4', 'KUL', 'LHR', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '21:15:00', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '05:30:00', 'scheduled', 'Airbus A350-900'),
('MH84', 'KUL', 'NRT', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '23:50:00', DATE_ADD(CURDATE(), INTERVAL 7 DAY), '07:35:00', 'scheduled', 'Airbus A330-300'),
('MH605', 'KUL', 'SIN', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '11:00:00', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '12:05:00', 'scheduled', 'Boeing 737-800'),
('MH126', 'KUL', 'BNE', DATE_ADD(CURDATE(), INTERVAL 9 DAY), '06:00:00', DATE_ADD(CURDATE(), INTERVAL 9 DAY), '16:45:00', 'scheduled', 'Airbus A330-300'),
('EK346', 'KUL', 'DXB', DATE_ADD(CURDATE(), INTERVAL 11 DAY), '03:45:00', DATE_ADD(CURDATE(), INTERVAL 11 DAY), '07:00:00', 'scheduled', 'Boeing 777-300ER'),

-- London (LHR) departures
('BA15', 'LHR', 'SYD', DATE_ADD(CURDATE(), INTERVAL 2 DAY), '21:40:00', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '05:25:00', 'scheduled', 'Boeing 787-9'),
('QF10', 'LHR', 'SIN', DATE_ADD(CURDATE(), INTERVAL 4 DAY), '11:00:00', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '07:30:00', 'scheduled', 'Airbus A380-800'),
('BA179', 'LHR', 'AMS', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '07:40:00', DATE_ADD(CURDATE(), INTERVAL 6 DAY), '10:00:00', 'scheduled', 'Airbus A320'),
('BA2158', 'LHR', 'CDG', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '18:30:00', DATE_ADD(CURDATE(), INTERVAL 8 DAY), '20:50:00', 'scheduled', 'Airbus A320'),

-- Los Angeles (LAX) departures
('QF12', 'LAX', 'SYD', DATE_ADD(CURDATE(), INTERVAL 3 DAY), '22:30:00', DATE_ADD(CURDATE(), INTERVAL 5 DAY), '07:00:00', 'scheduled', 'Airbus A380-800'),
('UA840', 'LAX', 'SYD', DATE_ADD(CURDATE(), INTERVAL 7 DAY), '22:00:00', DATE_ADD(CURDATE(), INTERVAL 9 DAY), '06:30:00', 'scheduled', 'Boeing 787-9'),
('QF16', 'LAX', 'BNE', DATE_ADD(CURDATE(), INTERVAL 9 DAY), '21:45:00', DATE_ADD(CURDATE(), INTERVAL 11 DAY), '06:30:00', 'scheduled', 'Boeing 787-9');

SELECT 'Database initialized successfully!' as status;
SQLINIT
echo -e "${GREEN}Database initialized successfully${NC}"
echo

# Step 4: Start Weather Service
echo -e "${YELLOW}[4/6] Starting Weather Service...${NC}"
docker rm -f weather-service 2>/dev/null || true
docker run -d \
    --name weather-service \
    --network routegate-net \
    -p 5001:5001 \
    routegate/weather-service:v1
echo -e "${GREEN}Weather Service started${NC}"
echo

# Step 5: Start API Service
echo -e "${YELLOW}[5/6] Starting API Service...${NC}"
docker rm -f api-service 2>/dev/null || true
docker run -d \
    --name api-service \
    --network routegate-net \
    -p 5000:5000 \
    -e DB_HOST=mysql \
    -e DB_USER=root \
    -e DB_PASSWORD=RouteGate2024! \
    -e DB_NAME=routegate \
    -e WEATHER_SERVICE_URL=http://weather-service:5001 \
    -e PORT=5000 \
    routegate/api-service:v1
echo -e "${GREEN}API Service started${NC}"
echo

# Step 6: Start Frontend
echo -e "${YELLOW}[6/6] Starting Frontend...${NC}"
docker rm -f frontend 2>/dev/null || true
docker run -d \
    --name frontend \
    --network routegate-net \
    -p 80:80 \
    routegate/frontend:v1
echo -e "${GREEN}Frontend started${NC}"
echo

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Display deployment status
echo -e "${BLUE}Container Status:${NC}"
docker ps --filter "network=routegate-net"
echo

echo -e "${BLUE}Access your app:${NC}"
echo "  Frontend: http://localhost"
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
echo "  docker ps                                                    # Check container status"
echo "  docker logs api-service                                      # View API logs"
echo "  docker stop mysql weather-service api-service frontend       # Stop all containers"
echo
