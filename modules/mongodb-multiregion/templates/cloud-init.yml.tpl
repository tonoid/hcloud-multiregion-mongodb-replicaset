#cloud-config
users:
  - name: mongodb
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${ssh_public_key}

# Disable password authentication and root login
ssh_pwauth: false
disable_root: true

package_update: true
package_upgrade: true

packages:
  - curl
  - gnupg
  - software-properties-common
  - xfsprogs
  - linux-tools-generic
  - linux-tools-common
  # Added for Alloy install process
  - apt-transport-https
  - wget
  # Added for Let's Encrypt TLS
  - certbot
  - python3-certbot
  - nginx

write_files:
  - path: /etc/sysctl.d/mongodb.conf
    content: |
      vm.max_map_count=262144
      
  - path: /etc/ssh/sshd_config
    content: |
      Port 22
      PermitRootLogin no
      PubkeyAuthentication yes
      PasswordAuthentication no
      MaxAuthTries 30
      ChallengeResponseAuthentication no
      UsePAM yes
      X11Forwarding yes
      PrintMotd no
      AcceptEnv LANG LC_*
      Subsystem sftp /usr/lib/openssh/sftp-server
      AllowUsers mongodb

runcmd:
  # Disable UFW firewall (using Hetzner firewall instead)
  - systemctl stop ufw
  - systemctl disable ufw
  
  # Apply sysctl settings
  - sysctl -p /etc/sysctl.d/mongodb.conf
  
  # Install MongoDB
  - curl -fsSL https://pgp.mongodb.com/server-${mongodb_version}.asc | gpg -o /usr/share/keyrings/mongodb-server-${mongodb_version}.gpg --dearmor
  - echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${mongodb_version}.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/${mongodb_version} multiverse" | tee /etc/apt/sources.list.d/mongodb-org-${mongodb_version}.list
  - DEBIAN_FRONTEND=noninteractive apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-org
  # Create MongoDB log directory and set permissions
  - mkdir -p /var/log/mongodb
  - chown -R mongodb:mongodb /var/log/mongodb
  - chmod 755 /var/log/mongodb

%{ if enable_tls ~}
  # --- Configure Let's Encrypt TLS Certificate ---
  # Stop nginx if running (we just need it for certbot)
  - systemctl stop nginx || true
  - systemctl disable nginx || true
  
  # Get Let's Encrypt certificate using standalone mode
  - |
    certbot certonly --standalone --non-interactive --agree-tos \
      ${letsencrypt_email != "" ? "--email ${letsencrypt_email}" : "--register-unsafely-without-email"} \
      ${letsencrypt_staging ? "--staging" : ""} \
      -d ${hostname}
  
  # Create combined PEM file for MongoDB
  - cat /etc/letsencrypt/live/${hostname}/privkey.pem /etc/letsencrypt/live/${hostname}/fullchain.pem > /etc/letsencrypt/live/${hostname}/mongodb.pem
  - chmod 600 /etc/letsencrypt/live/${hostname}/mongodb.pem
  - chown mongodb:mongodb /etc/letsencrypt/live/${hostname}/mongodb.pem
  
  # Make Let's Encrypt directories accessible to MongoDB user
  - chmod 755 /etc/letsencrypt
  - chmod 755 /etc/letsencrypt/live
  - chmod 755 /etc/letsencrypt/archive
  - chmod 755 /etc/letsencrypt/live/${hostname}
  
  # Set up auto-renewal with post-hook to restart MongoDB
  - |
    cat > /etc/letsencrypt/renewal-hooks/post/mongodb-reload.sh << 'EOF'
    #!/bin/bash
    for cert_dir in /etc/letsencrypt/live/*/; do
      if [ -f "$cert_dir/privkey.pem" ] && [ -f "$cert_dir/fullchain.pem" ]; then
        cat "$cert_dir/privkey.pem" "$cert_dir/fullchain.pem" > "$cert_dir/mongodb.pem"
        chmod 600 "$cert_dir/mongodb.pem"
        chown mongodb:mongodb "$cert_dir/mongodb.pem"
      fi
    done
    systemctl restart mongod
    EOF
  - chmod +x /etc/letsencrypt/renewal-hooks/post/mongodb-reload.sh
  
  # Test certbot renewal (dry-run)
  - certbot renew --dry-run || true
%{ endif ~}

%{ if enable_grafana ~}
  # --- Add Grafana Alloy Installation and Configuration ---
  # Add Grafana GPG key and repository
  - mkdir -p /etc/apt/keyrings/
  - wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
  - echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
  
  # Update package list again after adding repo
  - DEBIAN_FRONTEND=noninteractive apt-get update

  # Install Alloy
  - DEBIAN_FRONTEND=noninteractive apt-get install -y alloy

  # Create Alloy configuration directory
  - mkdir -p /etc/alloy
  
  # Write Alloy configuration file
  - |
    cat <<EOF > /etc/alloy/config.alloy
    prometheus.exporter.mongodb "default" {
      // Use localhost as Alloy runs on the same server. Credentials are required.
      // directConnection=true is important when connecting to a specific mongod instance.
      mongodb_uri = "mongodb://${mongo_admin_username}:${mongo_admin_password}@localhost:27017/?directConnection=true"
    }

    prometheus.remote_write "grafana" {
      endpoint {
        url = "${grafana_metrics_url}"
        basic_auth {
          username = "${grafana_metrics_username}"
          password = "${grafana_api_key}"
        }
      }
      external_labels = {
        instance = "${instance_name}",
        job = "integrations/mongodb",
        environment = "${environment}",
      }
    }

    prometheus.scrape "default" {
      targets    = prometheus.exporter.mongodb.default.targets
      forward_to = [prometheus.remote_write.grafana.receiver]
      scrape_interval = "60s" // Adjust scrape interval if needed
    }
    EOF

  # Set permissions for config file
  - chown alloy:alloy /etc/alloy/config.alloy
  - chmod 640 /etc/alloy/config.alloy

  # Enable and start Alloy service
  # Note: Alloy might fail to connect initially if MongoDB or the admin user isn't ready yet.
  # systemd will restart it based on the default service configuration.
  - systemctl enable alloy
  - systemctl start alloy
  # --- End Grafana Alloy ---
%{ endif ~}

