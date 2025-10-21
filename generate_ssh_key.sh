#!/bin/bash

# Variables
KEY_NAME="hcloud_terraform_ssh_key"
KEY_DIR="$(pwd)/ssh-keys"
PRIVATE_KEY_PATH="$KEY_DIR/$KEY_NAME"
PUBLIC_KEY_PATH="$PRIVATE_KEY_PATH.pub"

# Generate SSH key pair without passphrase using ed25519 algorithm
ssh-keygen -t ed25519 -f "$PRIVATE_KEY_PATH" -N "" -C "${KEY_NAME}"

# Output information
echo "SSH key pair generated."
echo "Private key path: $PRIVATE_KEY_PATH"
echo "Public key path: $PUBLIC_KEY_PATH"

# Get public key fingerprint
FINGERPRINT=$(ssh-keygen -E md5 -lf "$PUBLIC_KEY_PATH" | awk '{print $2}' | sed 's/MD5://')
echo "Public key fingerprint (MD5): $FINGERPRINT"


# Instructions for Terraform variables
echo ""
echo "Use the following values in your Terraform configuration:"
echo ""
echo "ssh_private_key_path = \"$PRIVATE_KEY_PATH\""