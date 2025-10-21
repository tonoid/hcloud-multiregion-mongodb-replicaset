output "connection_string_public" {
  description = "MongoDB connection string for the replica set (public IPs)"
  value       = "mongodb://${var.mongo_admin_username}:${var.mongo_admin_password}@${join(",", [for node in hcloud_server.mongodb : "${node.ipv4_address}:27017"])}/?replicaSet=${var.replica_set_name}&authSource=admin"
  sensitive   = true
}

output "connection_string_srv" {
  description = "MongoDB+srv connection string (requires DNS SRV records to be configured)"
  value       = "mongodb+srv://${var.mongo_admin_username}:${var.mongo_admin_password}@${var.cluster_name}/?authSource=admin"
  sensitive   = true
}

output "mongodb_ips_public" {
  description = "List of MongoDB server public IPs"
  value       = [for node in hcloud_server.mongodb : node.ipv4_address]
}

output "mongodb_nodes" {
  description = "Map of MongoDB nodes with their details"
  value = {
    for key, node in hcloud_server.mongodb : key => {
      name     = node.name
      ip       = node.ipv4_address
      location = node.location
      hostname = "${var.domain_prefix}${key}.${var.dns_domain}"
    }
  }
}

