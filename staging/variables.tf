# Provider Authentication
variable "hcloud_token" {
  description = "Hetzner Cloud API token for authentication"
  type        = string
  sensitive   = true
}

variable "cloudflare_token" {
  description = "Cloudflare API token for DNS management"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for DNS records"
  type        = string
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name prefix for the cluster resources (will be used as: {cluster_name}-network, {cluster_name}-mongo)"
  type        = string
}

# DNS Configuration
variable "dns_domain" {
  description = "DNS domain for the cluster (e.g., sample.dev)"
  type        = string
}

# SSH Configuration
variable "ssh_private_key_path" {
  description = "Path to SSH private key for server access (e.g., ./ssh-keys/hcloud_terraform_ssh_key)"
  type        = string
}

# Security Configuration
variable "allowed_ssh_ips" {
  description = "List of IP addresses (CIDR notation) allowed to connect via SSH and MongoDB"
  type        = list(string)
}

# MongoDB Authentication
variable "mongo_admin_username" {
  description = "MongoDB admin username for root access"
  type        = string
  sensitive   = true
}

variable "mongo_admin_password" {
  description = "MongoDB admin password for root access"
  type        = string
  sensitive   = true
}

# Grafana Cloud Monitoring (Optional)
variable "enable_grafana" {
  description = "Enable Grafana Cloud monitoring with Alloy"
  type        = bool
  default     = false
}

variable "grafana_metrics_url" {
  description = "Grafana Cloud Prometheus remote write endpoint URL"
  type        = string
  default     = ""
}

variable "grafana_metrics_username" {
  description = "Grafana Cloud Metrics username (instance ID)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_api_key" {
  description = "Grafana Cloud API key for metrics authentication"
  type        = string
  sensitive   = true
  default     = ""
}

