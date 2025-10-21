variable "cluster_name" {
  description = "Name of the MongoDB cluster"
  type        = string
}

variable "regions" {
  description = "Map of regions with their configurations"
  type = map(object({
    location       = string
    instance_count = number
    server_type    = string
    priority       = number
  }))
  
  validation {
    condition = alltrue([
      for region, config in var.regions :
      config.instance_count > 0 && config.priority >= 0
    ])
    error_message = "Each region must have at least 1 instance and non-negative priority"
  }
}

variable "ssh_public_key" {
  description = "SSH public key for server access"
  sensitive   = true
  type        = string
}

variable "ssh_key_id" {
  description = "ID of the SSH key in Hetzner Cloud"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the MongoDB resources"
  type        = list(string)
  default     = []
}

variable "allowed_ssh_ips" {
  description = "List of IP addresses allowed to connect via SSH"
  type        = list(string)
}

variable "allowed_mongo_ips" {
  description = "List of IP addresses allowed to connect to MongoDB"
  type        = list(string)
}

variable "mongodb_version" {
  description = "Version of MongoDB to install"
  type        = string
  default     = "8.0"
}

variable "replica_set_name" {
  description = "Name of the MongoDB replica set"
  type        = string
  default     = "rs0"
}

variable "mongo_admin_username" {
  description = "MongoDB admin username"
  type        = string
  sensitive   = true
}

variable "mongo_admin_password" {
  description = "MongoDB admin password"
  type        = string
  sensitive   = true

}

variable "enable_backups" {
  description = "Whether to enable automated backups"
  type        = bool
  default     = false
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for server access"
  type        = string
}

variable "memory_size_mb" {
  description = "Amount of memory in MB for MongoDB WiredTiger cache calculation"
  type        = number
}

variable "enable_grafana" {
  description = "Enable Grafana Cloud monitoring with Alloy"
  type        = bool
  default     = false
}

variable "grafana_metrics_url" {
  description = "The URL for the Grafana Prometheus remote write endpoint."
  type        = string
  default     = ""
}

variable "grafana_metrics_username" {
  description = "The username for Grafana Cloud Metrics."
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_api_key" {
  description = "The API key for Grafana Cloud."
  type        = string
  sensitive   = true
  default     = ""
}

variable "environment" {
  description = "The environment name for metric labels (e.g., staging, production)"
  type        = string
  default     = "production"
}

variable "enable_tls" {
  description = "Enable TLS/SSL for MongoDB connections using Let's Encrypt"
  type        = bool
  default     = true
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
  default     = ""
}

variable "letsencrypt_staging" {
  description = "Use Let's Encrypt staging environment (for testing, avoids rate limits)"
  type        = bool
  default     = false
}

variable "dns_domain" {
  description = "DNS domain for MongoDB servers (e.g., sample.dev)"
  type        = string
}

variable "domain_prefix" {
  description = "Prefix for MongoDB server hostnames (e.g., 'hcloud-' results in hcloud-{server-name}.{dns_domain})"
  type        = string
  default     = "hcloud-"
}

