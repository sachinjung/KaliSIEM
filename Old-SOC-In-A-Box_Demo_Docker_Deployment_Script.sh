#!/bin/bash
# SOC-In-A-Box Introduction display
echo "This is an AI Driven SOC-In-A-Box"
echo "All-In-One-Solution for Security Operation Centers"
echo "Powered by AI and Open Source technologies over container based platform"
# Check if the user is root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Please run with sudo."
   exit 1
fi
# Prompt user for required information
read -p "Enter the IP address of the system: " IP_ADDRESS
read -p "Enter a username for the services: " USERNAME
read -sp "Enter a password for the services: " PASSWORD
echo
echo "Starting the SOC stack installation process..."

# Display progress for the user
echo "Updating system packages..."
sudo apt-get update -y && sudo apt-get upgrade -y

echo "Installing Docker and Docker Compose..."
sudo apt-get install -y docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker

# Create a Docker network
echo "Creating a Docker network for SOC components..."
docker network create soc-network

# Start deploying the containers
echo "Pulling and configuring SOC stack containers..."

# 1. Elasticsearch and Kibana (Elastic Stack)
docker pull docker.elastic.co/elasticsearch/elasticsearch:7.17.10
docker pull docker.elastic.co/kibana/kibana:7.17.10

# Elasticsearch Container
echo "Starting Elasticsearch container..."
docker run -d --name elasticsearch --network soc-network \
  -e "discovery.type=single-node" \
  -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
  -e "xpack.security.enabled=true" \
  -e "xpack.security.authc.api_key.enabled=true" \
  -e "ELASTIC_USERNAME=$USERNAME" \
  -e "ELASTIC_PASSWORD=$PASSWORD" \
  -p 9200:9200 \
  docker.elastic.co/elasticsearch/elasticsearch:7.17.10

# Kibana Container
echo "Starting Kibana container..."
docker run -d --name kibana --network soc-network \
  -e "ELASTICSEARCH_HOSTS=http://elasticsearch:9200" \
  -e "ELASTICSEARCH_USERNAME=$USERNAME" \
  -e "ELASTICSEARCH_PASSWORD=$PASSWORD" \
  -p 5601:5601 \
  docker.elastic.co/kibana/kibana:7.17.10

# 2. Logstash
docker pull docker.elastic.co/logstash/logstash:7.17.10
echo "Starting Logstash container..."
docker run -d --name logstash --network soc-network \
  -p 5044:5044 -p 9600:9600 \
  docker.elastic.co/logstash/logstash:7.17.10

# 3. TheHive (Incident Response and SOAR)
docker pull thehiveproject/thehive:4.1.11-1
echo "Starting TheHive container..."
docker run -d --name thehive --network soc-network \
  -e "CORTEX_URL=http://cortex:9000" \
  -e "HIVE_ADMIN_LOGIN=$USERNAME" \
  -e "HIVE_ADMIN_PASSWORD=$PASSWORD" \
  -p 9001:9001 \
  thehiveproject/thehive:4.1.11-1

# 4. Cortex
docker pull thehiveproject/cortex:3.1.1-1
echo "Starting Cortex container..."
docker run -d --name cortex --network soc-network \
  -e "CORTEX_ADMIN_LOGIN=$USERNAME" \
  -e "CORTEX_ADMIN_PASSWORD=$PASSWORD" \
  -p 9000:9000 \
  thehiveproject/cortex:3.1.1-1

# 5. MISP
docker pull harvarditsecurity/misp
echo "Starting MISP container..."
docker run -d --name misp --network soc-network \
  -e "MYSQL_USER=$USERNAME" \
  -e "MYSQL_PASSWORD=$PASSWORD" \
  -e "MISP_BASEURL=http://$IP_ADDRESS:8080" \
  -p 8080:80 \
  harvarditsecurity/misp

# 6. Infection Monkey
docker pull guardicore/monkey
echo "Starting Infection Monkey container..."
docker run -d --name infection-monkey --network soc-network \
  -p 5000:5000 \
  guardicore/monkey

# 7. OpenVAS
docker pull mikesplain/openvas
echo "Starting OpenVAS container..."
docker run -d --name openvas --network soc-network \
  -e "PUBLIC_HOSTNAME=$IP_ADDRESS" \
  -p 443:443 \
  mikesplain/openvas

# 8. Cuckoo Sandbox
docker pull blacktop/cuckoo
echo "Starting Cuckoo Sandbox container..."
docker run -d --name cuckoo --network soc-network \
  -p 8090:8090 \
  blacktop/cuckoo

# 9. Elastic Agent
docker pull docker.elastic.co/beats/elastic-agent:7.17.10
echo "Starting Elastic Agent container..."
docker run -d --name elastic-agent --network soc-network \
  -e "FLEET_ENROLL=1" \
  -e "FLEET_URL=http://kibana:5601" \
  -p 8200:8200 \
  docker.elastic.co/beats/elastic-agent:7.17.10

# Check the status of all containers
echo "Verifying the installation and container status..."
docker ps

# Display completion message with access URLs
echo -e "\nSOC Stack installation completed successfully!"
echo -e "You can access each service using the following URLs:"
echo -e "Elasticsearch: http://$IP_ADDRESS:9200"
echo -e "Kibana: http://$IP_ADDRESS:5601"
echo -e "TheHive: http://$IP_ADDRESS:9001"
echo -e "Cortex: http://$IP_ADDRESS:9000"
echo -e "MISP: http://$IP_ADDRESS:8080"
echo -e "Infection Monkey: http://$IP_ADDRESS:5000"
echo -e "OpenVAS: https://$IP_ADDRESS"
echo -e "Cuckoo Sandbox: http://$IP_ADDRESS:8090"
echo -e "\nLog in with username: $USERNAME and the password you provided.\n"