# Multi-Region MongoDB Replica Set on Hetzner Cloud

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

Deploy a production-ready, multi-region MongoDB replica set across US and EU regions for a fraction of the cost of MongoDB Atlas.

## 🎯 Motivation

Recent cloud outages (like the AWS us-east-1 incident) have highlighted the importance of multi-region redundancy. This project helps you:

- **Survive regional outages** - MongoDB remains available even if an entire region goes down
- **Reduce costs by 80-90%** - Pay dramatically less than managed MongoDB services
- **Maintain full control** - Own your infrastructure and data
- **Scale easily** - Add or remove nodes across regions with simple Terraform changes

## 💰 Cost Comparison

### Hetzner Cloud (This Solution)

| Region | Nodes | Server Type | RAM per Node | Monthly Cost |
|--------|-------|-------------|--------------|--------------|
| US (Ashburn) | 3 | CPX31 | 8GB | €49.47 (3 × €16.49) |
| EU (Falkenstein) | 2 | CPX32 | 8GB | €21.98 (2 × €10.99) |
| **Total** | **5** | - | **8GB each** | **€71.45/mo** (~$77/mo) |

### MongoDB Atlas (AWS)

| Tier | Nodes | RAM per Node | Monthly Cost (Estimated) |
|------|-------|--------------|--------------------------|
| M30 | 5 (3 US + 2 EU) | 8GB | **$1,200-1,400/mo** |

**💡 Savings: ~$1,300/mo or ~$15,600/year (94% cost reduction)**

