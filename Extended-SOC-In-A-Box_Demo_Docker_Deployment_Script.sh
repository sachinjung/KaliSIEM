#!/bin/bash
# SOC-In-A-Box Introduction display
echo "This is an AI Driven SOC-In-A-Box"
echo "All-In-One-Solution for Security Operation Centers"
echo "Powered by AI and Open Source technologies over a container-based platform"

# Check if the user is root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Please run with sudo."
   exit 1
fi

# Function to check command success
check_success() {
  if [ $? -ne 0 ]; then
    echo "Error: $1 failed. Exiting."
    exit 1
  fi
}

# Function to pull Docker image if not already present
pull_if_not_exists() {
  IMAGE_NAME=$1
  IMAGE_TAG=$2
  if ! docker image inspect "$IMAGE_NAME:$IMAGE_TAG" > /dev/null 2>&1; then
    echo "Image $IMAGE_NAME:$IMAGE_TAG not found locally. Pulling..."
    docker pull "$IMAGE_NAME:$IMAGE_TAG"
    check_success "$IMAGE_NAME image pull"
  else
    echo "Image $IMAGE_NAME:$IMAGE_TAG already exists. Skipping pull."
  fi
}

# Function to check if a container exists and handle reinstall/update options
manage_container() {
  CONTAINER_NAME=$1
  IMAGE_NAME=$2
  IMAGE_TAG=$3
  CONFIG_COMMAND=$4

  if docker container inspect "$CONTAINER_NAME" > /dev/null 2>&1; then
    echo "Container $CONTAINER_NAME already exists."
    read -p "Do you want to (u)pdate, (r)einstall, or (s)kip this container? [u/r/s]: " OPTION
    case $OPTION in
      u|U)
        echo "Stopping and removing the container to update..."
        docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME"
        pull_if_not_exists "$IMAGE_NAME" "$IMAGE_TAG"
        eval "$CONFIG_COMMAND"
        check_success "$CONTAINER_NAME update"
        ;;
      r|R)
        echo "Removing container and reinstalling..."
        docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME"
        pull_if_not_exists "$IMAGE_NAME" "$IMAGE_TAG"
        eval "$CONFIG_COMMAND"
        check_success "$CONTAINER_NAME reinstall"
        ;;
      *)
        echo "Skipping $CONTAINER_NAME."
        ;;
    esac
  else
    echo "Container $CONTAINER_NAME does not exist. Setting up..."
    pull_if_not_exists "$IMAGE_NAME" "$IMAGE_TAG"
    eval "$CONFIG_COMMAND"
    check_success "$CONTAINER_NAME setup"
  fi
}

# Prompt user for required information
read -p "Enter the IP address of the system: " IP_ADDRESS
read -p "Enter a username for the services: " USERNAME
read -sp "Enter a password for the services: " PASSWORD
echo
echo "Starting the SOC stack installation process..."

# Display progress for the user
echo "Updating system packages..."
sudo apt-get update -y && sudo apt-get upgrade -y
check_success "System package update and upgrade"

echo "Installing Docker and Docker Compose..."
sudo apt-get install -y docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker
check_success "Docker service start and enable"

# Create a Docker network, if not already created
if ! docker network inspect soc-network >/dev/null 2>&1; then
  echo "Creating a Docker network for SOC components..."
  docker network create soc-network
  check_success "Docker network creation"
else
  echo "Docker network 'soc-network' already exists. Skipping creation."
fi

# Elasticsearch Java options for production (recommended: 2GB minimum heap size)
ES_JAVA_OPTS="-Xms2g -Xmx2g"  # Set to 2GB. Adjust based on available system memory.

# Start deploying the containers
echo "Pulling and configuring SOC stack containers..."

# 1. Elasticsearch
manage_container "elasticsearch" "docker.elastic.co/elasticsearch/elasticsearch" "7.17.10" \
  "docker run -d --restart unless-stopped --name elasticsearch --network soc-network \
  -v /var/lib/docker_volumes/elasticsearch:/usr/share/elasticsearch/data \
  -e 'discovery.type=single-node' \
  -e 'ES_JAVA_OPTS=-Xms2g -Xmx2g' \
  -e 'xpack.security.enabled=true' \
  -e 'xpack.security.authc.api_key.enabled=true' \
  -e 'ELASTIC_USERNAME=$USERNAME' \
  -e 'ELASTIC_PASSWORD=$PASSWORD' \
  -p 9200:9200 docker.elastic.co/elasticsearch/elasticsearch:7.17.10"

