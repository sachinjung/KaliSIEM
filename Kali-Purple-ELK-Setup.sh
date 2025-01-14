#!/bin/bash

# Banner Function
function display_banner() {
  clear
  echo "############################################################"
  echo "#                                                          #"
  echo "#              ELK Security Stack Installation             #"
  echo "#               Prepared by Sachin Jung Karki              #"
  echo "############################################################"
  echo
}

# Display Banner
trap display_banner DEBUG

display_banner

# Prompt user for IP address and elastic user password
read -p "Enter the IP address for SIEM (e.g., 192.168.253.5): " SIEM_IP
read -s -p "Enter password for elastic superuser: " ELASTIC_PASSWORD
echo

# Save details to a file for reference
OUTPUT_FILE="/var/log/kali-purple-siem-setup.log"
echo "Saving setup details to $OUTPUT_FILE"

# Update /etc/hosts
echo "Executing: Update /etc/hosts"
if ! grep -q "$SIEM_IP kali-purple.kali.purple" /etc/hosts; then
  echo "$SIEM_IP kali-purple.kali.purple" | sudo tee -a /etc/hosts
fi

# Install dependencies
echo "Executing: Install dependencies"
sudo apt-get update
sudo apt-get install -y curl gpg
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/elastic-archive-keyring.gpg
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

# Install Elasticsearch
echo "Executing: Install Elasticsearch"
sudo bash -c "export HOSTNAME=kali-purple.kali.purple; apt-get install elasticsearch -y"

# Set elastic superuser password
echo "Executing: Set elastic superuser password"
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -p "$ELASTIC_PASSWORD" > /tmp/elastic-password-reset.log

# Convert to single-node setup
echo "Executing: Convert to single-node setup"
sudo sed -e '/cluster.initial_master_nodes/ s/^#*/#/' -i /etc/elasticsearch/elasticsearch.yml
echo "discovery.type: single-node" | sudo tee -a /etc/elasticsearch/elasticsearch.yml

# Disable HTTPS in Elasticsearch
echo "Executing: Disable HTTPS in Elasticsearch"
sudo sed -i '/xpack.security.http.ssl.enabled/d' /etc/elasticsearch/elasticsearch.yml
sudo sed -i '/xpack.security.http.ssl.keystore.path/d' /etc/elasticsearch/elasticsearch.yml
sudo sed -i '/xpack.security.http.ssl.keystore.password/d' /etc/elasticsearch/elasticsearch.yml

# Install Kibana
echo "Executing: Install Kibana"
sudo apt-get install -y kibana
KIBANA_KEYS=$(sudo /usr/share/kibana/bin/kibana-encryption-keys generate -q)

# Configure Kibana
echo "Executing: Configure Kibana"
echo "server.host: \"kali-purple.kali.purple\"" | sudo tee -a /etc/kibana/kibana.yml
echo "elasticsearch.hosts: [\"http://kali-purple.kali.purple:9200\"]" | sudo tee -a /etc/kibana/kibana.yml

# Enroll Kibana
echo "Executing: Enroll Kibana"
ENROLLMENT_TOKEN=$(sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana)
KIBANA_VERIFICATION_CODE=$(sudo /usr/share/kibana/bin/kibana-verification-code)

# Enable Elasticsearch and Kibana services
echo "Executing: Enable Elasticsearch and Kibana services"
sudo systemctl enable elasticsearch kibana --now

# Install Elastic Agent and Fleet Server
echo "Executing: Install Elastic Agent and Fleet Server"
sudo apt-get install -y elastic-agent
sudo systemctl enable elastic-agent

# Configure Fleet Server
echo "Executing: Configure Fleet Server"
sudo /usr/share/elastic-agent/bin/elastic-agent install \
  --fleet-server-es=http://$SIEM_IP:9200 \
  --fleet-server-service-token="$ENROLLMENT_TOKEN" \
  --fleet-server-policy=default \
  --fleet-server-host=http://$SIEM_IP:8220

# Save details to log file
{
  echo "Elastic superuser password: $ELASTIC_PASSWORD"
  echo "Elasticsearch enrollment token: $ENROLLMENT_TOKEN"
  echo "Kibana verification code: $KIBANA_VERIFICATION_CODE"
  echo "Kibana encryption keys:"
  echo "$KIBANA_KEYS"
  echo "Access Kibana: http://$SIEM_IP:5601"
  echo "Fleet Server URL: http://$SIEM_IP:8220"
} | sudo tee "$OUTPUT_FILE"

# Display saved details
echo "Setup complete! Details saved to $OUTPUT_FILE."
cat "$OUTPUT_FILE"

# Cleanup
echo "Cleaning up temporary files"
sudo rm -f /tmp/elastic-password-reset.log
