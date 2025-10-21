terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.54.0"
    }
  }
  required_version = ">= 1.3.5"
}

# Flatten regions into individual nodes

locals {
  # Sort regions by priority (descending) using negative values for ascending sort
  # This ensures high-priority regions (like US with priority 1) come first
  region_priorities = {
    for key, config in var.regions :
    key => -config.priority  # Negative so higher priority sorts first
  }
  
  region_keys_sorted_by_priority = [
    for item in sort([
      for key in keys(var.regions) :
      "${format("%010.5f", local.region_priorities[key])}|${key}"  # Use pipe separator
    ]) :
    split("|", item)[1]  # Extract the region key after pipe
  ]
  
  # Calculate global index offsets for each region based on priority order
  region_keys = local.region_keys_sorted_by_priority
  region_offsets = {
    for idx, region_key in local.region_keys :
    region_key => idx == 0 ? 0 : sum([for i in range(idx) : var.regions[local.region_keys[i]].instance_count])
  }
  
  # Create a map of nodes with their region and priority
  mongodb_nodes = merge([
    for region_key, region_config in var.regions : {
      for i in range(region_config.instance_count) :
      "${var.cluster_name}-${region_key}-${i + 1}" => {
        region_key     = region_key
        location       = region_config.location
        priority       = region_config.priority
        server_type    = region_config.server_type
        index          = i
        global_index   = local.region_offsets[region_key] + i
      }
    }
  ]...)
  
  # Sort nodes by global_index (which respects region priority order)
  # This ensures high-priority regions come first
  sorted_node_keys = [
    for idx in range(length(keys(local.mongodb_nodes))) :
    [for key, node in local.mongodb_nodes : key if node.global_index == idx][0]
  ]
  
  # Create a list of all IPs in order
  mongodb_ips = [for key in local.sorted_node_keys : hcloud_server.mongodb[key].ipv4_address]
}

# Create MongoDB servers across regions
resource "hcloud_server" "mongodb" {
  for_each = local.mongodb_nodes

  lifecycle {
    # prevent_destroy = true
    ignore_changes = all
  }

  name        = each.key
  location    = each.value.location
  server_type = each.value.server_type
  image       = "ubuntu-24.04"
  ssh_keys    = [var.ssh_key_id]
  labels      = { for tag in var.tags : tag => "" }
  backups     = var.enable_backups

  # No private network configuration for multi-region

  user_data = templatefile("${path.module}/templates/cloud-init.yml.tpl", {
    ssh_public_key           = var.ssh_public_key
    mongodb_version          = var.mongodb_version
    replica_set_name         = var.replica_set_name
    mongo_admin_username     = var.mongo_admin_username
    mongo_admin_password     = var.mongo_admin_password
    enable_grafana           = var.enable_grafana
    grafana_metrics_url      = var.grafana_metrics_url
    grafana_metrics_username = var.grafana_metrics_username
    grafana_api_key          = var.grafana_api_key
    environment              = var.environment
    instance_name            = each.key
    enable_tls               = var.enable_tls
    letsencrypt_email        = var.letsencrypt_email
    letsencrypt_staging      = var.letsencrypt_staging
    hostname                 = "${var.domain_prefix}${each.key}.${var.dns_domain}"
  })
}

