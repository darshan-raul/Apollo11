#!/bin/bash

# prep.sh - Apollo 11 Environment Setup Script (Native Linux Binaries)

set -e

echo "🚀 Initiating Apollo 11 Launch Preparation Sequence..."

# 1. Install kubectl
echo "🔧 Installing kubectl binary..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
echo "✅ kubectl installed successfully."

# 2. Install k3d
echo "🔧 Installing k3d via official script..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
echo "✅ k3d installed successfully."

# 3. Install docker
if ! command -v docker &> /dev/null; then
    echo "� Installing docker via convenience script..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    sudo systemctl start docker
    sudo systemctl enable docker
    # Post-install: add user to docker group (optional but recommended for local dev)
    sudo usermod -aG docker $USER
    newgrp docker
    echo "✅ docker installed successfully. Please logout and login again for the changes to take effect."
else
    echo "✅ docker is already installed."
fi

echo "----------------------------------------------------------------"
echo "🎉 Preparation Complete!"
echo "----------------------------------------------------------------"
echo "The tools (docker, kubectl, k3d) have been installed natively."
echo "You can now run them directly from your shell."
echo ""
echo "Verify the installation by running:"
echo "  kubectl version --client"
echo "  k3d version"
echo "  docker version"
echo "----------------------------------------------------------------"