# 2. Kibana
manage_container "kibana" "docker.elastic.co/kibana/kibana" "7.17.10" \
  "docker run -d --restart unless-stopped --name kibana --network soc-network \
  -v /var/lib/docker_volumes/kibana:/usr/share/kibana/data \
  -e 'ELASTICSEARCH_HOSTS=http://elasticsearch:9200' \
  -e 'ELASTICSEARCH_USERNAME=$USERNAME' \
  -e 'ELASTICSEARCH_PASSWORD=$PASSWORD' \
  -p 5601:5601 docker.elastic.co/kibana/kibana:7.17.10"

# 3. Logstash
manage_container "logstash" "docker.elastic.co/logstash/logstash" "7.17.10" \
  "docker run -d --restart unless-stopped --name logstash --network soc-network \
  -v /var/lib/docker_volumes/logstash:/usr/share/logstash/data \
  -p 5044:5044 -p 9600:9600 docker.elastic.co/logstash/logstash:7.17.10"

# 4. TheHive
manage_container "thehive" "thehiveproject/thehive" "4.1.11-1" \
  "docker run -d --restart unless-stopped --name thehive --network soc-network \
  -e 'CORTEX_URL=http://cortex:9000' \
  -e 'HIVE_ADMIN_LOGIN=$USERNAME' \
  -e 'HIVE_ADMIN_PASSWORD=$PASSWORD' \
  -p 9001:9001 thehiveproject/thehive:4.1.11-1"

# 5. Cortex
manage_container "cortex" "thehiveproject/cortex" "3.1.1-1" \
  "docker run -d --restart unless-stopped --name cortex --network soc-network \
  -e 'CORTEX_ADMIN_LOGIN=$USERNAME' \
  -e 'CORTEX_ADMIN_PASSWORD=$PASSWORD' \
  -p 9000:9000 thehiveproject/cortex:3.1.1-1"

# 6. MISP
manage_container "misp" "harvarditsecurity/misp" "latest" \
  "docker run -d --restart unless-stopped --name misp --network soc-network \
  -e 'MYSQL_USER=$USERNAME' \
  -e 'MYSQL_PASSWORD=$PASSWORD' \
  -e 'MISP_BASEURL=http://$IP_ADDRESS:8080' \
  -p 8080:80 harvarditsecurity/misp"

# 7. Infection Monkey
manage_container "infection-monkey" "guardicore/monkey" "latest" \
  "docker run -d --restart unless-stopped --name infection-monkey --network soc-network \
  -p 5000:5000 guardicore/monkey"

# 8. OpenVAS
manage_container "openvas" "mikesplain/openvas" "latest" \
  "docker run -d --restart unless-stopped --name openvas --network soc-network \
  -e 'PUBLIC_HOSTNAME=$IP_ADDRESS' -p 443:443 mikesplain/openvas"

# 9. Cuckoo Sandbox
manage_container "cuckoo" "blacktop/cuckoo" "latest" \
  "docker run -d --restart unless-stopped --name cuckoo --network soc-network \
  -p 8090:8090 blacktop/cuckoo"

# 10. Elastic Agent
manage_container "elastic-agent" "docker.elastic.co/beats/elastic-agent" "7.17.10" \
  "docker run -d --restart unless-stopped --name elastic-agent --network soc-network \
  -e 'FLEET_ENROLL=1' \
  -e 'FLEET_URL=http://kibana:5601' \
  -p 8200:8200 docker.elastic.co/beats/elastic-agent:7.17.10"

# Check the status of all containers
echo "Verifying the installation and container status..."
for service in elasticsearch kibana logstash thehive cortex misp infection-monkey openvas cuckoo elastic-agent; do
  if [[ $(docker inspect -f '{{.State.Running}}' $service) != "true" ]]; then
    echo "Warning: $service container did not start as expected."
  fi
done
docker ps

# Save credentials and access detail in a file
echo "Saving service access details..."
{
  echo "You can access each service using the following URLs:"
  echo "Elasticsearch: http://$IP_ADDRESS:9200"
  echo "Kibana: http://$IP_ADDRESS:5601"
  echo "TheHive: http://$IP_ADDRESS:9001"
  echo "Cortex: http://$IP_ADDRESS:9000"
  echo "MISP: http://$IP_ADDRESS:8080"
  echo "Infection Monkey: http://$IP_ADDRESS:5000"
  echo "OpenVAS: https://$IP_ADDRESS"
  echo "Cuckoo Sandbox: http://$IP_ADDRESS:8090"
  echo "Log in with username: $USERNAME and the $PASSWORD you provided."
} > SOC-Box-Credentials.txt
check_success "Credential file save"

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
echo -e "Log in with username: $USERNAME and the password you provided."
echo -e "\nAccess URLs and credentials are saved in SOC-Box-Credentials.txt on home path.\n"