*Note: MongoDB Atlas pricing varies by region and commitment. Verify current pricing at [mongodb.com/pricing](https://www.mongodb.com/pricing)*

## ✨ Features

- ✅ **Multi-Region Deployment** - 3 nodes in US (Ashburn), 2 nodes in EU (Falkenstein)
- ✅ **Automated Replica Set Configuration** - Primary/Secondary election with configurable priorities
- ✅ **TLS/SSL Encryption** - Free Let's Encrypt certificates with auto-renewal
- ✅ **DNS-based Discovery** - MongoDB+srv:// connection strings using Cloudflare
- ✅ **Optional Grafana Monitoring** - Prometheus metrics for performance insights
- ✅ **Infrastructure as Code** - Reproducible deployments with Terraform
- ✅ **Production Optimizations** - NVMe storage, proper memory allocation, kernel tuning

## 📋 Prerequisites

Before you begin, you'll need:

1. **[Hetzner Cloud Account](https://hetzner.cloud/?ref=imlNi04HXWMu)** - Cloud infrastructure provider*

*⚠️ **Disclaimer**: If you sign up using the link above, you will receive 20€ of credits and we may receive a small commission at no additional cost to you. This helps support the development and maintenance of this open-source project. You're free to sign up directly at Hetzner without using the referral link if you prefer.*

2. **[Cloudflare Account](https://www.cloudflare.com/)** - For DNS management (free tier works)
3. **[Terraform](https://www.terraform.io/downloads.html)** - v1.3.5 or later
4. **Domain Name** - Managed by Cloudflare (for setting mongodb+srv://)
5. **[Grafana Cloud Account](https://grafana.com/)** - Optional, for monitoring (free tier available)

## 🚀 Step-by-Step Setup Guide

### Step 1: Get Your Hetzner Cloud API Token

1. Sign up or log in to [Hetzner Cloud Console](https://console.hetzner.cloud/)* (or [create account](https://hetzner.cloud/?ref=imlNi04HXWMu))
2. Select your project (or create a new one)
3. Navigate to **Security** → **API Tokens** in the left sidebar
4. Click **Generate API Token**
5. Give it a name (e.g., "terraform-mongodb")
6. Set permissions to **Read & Write**
7. Click **Generate Token**
8. **⚠️ Copy the token immediately** - it won't be shown again!

### Step 2: Configure Cloudflare

#### Get API Token

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Go to **My Profile** → **API Tokens** (top right)
3. Click **Create Token**
4. Use the **Edit zone DNS** template
5. Under **Zone Resources**, select your domain
6. Click **Continue to summary** → **Create Token**
7. **Copy the token** - save it securely

#### Get Zone ID

1. In Cloudflare Dashboard, select your domain
2. Scroll down to the **API** section on the right sidebar
3. Copy your **Zone ID**

### Step 3: Generate SSH Keys

Run the provided script to generate SSH keys for server access:

```bash
./generate_ssh_key.sh
```

This creates:

- `ssh-keys/hcloud_terraform_ssh_key` (private key)
- `ssh-keys/hcloud_terraform_ssh_key.pub` (public key)

The script outputs the path you'll need for Terraform configuration.

### Step 4: Configure Your Environment

Create a `terraform.tfvars` file in the `staging/` directory:

```bash
cd staging
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your actual values:

```hcl
# Provider Authentication
hcloud_token      = "your_hetzner_api_token_here"
cloudflare_token  = "your_cloudflare_api_token_here"
cloudflare_zone_id = "your_cloudflare_zone_id_here"

# Cluster Configuration
cluster_name = "staging01-myproject"  # Change to your desired name
dns_domain   = "yourdomain.com"   # Your domain managed by Cloudflare

# SSH Configuration
ssh_private_key_path = "../ssh-keys/hcloud_terraform_ssh_key"

# Security - IMPORTANT: Replace with your IP!
allowed_ssh_ips = [
  "YOUR_IP_ADDRESS/32",  # Your public IP for SSH access
]

# MongoDB Authentication - CHANGE THESE!
mongo_admin_username = "admin"
mongo_admin_password = "CHANGE_THIS_STRONG_PASSWORD"

# Grafana Cloud Monitoring (Optional)
enable_grafana           = false  # Set to true to enable monitoring
grafana_metrics_url      = ""     # Your Grafana Prometheus endpoint
grafana_metrics_username = ""     # Your Grafana instance ID
grafana_api_key          = ""     # Your Grafana API key
```

**🔒 Security Note:** Never commit `terraform.tfvars` to Git - it contains sensitive credentials!

### Step 5: Deploy the Infrastructure

From the `staging/` directory, run:

```bash
./apply.sh
```

This script will:

1. Initialize Terraform and download required providers
2. Show you a deployment plan
3. Ask for confirmation
4. Provision 5 MongoDB servers across US and EU
5. Configure TLS certificates via Let's Encrypt
6. Set up the replica set with proper priorities
7. Create DNS records in Cloudflare

**⏱️ Deployment Time:** 10-15 minutes

### Step 6: Verify Your Deployment

After successful deployment, Terraform outputs connection strings:

```bash
# View outputs (credentials are hidden by default)
terraform output

# Show MongoDB connection strings
terraform output mongodb_connection_string_srv
terraform output mongodb_connection_string_public
terraform output mongodb_connection_string_direct
```

Test connectivity:

```bash
# Using mongodb+srv:// (cleaner, auto-discovery)
mongosh "mongodb+srv://admin:YOUR_PASSWORD@staging01-myproject-mongo.yourdomain.com/?authSource=admin"

# Check replica set status
rs.status()

# View configuration
rs.conf()
```

### Step 7: Cleanup (When Needed)

To destroy all resources and stop billing:

```bash
cd staging
./destroy.sh
```

**⚠️ Warning:** This permanently deletes all servers and data!

## 🏗️ Architecture

### Replica Set Configuration

```
┌─────────────────────────────────────────────────────────────┐
│                     MongoDB Replica Set                      │
├─────────────────────────────────────────────────────────────┤
│  US Region (Ashburn)               EU Region (Falkenstein)  │
│  ┌────────────────┐                ┌────────────────┐       │
│  │  Node 1 (P=1)  │◄───────────────┤  Node 4 (P=0.5)│       │
│  │   PRIMARY      │                │   SECONDARY    │       │
│  └────────────────┘                └────────────────┘       │
│  ┌────────────────┐                ┌────────────────┐       │
│  │  Node 2 (P=1)  │◄───────────────┤  Node 5 (P=0.5)│       │
│  │   SECONDARY    │                │   SECONDARY    │       │
│  └────────────────┘                └────────────────┘       │
│  ┌────────────────┐                                         │
│  │  Node 3 (P=1)  │                                         │
│  │   SECONDARY    │                                         │
│  └────────────────┘                                         │
└─────────────────────────────────────────────────────────────┘
```

**Priority Weighting:**

- US nodes have priority `1.0` - more likely to become PRIMARY
- EU nodes have priority `0.5` - typically remain SECONDARY
- This minimizes cross-region write latency for US-based applications

**Failover Behavior:**

- If US PRIMARY fails → another US node becomes PRIMARY
- If all US nodes fail → EU node can become PRIMARY
- Ensures high availability even during regional outages

## 🌍 Multi-Environment Setup

To create production, development, or other environments:

1. **Duplicate the staging directory:**

```bash
cp -r staging production
```

2. **Update configuration:**

Edit `production/main.tf`:

```hcl
cluster_name = "production01-myproject"  # Change cluster name

# Optionally adjust resources for production:
memory_size_mb = 16384
regions = {
  us = {
    location       = "ash"
    instance_count = 3
    server_type    = "cpx41"  # Upgrade to 16GB RAM
    priority       = 1
  }
  eu = {
    location       = "fsn1"
    instance_count = 2
    server_type    = "cpx42"  # Upgrade to 16GB RAM
    priority       = 0.5
  }
}
```

3. **Create separate tfvars:**

```bash
cd production
cp terraform.tfvars.example terraform.tfvars
# Edit with production-specific values
```

4. **Deploy:**

```bash
cd production
./apply.sh
```

## 🔌 DNS Configuration

The setup automatically creates:

### A Records (for each node)

```
hcloud-staging01-myproject-mongo-us-1.yourdomain.com → 1.2.3.4
hcloud-staging01-myproject-mongo-us-2.yourdomain.com → 1.2.3.5
hcloud-staging01-myproject-mongo-us-3.yourdomain.com → 1.2.3.6
hcloud-staging01-myproject-mongo-eu-1.yourdomain.com → 5.6.7.8
hcloud-staging01-myproject-mongo-eu-2.yourdomain.com → 5.6.7.9
```

### SRV Records (for mongodb+srv://)

```
_mongodb._tcp.staging01-myproject-mongo.yourdomain.com
  → hcloud-staging01-myproject-mongo-us-1.yourdomain.com:27017
  → hcloud-staging01-myproject-mongo-us-2.yourdomain.com:27017
  → hcloud-staging01-myproject-mongo-us-3.yourdomain.com:27017
  → hcloud-staging01-myproject-mongo-eu-1.yourdomain.com:27017
  → hcloud-staging01-myproject-mongo-eu-2.yourdomain.com:27017
```

### TXT Record (connection options)

```
staging01-myproject-mongo.yourdomain.com
  → "replicaSet=rs0&authSource=admin"
```

## 📊 Monitoring with Grafana Cloud (Optional)

### Setup Grafana Cloud

1. Sign up at [grafana.com](https://grafana.com/) (free tier available)
2. In Grafana Cloud Portal, go to **Prometheus** → **Send Metrics**
3. Copy these values:
   - **Remote Write Endpoint** → `grafana_metrics_url`
   - **Username/Instance ID** → `grafana_metrics_username`
   - **API Key** → Click "Generate now" → `grafana_api_key`

4. Enable in `terraform.tfvars`:

```hcl
enable_grafana           = true
grafana_metrics_url      = "https://prometheus-xxx.grafana.net/api/prom/push"
grafana_metrics_username = "123456"
grafana_api_key          = "glc_xxx"
```

5. Re-apply Terraform:

```bash
cd staging
./apply.sh
```

### View Metrics

1. In Grafana Cloud, go to **Explore**
2. Select your Prometheus data source
3. Query: `mongodb_up{job="integrations/mongodb"}`
4. Import the [MongoDB Integration Dashboard](https://grafana.com/grafana/dashboards/12079)

## 🔧 Troubleshooting

### Issue: Terraform fails with "API rate limit exceeded"

**Solution:** Hetzner has API rate limits. Wait a few minutes and retry.

### Issue: Let's Encrypt certificate fails

**Solution:**

- Ensure DNS records are propagated (check with `dig` or `nslookup`)
- Verify port 80 is open for HTTP-01 challenge
- Check if you've hit Let's Encrypt rate limits (5 per domain per week), you can also set `letsencrypt_staging=true`

### Issue: Can't connect to MongoDB

**Solution:**

- Verify your IP is in `allowed_ssh_ips`
- Check firewall rules in Hetzner Console
- Ensure TLS is enabled in your connection string
- Test with: `mongosh --host <node-ip> --tls --tlsAllowInvalidCertificates`

### Issue: Replica set won't elect PRIMARY

**Solution:**

- Check connectivity between nodes: `rs.status()`
- Verify all nodes can reach each other on port 27017
- Check MongoDB logs: `tail -f /var/log/mongodb/mongod.log`
- Force reconfiguration: `rs.reconfig(rs.config(), {force: true})`

### Issue: High memory usage

**Solution:**

- MongoDB's WiredTiger cache is set to 50% of RAM by default
- This is expected and optimal for performance
- Upgrade to larger instance if needed (CPX41/CPX42 for 16GB RAM)

### Issue: Slow cross-region replication

**Solution:**

- This is normal for multi-region setups
- Optimize by writing to the PRIMARY (usually in US)
- Consider read preference settings in your application
- Monitor replication lag: `rs.printReplicationInfo()`

## 📝 Module Variables Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `hcloud_token` | Hetzner Cloud API token | `"abc123..."` |
| `cloudflare_token` | Cloudflare API token | `"xyz789..."` |
| `cloudflare_zone_id` | Cloudflare zone ID | `"def456..."` |
| `cluster_name` | Cluster identifier | `"staging01-myproject"` |
| `dns_domain` | Your domain name | `"yourdomain.com"` |
| `ssh_private_key_path` | Path to SSH private key | `"../ssh-keys/key"` |
| `allowed_ssh_ips` | IPs allowed for SSH/MongoDB | `["1.2.3.4/32"]` |
| `mongo_admin_username` | MongoDB admin username | `"admin"` |
| `mongo_admin_password` | MongoDB admin password | `"SecurePass123!"` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_grafana` | Enable Grafana monitoring | `false` |
| `grafana_metrics_url` | Grafana Prometheus endpoint | `""` |
| `grafana_metrics_username` | Grafana instance ID | `""` |
| `grafana_api_key` | Grafana API key | `""` |
| `enable_tls` | Enable TLS with Let's Encrypt | `true` |
| `letsencrypt_email` | Email for Let's Encrypt | `"tls@sample.dev"` |
| `letsencrypt_staging` | Use LE staging (testing) | `false` |
| `domain_prefix` | Hostname prefix | `"hcloud-"` |
| `enable_backups` | Enable Hetzner backups | `false` |

## 🤝 Contributing

We welcome contributions! If you have feedback, improvements, or bug fixes:

1. **Fork this repository**
2. **Create a feature branch:** `git checkout -b feature/amazing-improvement`
3. **Make your changes and test thoroughly**
4. **Commit with clear messages:** `git commit -m 'fix: add amazing improvement'`
5. **Push to your fork:** `git push origin feature/amazing-improvement`
6. **Open a Pull Request** with a detailed description

## 📄 License

This project is licensed under the **MIT License** - see below for details:

```
MIT License

Copyright (c) 2025 tonoid (microstartup studio)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 👨‍💻 Credits

**Created and maintained by [tonoid](https://www.tonoid.com)** - A microstartup studio building services like [2sync.com](https://2sync.com) or [refurb.me](https://www.refurb.me).

---

**⭐ If this project helped you, please star the repository and share it with others!**

**📧 Questions or issues?** Open an issue on GitHub.
