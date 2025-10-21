# Configure Terraform and required providers
terraform {
  required_version = ">= 1.3.5"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.54.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.47.0"
    }
  }
}

# Configure provider authentication
provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

# SSH Key Configuration
resource "hcloud_ssh_key" "ssh_key" {
  name       = "${var.cluster_name}-ssh-key"
  public_key = file("${var.ssh_private_key_path}.pub")
}

# Network Configuration
resource "hcloud_network" "network" {
  name     = "${var.cluster_name}-network"
  ip_range = "10.0.0.0/16"
}

# –––––––––––––––––––––––––––––––––
# –––––––––––––––––––––––––––––––––
# –––––––––––––––––––––––––––––––––
# MONGODB (Multi-Region)
# –––––––––––––––––––––––––––––––––
# MongoDB Multi-Region Configuration
module "mongodb_multiregion" {
  source = "../modules/mongodb-multiregion"
  providers = {
    hcloud = hcloud
  }
  
  depends_on = [
    hcloud_ssh_key.ssh_key
  ]
  
  cluster_name   = "${var.cluster_name}-mongo"
  memory_size_mb = 8192  # How much total memory per instance (used to calculate WiredTiger cache size)
  
  regions = {
    us = {
      location       = "ash"  
      instance_count = 3
      server_type    = "cpx31"  
      priority       = 1      
    }
    eu = {
      location       = "fsn1"  
      instance_count = 2
      server_type    = "cpx31"  
      priority       = 0.5   
    }
  }
  
  ssh_public_key       = file("${var.ssh_private_key_path}.pub")
  ssh_private_key_path = var.ssh_private_key_path
  ssh_key_id           = hcloud_ssh_key.ssh_key.id
  
  allowed_ssh_ips      = var.allowed_ssh_ips
  allowed_mongo_ips    = var.allowed_ssh_ips
  
  mongodb_version      = "8.0"
  replica_set_name     = "rs0"
  mongo_admin_username = var.mongo_admin_username
  mongo_admin_password = var.mongo_admin_password
  
  enable_grafana           = var.enable_grafana
  grafana_metrics_url      = var.grafana_metrics_url
  grafana_metrics_username = var.grafana_metrics_username
  grafana_api_key          = var.grafana_api_key
  environment              = "staging"
  
  enable_backups = false
  
  # TLS configuration with Let's Encrypt
  enable_tls          = true
  letsencrypt_email   = "tls@sample.dev"  # Update with your email
  letsencrypt_staging = false  # Use staging certificates
  dns_domain          = var.dns_domain  # Domain for MongoDB server hostnames
}

# Save ipv4 of all mongodb nodes into cloudflare records (5 nodes: 3 US + 2 EU)
# Create A records matching the server names for Let's Encrypt certificates
resource "cloudflare_record" "mongodb" {
  for_each = module.mongodb_multiregion.mongodb_nodes
  zone_id  = var.cloudflare_zone_id
  name     = each.value.hostname
  content  = each.value.ip
  type     = "A"
  proxied  = false
}

# Create SRV records for MongoDB+srv:// connection string
resource "cloudflare_record" "mongodb_srv" {
  for_each = module.mongodb_multiregion.mongodb_nodes
  zone_id  = var.cloudflare_zone_id
  name     = "_mongodb._tcp.${var.cluster_name}-mongo"
  type     = "SRV"
  
  data {
    service  = "_mongodb"
    proto    = "_tcp"
    name     = "${var.cluster_name}-mongo"
    priority = 0
    weight   = 0
    port     = 27017
    target   = cloudflare_record.mongodb[each.key].hostname
  }
}

# Create TXT record for MongoDB connection options
resource "cloudflare_record" "mongodb_txt" {
  zone_id = var.cloudflare_zone_id
  name    = "${var.cluster_name}-mongo"
  type    = "TXT"
  content = "replicaSet=rs0&authSource=admin"
}

output "mongodb_connection_string_direct" {
  value     = "mongodb://${var.mongo_admin_username}:${var.mongo_admin_password}@${values(cloudflare_record.mongodb)[0].hostname}:27017/?directConnection=true&tls=true"
  sensitive = true
}

output "mongodb_connection_string_public" {
  value     = module.mongodb_multiregion.connection_string_public
  sensitive = true
}

output "mongodb_connection_string_srv" {
  value       = "mongodb+srv://${var.mongo_admin_username}:${var.mongo_admin_password}@${var.cluster_name}-mongo.${var.dns_domain}/?authSource=admin"
  sensitive   = true
  description = "MongoDB+srv connection string with TLS (cleaner, auto-discovers all nodes via DNS)"
}
