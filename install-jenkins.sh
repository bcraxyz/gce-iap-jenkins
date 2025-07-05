#!/bin/bash
set -euo pipefail

# Install Java and Jenkins (keep your existing installation code)
echo "Updating apt package list..."
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk ca-certificates curl gnupg

# Add Jenkins GPG key and repository (keep existing)
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /etc/apt/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" \
  "https://pkg.jenkins.io/debian-stable binary/" | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update
sudo apt-get install -y jenkins

# Configure Jenkins to run on port 80
echo "Configuring Jenkins to run on port 80..."
sudo sed -i 's/HTTP_PORT=8080/HTTP_PORT=80/' /etc/default/jenkins

# Start Jenkins
sudo systemctl daemon-reload
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Wait for Jenkins to be available and configure URL
echo "Waiting for Jenkins to be available..."
until curl -s http://127.0.0.1:80/login > /dev/null; do
  sleep 5
done

# Configure Jenkins URL (update for port 80)
JENKINS_HOME="/var/lib/jenkins"
JENKINS_LOCATION_CONFIG="${JENKINS_HOME}/jenkins.model.JenkinsLocationConfiguration.xml"

sudo mkdir -p "$JENKINS_HOME"
sudo chown jenkins:jenkins "$JENKINS_HOME"

if [ ! -f "$JENKINS_LOCATION_CONFIG" ]; then
  sudo tee "$JENKINS_LOCATION_CONFIG" <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<jenkins.model.JenkinsLocationConfiguration>
  <jenkinsUrl>https://${domain_name}/</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>
EOF
  sudo chown jenkins:jenkins "$JENKINS_LOCATION_CONFIG"
fi

echo "Jenkins installation completed and configured for port 80."
