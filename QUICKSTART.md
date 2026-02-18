# Simplified On-Prem DNS Deployment - Quick Start Guide

This guide walks you through deploying a simplified on-prem DNS environment for the POC.

## Overview

The simplified deployment creates:

- **One Azure VNet** (10.10.0.0/16) simulating an on-premises network
- **DNS Server VM** (10.10.1.10)
  - Runs dnsmasq configured for `onprem.pvt` zone
  - Forwards all other DNS queries to Azure DNS (168.63.129.16) and Google DNS (8.8.8.8)
- **Client VM** (10.10.1.20)
  - Uses the DNS server VM for all DNS queries
  - Tests DNS resolution and internet connectivity
- **NAT Gateway**
  - Provides outbound internet connectivity for both VMs
  - Allows package installation and public DNS queries

## Prerequisites

1. **Azure CLI** - installed and authenticated
2. **Bicep CLI** - for deploying ARM templates via Bicep
3. **SSH key pair** - for Linux VM access
4. **Azure Subscription** - with sufficient quota for VMs

### Install Prerequisites

```bash
# Install Bicep CLI (macOS with Homebrew)
brew install bicep

# Or on Linux
curl -Lo bicep https://aka.ms/bicep/linux && chmod +x ./bicep

# Ensure you have an SSH key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

## Quick Start

### 1. Deploy the Infrastructure

```powershell
cd /path/to/DNSMigrationPOC
./scripts/deploy-simple-onprem.ps1 -SshPublicKeyPath ~/.ssh/id_rsa.pub
```

**Expected Output:**

```
Bicep CLI: Bicep CLI version X.X.X
✓ SSH public key loaded: ~/.ssh/id_rsa.pub

Deployment started...
✓ Deployment succeeded!

Key Outputs:
  Resource Group: dnsmig-rg-onprem
  DNS Server VM: dnsmig-onprem-vm-dns
  DNS Server IP: 10.10.1.10
  Client VM: dnsmig-onprem-vm-client
  VNet: dnsmig-onprem-vnet

Next Steps:
1. Wait 2-3 minutes for cloud-init to complete on both VMs
...
```

### 2. Wait for Cloud-Init (2-3 minutes)

The deployment includes cloud-init scripts that automatically:

- Install dnsmasq on the DNS server
- Configure the DNS server with the onprem.pvt zone
- Install DNS testing tools on the client VM

You can manually check progress by SSHing to the DNS server and running:

```bash
systemctl status dnsmasq
```

### 3. Verify DNS Resolution

Once cloud-init is complete, run the verification script:

```powershell
./scripts/verify-dns.ps1 -ResourceGroupName dnsmig-rg-onprem -Verbose
```

This script will:

- ✓ Check that both VMs are running
- ✓ Verify dnsmasq is operational
- ✓ Query the local onprem.pvt domain
- ✓ Query public DNS (google.com, azure.microsoft.com)
- ✓ Test internet connectivity

**Expected Results:**

```
Phase 1: Infrastructure Verification
✓ Resource group found
✓ DNS server VM found (provisioning state: Succeeded)
✓ DNS server private IP: 10.10.1.10

Phase 2: DNS Server Tests
✓ dnsmasq service is running
✓ dnsmasq configuration loaded
✓ DNS server listening on port 53

Phase 3: DNS Resolution Tests (from DNS Server)
✓ Local domain (onprem.pvt)
✓ Local host (onprem-dns.onprem.pvt)
✓ Public DNS (google.com)
✓ Azure DNS (azure.microsoft.com)

Phase 4-5: Client Tests
✓ Client DNS configuration
✓ Local domain resolution from client
✓ Public DNS resolution from client

Phase 6: Internet Connectivity
✓ Internet connectivity (8.8.8.8)
✓ HTTPS connectivity
```

## Interactive Testing

### SSH to the DNS Server

```bash
az ssh vm \
  -g dnsmig-rg-onprem \
  -n dnsmig-onprem-vm-dns \
  --local-user azureuser
```

Once connected:

```bash
# Check dnsmasq status
systemctl status dnsmasq
systemctl restart dnsmasq  # if needed

# View configuration
cat /etc/dnsmasq.d/onprem.conf

# View DNS logs
journalctl -u dnsmasq -f

# Test local DNS resolution
nslookup onprem.pvt 127.0.0.1
nslookup onprem-dns.onprem.pvt
nslookup google.com
```

### SSH to the Client VM

```bash
az ssh vm \
  -g dnsmig-rg-onprem \
  -n dnsmig-onprem-vm-client \
  --local-user azureuser
```

Once connected:

```bash
# View DNS configuration
cat /etc/resolv.conf

# Test DNS resolution
nslookup onprem.pvt       # Should resolve to 10.10.1.10
nslookup google.com       # Should use DNS forwarding
dig +short onprem.pvt

# Test internet connectivity
curl https://www.google.com -I
ping -c 3 8.8.8.8
```

## DNS Configuration Details

### On the DNS Server

- **Configuration File**: `/etc/dnsmasq.d/onprem.conf`
- **Hosts File**: `/etc/dnsmasq.hosts`
- **Service**: dnsmasq (managed by systemd)

**Example Configuration:**

```
# Local domain
address=/onprem.pvt/10.10.1.10

# DNS Server settings
listen-address=127.0.0.1,::1
listen-address=10.10.1.10

# Upstream DNS servers
server=168.63.129.16  # Azure DNS
server=8.8.8.8        # Google DNS
server=8.8.4.4
```

### On the Client VM

- **DNS Server**: 10.10.1.10 (set via VNet DHCP)
- **Resolver Conf**: `/etc/resolv.conf`

## Troubleshooting

### DNS not resolving locally

```bash
# SSH to DNS server
systemctl status dnsmasq

# Check if dnsmasq is listening
netstat -tuln | grep :53

# View recent logs
journalctl -u dnsmasq -n 20

# Restart the service
sudo systemctl restart dnsmasq
```

### Client can't reach DNS server

```bash
# From client VM, test connectivity
nc -zv 10.10.1.10 53

# From client VM, check DNS config
cat /etc/resolv.conf

# Check NSG rules (from local terminal)
az network nsg rule list \
  -g dnsmig-rg-onprem \
  --nsg-name dnsmig-onprem-nsg
```

### No internet connectivity

```bash
# Check NAT Gateway status
az network nat gateway show \
  -g dnsmig-rg-onprem \
  -n dnsmig-onprem-nat

# Check public IP
az network public-ip show \
  -g dnsmig-rg-onprem \
  -n dnsmig-onprem-nat-pip
```

## Cleanup

To remove all resources:

```powershell
az group delete \
  -n dnsmig-rg-onprem \
  --yes \
  --no-wait
```

## Next Steps: Scaling Up

Once this simplified on-prem environment is working reliably:

1. **Add a Hub VNet** with its own DNS server
2. **Add VNet Peering** between on-prem and hub
3. **Add Spoke VNets** with storage accounts
4. **Test zone forwarding** between DNS servers
5. **Test DNS Resolver** for hybrid DNS scenarios
6. **Migrate to Azure Private DNS** zone by zone

Each step can be tested incrementally before moving to the next.

## Files

- **Bicep Template**: `bicep/simple-onprem.bicep`
- **Deployment Script**: `scripts/deploy-simple-onprem.ps1`
- **Verification Script**: `scripts/verify-dns.ps1`
- **Archived Scripts**: `scripts-archive/` (original complex deployment)

---

**Last Updated**: February 2026
**POC Purpose**: Demonstrate VM-hosted DNS → Azure Private DNS migration