# Create keyfile on first node and distribute to others
resource "null_resource" "mongodb_keyfile" {
  depends_on = [
    hcloud_server.mongodb
  ]

  connection {
    type        = "ssh"
    user        = "mongodb"
    private_key = file(var.ssh_private_key_path)
    host        = hcloud_server.mongodb[local.sorted_node_keys[0]].ipv4_address
    agent       = false
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      # Create keyfile on first node
      "echo 'Creating keyfile...'",
      "sudo mkdir -p /etc/mongodb",
      "sudo chown mongodb:mongodb /etc/mongodb",
      "openssl rand -base64 756 | sudo tee /etc/mongodb/mongodb-keyfile > /dev/null",
      "sudo chown mongodb:mongodb /etc/mongodb/mongodb-keyfile",
      "sudo chmod 400 /etc/mongodb/mongodb-keyfile"
    ]
  }

  # Copy keyfile from first node to local
  provisioner "local-exec" {
    command = "scp -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} mongodb@${hcloud_server.mongodb[local.sorted_node_keys[0]].ipv4_address}:/etc/mongodb/mongodb-keyfile /tmp/mongodb-keyfile-${var.cluster_name}"
  }

  # Distribute keyfile to all other nodes (explicitly for each node)
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ${join("\n      ", [for key in slice(local.sorted_node_keys, 1, length(local.sorted_node_keys)) : 
        <<-COPY
echo "Distributing keyfile to ${key} at ${hcloud_server.mongodb[key].ipv4_address}..."
echo "Waiting for SSH to be ready on ${key}..."
for i in {1..60}; do
  if ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${var.ssh_private_key_path} mongodb@${hcloud_server.mongodb[key].ipv4_address} echo "SSH ready" 2>/dev/null; then
    echo "SSH is ready on ${key}"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "Timeout waiting for SSH on ${key}"
    exit 1
  fi
  echo "Waiting for SSH on ${key} (attempt $i/60)..."
  sleep 5
done
scp -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o ConnectTimeout=30 -i ${var.ssh_private_key_path} /tmp/mongodb-keyfile-${var.cluster_name} mongodb@${hcloud_server.mongodb[key].ipv4_address}:/tmp/mongodb-keyfile || { echo "Failed to copy keyfile to ${key}"; exit 1; }
ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o ConnectTimeout=30 -i ${var.ssh_private_key_path} mongodb@${hcloud_server.mongodb[key].ipv4_address} 'sudo sh -c "mkdir -p /etc/mongodb && chown mongodb:mongodb /etc/mongodb && mv /tmp/mongodb-keyfile /etc/mongodb/mongodb-keyfile && chown mongodb:mongodb /etc/mongodb/mongodb-keyfile && chmod 400 /etc/mongodb/mongodb-keyfile"' || { echo "Failed to setup keyfile on ${key}"; exit 1; }
echo "Successfully distributed keyfile to ${key}"
COPY
      ])}
      rm -f /tmp/mongodb-keyfile-${var.cluster_name}
      echo "Keyfile distribution complete for all nodes!"
    EOT
  }
}

