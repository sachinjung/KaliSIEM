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
OUTPUT_FILE="/var/log/Kali-Purple-ELK-Endpoint-Fleet-Setup.log"
echo "Saving setup details to $OUTPUT_FILE"

# Update /etc/hosts
echo "Executing: Update /etc/hosts"
if ! grep -q "$SIEM_IP kali-purple.kali.purple" /etc/hosts; then
  echo "$SIEM_IP kali-purple.kali.purple" | sudo tee -a /etc/hosts
fi

# Install dependencies
echo "Executing: Install dependencies"
sudo apt-get update
sudo apt-get install -y curl
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/elastic-archive-keyring.gpg
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-8.x.list

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

# Install Kibana
echo "Executing: Install Kibana"
sudo apt-get install -y kibana
KIBANA_KEYS=$(sudo /usr/share/kibana/bin/kibana-encryption-keys generate -q)

# Configure Kibana
echo "Executing: Configure Kibana"
echo "server.host: \"kali-purple.kali.purple\"" | sudo tee -a /etc/kibana/kibana.yml
sudo systemctl enable elasticsearch kibana --now

# Enroll Kibana
echo "Executing: Enroll Kibana"
ENROLLMENT_TOKEN=$(sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana)
KIBANA_VERIFICATION_CODE=$(sudo /usr/share/kibana/bin/kibana-verification-code)

# Enable HTTPS for Kibana
echo "Executing: Enable HTTPS for Kibana"
sudo /usr/share/elasticsearch/bin/elasticsearch-certutil ca
sudo /usr/share/elasticsearch/bin/elasticsearch-certutil cert \
  --ca elastic-stack-ca.p12 \
  --dns kali-purple.kali.purple,elastic.kali.purple,kali-purple \
  --out kibana-server.p12

sudo openssl pkcs12 -in kibana-server.p12 -out /etc/kibana/kibana-server.crt -clcerts -nokeys
sudo openssl pkcs12 -in kibana-server.p12 -out /etc/kibana/kibana-server.key -nocerts -nodes
sudo chown root:kibana /etc/kibana/kibana-server.key /etc/kibana/kibana-server.crt
sudo chmod 660 /etc/kibana/kibana-server.key /etc/kibana/kibana-server.crt
echo "server.ssl.enabled: true" | sudo tee -a /etc/kibana/kibana.yml
echo "server.ssl.certificate: /etc/kibana/kibana-server.crt" | sudo tee -a /etc/kibana/kibana.yml
echo "server.ssl.key: /etc/kibana/kibana-server.key" | sudo tee -a /etc/kibana/kibana.yml
echo "server.publicBaseUrl: \"https://kali-purple.kali.purple:5601\"" | sudo tee -a /etc/kibana/kibana.yml

# Install Elastic Agent and Fleet Server
echo "Executing: Install Elastic Agent and Fleet Server"
sudo apt-get install -y elastic-agent
sudo systemctl enable elastic-agent --now

# Enroll Elastic Agent in Fleet
echo "Executing: Enroll Elastic Agent in Fleet"
FLEET_ENROLLMENT_TOKEN=$(sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s fleet)
sudo elastic-agent enroll --url=https://kali-purple.kali.purple:8220 --enrollment-token=$FLEET_ENROLLMENT_TOKEN

# Save details to log file
{
  echo "Elastic superuser password: $ELASTIC_PASSWORD"
  echo "Elasticsearch enrollment token: $ENROLLMENT_TOKEN"
  echo "Kibana verification code: $KIBANA_VERIFICATION_CODE"
  echo "Kibana encryption keys:"
  echo "$KIBANA_KEYS"
  echo "Fleet enrollment token: $FLEET_ENROLLMENT_TOKEN"
  echo "Certificate file path for Elasticsearch: /usr/share/elasticsearch/elastic-stack-ca.p12"
  echo "Certificate file path for Kibana: /etc/kibana/kibana-server.p12"
  echo "Access Elasticsearch: http://$SIEM_IP:9200 or https://$SIEM_IP:9200"
  echo "Access Kibana: http://$SIEM_IP:5601 or https://$SIEM_IP:5601"
} | sudo tee "$OUTPUT_FILE"

# Display saved details
echo "Setup complete! Details saved to $OUTPUT_FILE."
sudo mousepad "$OUTPUT_FILE" &
