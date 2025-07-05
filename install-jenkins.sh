#!/bin/bash
# This script installs Jenkins LTS and configures Nginx as a reverse proxy.
set -euo pipefail

# Install necessary packages for Jenkins
echo "Updating apt package list..."
sudo apt-get update
echo "Installing OpenJDK 17, ca-certificates, curl, and gnupg..."
sudo apt-get install -y openjdk-17-jdk # Jenkins requires Java 11 or 17
sudo apt-get install -y ca-certificates curl gnupg

# Add Jenkins GPG key
echo "Adding Jenkins GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /etc/apt/keyrings/jenkins-keyring.asc > /dev/null

# Add Jenkins APT repository
echo "Adding Jenkins APT repository..."
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" \
  "https://pkg.jenkins.io/debian-stable binary/" | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

# Update apt cache and install Jenkins
echo "Updating apt cache and installing Jenkins..."
sudo apt-get update
sudo apt-get install -y jenkins

# Reload systemd daemon to recognize new Jenkins service unit file
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload
# Give systemd a moment to process (optional, but can help with timing)
sleep 5

# Start and enable Jenkins service
echo "Starting and enabling Jenkins service..."
sudo systemctl start jenkins
sudo systemctl enable jenkins

# --- START: Install and Configure Nginx as a Reverse Proxy ---
echo "Installing Nginx..."
sudo apt-get install -y nginx

echo "Configuring Nginx for Jenkins reverse proxy..."
# Create Nginx configuration for Jenkins
# Using <<'EOF' to prevent shell variable expansion inside the heredoc
# Terraform will replace ${var.domain_name} before the script runs on the VM.
sudo tee /etc/nginx/sites-available/jenkins <<EOF
server {
    listen 80;
    server_name ${var.domain_name}; # This will be replaced by Terraform

    location / {
        proxy_pass http://127.0.0.1:8080; # Jenkins default port
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 150;
        proxy_send_timeout 100;
        proxy_read_timeout 100;
        proxy_buffers 16 64k;
        proxy_buffer_size 128k;
    }
}
EOF

# Enable the Nginx site and remove default
echo "Enabling Nginx site and removing default..."
sudo ln -sf /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
echo "Testing Nginx configuration..."
sudo nginx -t && echo "Nginx config test passed." || echo "Nginx config test failed!"

# Restart Nginx service
echo "Restarting and enabling Nginx service..."
sudo systemctl restart nginx
sudo systemctl enable nginx
echo "Nginx configured and started as reverse proxy for Jenkins."
# --- END: Install and Configure Nginx as a Reverse Proxy ---

# --- START: Configure Jenkins URL by modifying XML file ---
# Wait for Jenkins to be fully up and running before attempting configuration
echo "Waiting for Jenkins to be fully available on port 8080..."
until curl -s http://127.0.0.1:8080/login > /dev/null; do
  sleep 5
done
echo "Jenkins is available. Configuring Jenkins URL in XML..."

JENKINS_HOME="/var/lib/jenkins"
JENKINS_LOCATION_CONFIG="${JENKINS_HOME}/jenkins.model.JenkinsLocationConfiguration.xml"

# Ensure the directory exists and has correct permissions
sudo mkdir -p "$JENKINS_HOME"
sudo chown jenkins:jenkins "$JENKINS_HOME"
sudo chmod 755 "$JENKINS_HOME"

# Create a basic config file if it doesn't exist (initial setup might create it later)
if [ ! -f "$JENKINS_LOCATION_CONFIG" ]; then
  echo "Creating initial Jenkins location configuration file..."
  sudo tee "$JENKINS_LOCATION_CONFIG" <<EOF_XML
<?xml version='1.1' encoding='UTF-8'?>
<jenkins.model.JenkinsLocationConfiguration>
  <jenkinsUrl>http://localhost:8080/</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>
EOF_XML
  sudo chown jenkins:jenkins "$JENKINS_LOCATION_CONFIG"
  sudo chmod 644 "$JENKINS_LOCATION_CONFIG"
fi

# Use xmlstarlet to update the jenkinsUrl. Install it first if not present.
echo "Installing xmlstarlet for XML modification..."
sudo apt-get install -y xmlstarlet

echo "Modifying Jenkins URL in ${JENKINS_LOCATION_CONFIG} to https://${DOMAIN_NAME}/"
sudo xmlstarlet ed --inplace -u "/jenkins.model.JenkinsLocationConfiguration/jenkinsUrl" -v "https://${DOMAIN_NAME}/" "$JENKINS_LOCATION_CONFIG"

# Verify the change (optional)
echo "Verifying Jenkins URL in XML:"
sudo cat "$JENKINS_LOCATION_CONFIG"

# Restart Jenkins service to apply the URL change
echo "Restarting Jenkins service to apply URL change..."
sudo systemctl restart jenkins

echo "Jenkins URL configuration completed."
# --- END: Configure Jenkins URL by modifying XML file ---

echo "Jenkins LTS installation and setup script completed."