# Initialize MongoDB on all nodes
resource "null_resource" "mongodb_init" {
  for_each = local.mongodb_nodes
  
  depends_on = [
    null_resource.mongodb_keyfile
  ]

  triggers = {
    server_id = hcloud_server.mongodb[each.key].id
  }

  connection {
    type        = "ssh"
    user        = "mongodb"
    private_key = file(var.ssh_private_key_path)
    host        = hcloud_server.mongodb[each.key].ipv4_address
    agent       = false
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to complete
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      
      # Wait for MongoDB to be installed
      "echo 'Waiting for MongoDB installation to complete...'",
      "until systemctl list-unit-files | grep -q mongod.service; do",
      "  echo 'MongoDB not yet installed, waiting...'",
      "  sleep 5",
      "done",
      "echo 'MongoDB installation complete!'",
      
      # Configure system settings
      "echo 'Configuring system settings...'",
      "echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl -p",
      
      # Configure memory allocator settings
      "echo 'Configuring memory allocator settings...'",
      "echo 0 | sudo tee /proc/sys/kernel/numa_balancing",
      "echo 'kernel.numa_balancing = 0' | sudo tee -a /etc/sysctl.conf",
      
      # Enable Transparent Hugepages (THP) for MongoDB 8.0
      "echo 'Enabling Transparent Hugepages for MongoDB 8.0...'",
      "echo 'always' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null",
      "echo 'always' | sudo tee /sys/kernel/mm/transparent_hugepage/defrag > /dev/null",
      
      # Make THP settings persistent across reboots
      "sudo mkdir -p /etc/systemd/system/mongodb-thp.service.d",
      <<-EOT
      sudo tee /etc/systemd/system/mongodb-thp.service << 'EOF'
      [Unit]
      Description=Enable Transparent Hugepages for MongoDB 8.0
      
      [Service]
      Type=oneshot
      ExecStart=/bin/sh -c 'echo always > /sys/kernel/mm/transparent_hugepage/enabled'
      ExecStart=/bin/sh -c 'echo always > /sys/kernel/mm/transparent_hugepage/defrag'
      RemainAfterExit=yes
      
      [Install]
      WantedBy=multi-user.target
      EOF
      EOT
      ,
      "sudo systemctl daemon-reload",
      "sudo systemctl enable mongodb-thp.service",
      "sudo systemctl start mongodb-thp.service",
      
      # Setup native NVMe storage for MongoDB
      "echo 'Setting up native NVMe storage for MongoDB...'",
      "sudo mkdir -p /data",
      
      # Set permissions
      "sudo chown -R mongodb:mongodb /data",
      
      # Create secure MongoDB configuration
      "echo 'Creating secure MongoDB configuration...'",
      "export HOSTNAME=$(hostname -f)",
      "echo \"Using hostname: $HOSTNAME for TLS certificate\"",
      <<-EOT
      sudo tee /etc/mongod.conf > /dev/null <<'MONGOD_EOF'
storage:
  dbPath: /data
  wiredTiger:
    engineConfig:
      cacheSizeGB: ${floor((var.memory_size_mb * 0.5) / 1024)} # 50% of RAM for WiredTiger cache
      journalCompressor: snappy
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true
systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true
  logRotate: reopen
operationProfiling:
  mode: slowOp
  slowOpThresholdMs: 100
net:
  bindIp: 0.0.0.0
  port: 27017
  maxIncomingConnections: 20000
%{~ if var.enable_tls }
  tls:
    mode: requireTLS
    certificateKeyFile: /etc/letsencrypt/live/${var.domain_prefix}${each.key}.${var.dns_domain}/mongodb.pem
    CAFile: /etc/ssl/certs/ca-certificates.crt
    allowConnectionsWithoutCertificates: true
%{~ if var.letsencrypt_staging }
    allowInvalidCertificates: true
%{~ endif }
%{~ endif }
security:
  keyFile: /etc/mongodb/mongodb-keyfile
replication:
  replSetName: ${var.replica_set_name}
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
MONGOD_EOF
      EOT
      ,
      
      # Create systemd override for MongoDB
      "echo 'Creating systemd override for MongoDB...'",
      "sudo mkdir -p /etc/systemd/system/mongod.service.d",
      <<-EOT
      sudo tee /etc/systemd/system/mongod.service.d/override.conf > /dev/null << 'EOF'
      [Service]
      LimitFSIZE=infinity
      LimitCPU=infinity
      LimitAS=infinity
      LimitNOFILE=64000
      LimitNPROC=64000
      LimitMEMLOCK=infinity
      TasksMax=infinity
      EOF
      EOT
      ,
      
      # Update system limits for MongoDB user
      "echo 'Updating system limits for MongoDB...'",
      <<-EOT
      sudo tee -a /etc/security/limits.conf > /dev/null << 'EOF'
      mongodb soft nofile 64000
      mongodb hard nofile 64000
      mongodb soft nproc 64000
      mongodb hard nproc 64000
      mongodb soft memlock unlimited
      mongodb hard memlock unlimited
      EOF
      EOT
      ,
      
      # Create directories for MongoDB
      "sudo mkdir -p /var/run/mongodb",
      "sudo chown mongodb:mongodb /var/run/mongodb",
      
      # Optimize kernel settings for MongoDB
      "echo 'Optimizing kernel settings for MongoDB...'",
      <<-EOT
      sudo tee -a /etc/sysctl.conf > /dev/null << 'EOF'
      # MongoDB network settings
      net.ipv4.tcp_keepalive_time = 300
      net.ipv4.tcp_keepalive_intvl = 30
      net.ipv4.tcp_keepalive_probes = 9
      # MongoDB disk settings optimized for NVMe
      vm.dirty_ratio = 15
      vm.dirty_background_ratio = 5
      vm.dirty_expire_centisecs = 500
      vm.dirty_writeback_centisecs = 100
      # MongoDB performance settings
      kernel.pid_max = 64000
      kernel.threads-max = 64000
      vm.swappiness = 1
      vm.zone_reclaim_mode = 0
      # NVMe-specific optimizations
      vm.vfs_cache_pressure = 50
      EOF
      EOT
      ,
      "sudo sysctl -p",
      
      # Wait for keyfile to be distributed
      "echo 'Waiting for keyfile to be distributed...'",
      "until [ -f /etc/mongodb/mongodb-keyfile ]; do",
      "  echo 'Keyfile not found, waiting...'",
      "  sleep 5",
      "done",
      "echo 'Keyfile found!'",
      
      # Ensure MongoDB service exists, stop if running, then start with new config
      "sudo systemctl daemon-reload",
      "if systemctl list-unit-files | grep -q mongod.service; then",
      "  echo 'Stopping MongoDB if running...'",
      "  sudo systemctl stop mongod || true",
      "  sudo systemctl enable mongod",
      "  echo 'Starting MongoDB with TLS-enabled config...'",
      "  sudo systemctl start mongod",
      "else",
      "  echo 'ERROR: mongod.service not found. MongoDB installation may have failed.'",
      "  exit 1",
      "fi",
      
      # Wait for MongoDB to start
      "echo 'Waiting for MongoDB to start...'",
      "until sudo systemctl is-active --quiet mongod && mongosh ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --eval 'db.runCommand({ ping: 1 })' >/dev/null 2>&1; do",
      "  echo 'Waiting for MongoDB to become available...'",
      "  sleep 2",
      "done",
      "echo 'MongoDB is running and accepting connections'"
    ]
  }
}

# Initialize replica set on primary node
resource "null_resource" "mongodb_replica_init" {
  depends_on = [
    null_resource.mongodb_init
  ]

  triggers = {
    cluster_instance_ids = join(",", [for key in local.sorted_node_keys : hcloud_server.mongodb[key].id])
  }

  connection {
    type        = "ssh"
    user        = "mongodb"
    private_key = file(var.ssh_private_key_path)
    host        = hcloud_server.mongodb[local.sorted_node_keys[0]].ipv4_address
    agent       = false
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      # Wait for all nodes to be available
      "echo 'Waiting for all MongoDB nodes to be available...'",
      "for hostname in ${join(" ", [for key in local.sorted_node_keys : "${var.domain_prefix}${key}.${var.dns_domain}"])}; do",
      "  until mongosh --host $hostname ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --eval 'db.runCommand({ ping: 1 })' >/dev/null 2>&1; do",
      "    echo \"Waiting for MongoDB on $hostname...\"",
      "    sleep 5",
      "  done",
      "done",
      
      # Initialize replica set with priorities
      "echo 'Initializing replica set with priorities...'",
      <<-EOT
      mongosh ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --eval '
        rs.initiate({
          _id: "${var.replica_set_name}",
          members: [
            ${join(",\n            ", [
              for key in local.sorted_node_keys :
              "{ _id: ${local.mongodb_nodes[key].global_index}, host: \"${var.domain_prefix}${key}.${var.dns_domain}:27017\", priority: ${local.mongodb_nodes[key].priority}, tags: { name: \"${key}\", region: \"${local.mongodb_nodes[key].region_key}\", location: \"${local.mongodb_nodes[key].location}\", server_type: \"${local.mongodb_nodes[key].server_type}\" } }"
            ])}
          ]
        });'
      EOT
      ,
      
      # Wait for replica set to stabilize and have a primary
      "echo 'Waiting for replica set to stabilize and elect a primary...'",
      "while true; do",
      "  sleep 5",
      "  STATUS=$(mongosh ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --quiet --eval 'rs.status().members.map(m => m.stateStr)')",
      "  echo \"Current replica set status: $STATUS\"",
      "  if echo \"$STATUS\" | grep -q \"PRIMARY\"; then",
      "    echo 'Primary node detected'",
      "    break",
      "  fi",
      "  echo 'No primary node yet, checking replica set status...'",
      "  mongosh ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --eval 'rs.status()'",
      "  echo 'Forcing replica set reconfiguration...'",
      "  if mongosh ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --quiet --eval 'db.auth(\"${var.mongo_admin_username}\", \"${var.mongo_admin_password}\")' admin; then",
      "    echo 'Using authentication for reconfiguration...'",
      "    mongosh ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --username '${var.mongo_admin_username}' --password '${var.mongo_admin_password}' --authenticationDatabase 'admin' --eval 'rs.reconfig(rs.config(), {force: true})'",
      "  else",
      "    echo 'Reconfiguring without authentication...'",
      "    mongosh ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --eval 'rs.reconfig(rs.config(), {force: true})'",
      "  fi",
      "  sleep 10",
      "done",
      
      # Admin user creation is handled by local-exec provisioner below
      "echo 'Replica set initialized successfully'"
    ]
  }
  
  # Create admin user on PRIMARY from local machine
  provisioner "local-exec" {
    command = <<-EOT
      echo "Creating admin user on replica set..."
      
      # Try to create admin user on each node until one succeeds
      ADMIN_CREATED=false
      ${join("\n      ", [for key in local.sorted_node_keys : 
        <<-CMD
echo "Trying to create admin user on node: ${key}"
if ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} mongodb@${hcloud_server.mongodb[key].ipv4_address} "mongosh ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --eval '
  admin = db.getSiblingDB(\"admin\");
  try {
    admin.createUser({
      user: \"${var.mongo_admin_username}\",
      pwd: \"${var.mongo_admin_password}\",
      roles: [ { role: \"root\", db: \"admin\" } ]
    });
    print(\"Admin user created successfully\");
  } catch (e) {
    if (e.code === 51003) {
      print(\"Admin user already exists\");
    } else {
      throw e;
    }
  }'" 2>/dev/null; then
  echo "Admin user creation succeeded on node: ${key}"
  ADMIN_CREATED=true
else
  echo "Admin user creation failed on node: ${key}, trying next node..."
fi
if [ "$ADMIN_CREATED" = "true" ]; then
  exit 0
fi
CMD
      ])}
      
      if [ "$ADMIN_CREATED" = "false" ]; then
        echo "ERROR: Failed to create admin user on any node"
        exit 1
      fi
      
      echo "Finding PRIMARY node for verification..."
      PRIMARY_HOSTNAME=$(ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} mongodb@${hcloud_server.mongodb[local.sorted_node_keys[0]].ipv4_address} "mongosh ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --quiet --eval 'rs.status().members.find(m => m.stateStr === \"PRIMARY\").name.split(\":\")[0]'")
      echo "PRIMARY is at: $PRIMARY_HOSTNAME"
      
      echo "Verifying admin user..."
      mongosh --host $PRIMARY_HOSTNAME ${var.enable_tls ? "--tls --tlsAllowInvalidCertificates" : ""} --eval 'db.runCommand({ ping: 1 })' --username '${var.mongo_admin_username}' --password '${var.mongo_admin_password}' --authenticationDatabase 'admin'
      echo "Admin user verification successful!"
    EOT
  }
}

# Create firewall rules for MongoDB cluster
resource "hcloud_firewall" "mongodb" {
  name = "${var.cluster_name}-firewall"

  # Allow ICMP (ping) from anywhere
  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "Allow ICMP (ping) from any source for monitoring and diagnostics"
  }

  # Allow SSH access from specified IPs
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = var.allowed_ssh_ips
    description = "Allow SSH access from authorized IPs"
  }

  # Allow HTTP for Let's Encrypt certificate validation (when TLS is enabled)
  dynamic "rule" {
    for_each = var.enable_tls ? [1] : []
    content {
      direction = "in"
      protocol  = "tcp"
      port      = "80"
      source_ips = [
        "0.0.0.0/0",
        "::/0"
      ]
      description = "Allow HTTP for Let's Encrypt certificate validation"
    }
  }

  # Allow MongoDB access from specified IPs and other replica set members
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "27017"
    source_ips = concat(var.allowed_mongo_ips, [for node in hcloud_server.mongodb : "${node.ipv4_address}/32"])
    description = "Allow MongoDB access from authorized IPs and replica set members"
  }

  # Allow replica set communication from specified IPs and other replica set members
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "27019"
    source_ips = concat(var.allowed_mongo_ips, [for node in hcloud_server.mongodb : "${node.ipv4_address}/32"])
    description = "Allow replica set communication from authorized IPs and replica set members"
  }
}

# Apply firewall to all MongoDB servers
resource "hcloud_firewall_attachment" "mongodb" {
  firewall_id = hcloud_firewall.mongodb.id
  server_ids  = [for key in local.sorted_node_keys : hcloud_server.mongodb[key].id]
}

