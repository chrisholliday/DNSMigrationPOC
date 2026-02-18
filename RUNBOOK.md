# DNS Migration POC - Phased Implementation Runbook

**Date Created**: February 18, 2026  
**Status**: Phase 1 Implementation  
**Objective**: Validate on-prem DNS migration to Azure Private DNS through staged, isolated phases

---

## Overview

This runbook guides you through a **5-phase implementation** of a DNS migration proof-of-concept. Each phase is independently deployable with clear success criteria. This approach ensures:

- ✅ Isolation: Each phase stands alone; nothing breaks in later phases
- ✅ Debugging: Exact failure point is clear
- ✅ Learning: Understand what works before adding complexity
- ✅ Reusability: Phase templates become building blocks

---

## Architecture Summary

```
Phase 1 (On-Prem Network & VMs)
├── VNet: 10.10.0.0/16
├── DNS Server VM: 10.10.1.10 (Ubuntu 22.04)
└── Client VM: 10.10.1.20 (Ubuntu 22.04)

Phase 2 (DNS Server Configuration)
├── Install dnsmasq on DNS Server
├── Configure onprem.pvt zone
└── Add local hosts entries

Phase 3 (Client Validation)
├── Configure client DNS resolver to use DNS Server
├── Test local domain resolution
└── Test public DNS resolution

Phase 4 (Hub Environment & Peering)
├── VNet: 10.20.0.0/16
├── Peering: On-Prem ↔ Hub
├── Hub DNS Server: 10.20.1.10
└── Configure forwarders for azure.pvt zone

Phase 5 (Azure Private DNS & Resolver)
├── Azure Private DNS Zone: privatelink.blob.core.windows.net
├── Spokes: 10.30.0.0/16 and 10.40.0.0/16
├── Storage Accounts with Private Endpoints
└── Private Resolver (Inbound/Outbound)
```

---

## Phase 1: On-Prem Foundation Network

### Objective

Deploy a basic on-premises network with two VMs and validate infrastructure connectivity.

### What Gets Created

- Resource Group: `dnsmig-rg-onprem`
- Virtual Network: `dnsmig-onprem-vnet` (10.10.0.0/16)
- Subnet: `snet-vms` (10.10.1.0/24)
- Network Security Group with SSH and DNS rules
- NAT Gateway for outbound internet connectivity
- DNS Server VM: `dnsmig-onprem-vm-dns` (10.10.1.10)
- Client VM: `dnsmig-onprem-vm-client` (10.10.1.20)

### Prerequisites

```powershell
# Install prerequisites
brew install bicep          # macOS with Homebrew
az login
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig -N ""
```

### Deployment Commands

#### Deploy Phase 1

```powershell
cd /Users/chris/Git/DNSMigrationPOC
./scripts/phase1/01-deploy-network.ps1 `
  -SshPublicKeyPath ~/.ssh/dnsmig.pub `
  -Location centralus `
  -Prefix dnsmig
```

**Expected Output:**

```
✓ Bicep CLI: Bicep CLI version X.X.X
✓ SSH public key loaded: ~/.ssh/dnsmig.pub
✓ Using subscription: [Your Subscription]
✓ Deployment succeeded!

Key Outputs:
  Resource Group: dnsmig-rg-onprem
  DNS Server VM: dnsmig-onprem-vm-dns (10.10.1.10)
  Client VM: dnsmig-onprem-vm-client (10.10.1.20)
  VNet: dnsmig-onprem-vnet (10.10.0.0/16)
  NAT Gateway: dnsmig-onprem-nat
```

#### Verify Phase 1

```powershell
./scripts/phase1/02-verify-network.ps1 `
  -ResourceGroupName dnsmig-rg-onprem `
  -Verbose
```

### Phase 1 Success Criteria

✅ Both VMs are in "Succeeded" provisioning state  
✅ Network NSG is attached to subnet  
✅ NAT Gateway is operational  
✅ Can SSH to DNS Server: `ssh azureuser@<public-ip>`  
✅ Can SSH to Client VM: `ssh azureuser@<public-ip>`  
✅ Both VMs have internet connectivity (ping 8.8.8.8)  
✅ VMs can reach each other on subnet

### Troubleshooting Phase 1

**Deployment fails:**

```powershell
# Check prerequisites
az account show
bicep --version

# Check resource group creation
az group show -n dnsmig-rg-onprem

# Review deployment errors
az deployment group show -g dnsmig-rg-onprem -n dnsmig-onprem-deploy -o json | jq '.properties.deploymentOperations'
```

**VMs not accessible:**

```powershell
# Check if VMs are created
az vm list -g dnsmig-rg-onprem -o table

# Get actual public IPs
az vm list-ip-addresses -g dnsmig-rg-onprem -o table

# Check NSG rules
az network nsg rule list -g dnsmig-rg-onprem --nsg-name dnsmig-onprem-nsg -o table
```

**Internet connectivity failing:**

```powershell
# Verify NAT Gateway
az network nat list -g dnsmig-rg-onprem -o table

# Check Public IP
az network public-ip list -g dnsmig-rg-onprem -o table
```

---

## Phase 2: DNS Server Configuration

### Objective

Install and configure dnsmasq on the DNS Server VM to serve the `onprem.pvt` zone.

### What Gets Configured

- Install: dnsmasq, curl, net-tools, bind-utils
- Create zone file: `/etc/dnsmasq.d/onprem.conf`
- Create hosts file: `/etc/dnsmasq.hosts`
- Enable and start dnsmasq service
- Configure forwarders to Azure DNS (168.63.129.16) and Google DNS (8.8.8.8)

### Deployment Commands

#### Configure Phase 2

```powershell
./scripts/phase2/03-configure-dns-server.ps1 `
  -ResourceGroupName dnsmig-rg-onprem `
  -DnsServerVmName dnsmig-onprem-vm-dns `
  -DnsServerIp 10.10.1.10 `
  -Verbose
```

**Expected Output:**

```
Phase 2: DNS Server Configuration
──────────────────────────────────
✓ Connecting to DNS Server (dnsmig-onprem-vm-dns)
✓ Installing packages... (this may take 2-3 minutes)
✓ Creating dnsmasq configuration
✓ Creating local hosts file
✓ Enabling and starting dnsmasq
✓ Verifying service status

DNS Server is ready at 10.10.1.10
```

#### Verify Phase 2

```powershell
./scripts/phase2/04-verify-dns-server.ps1 `
  -ResourceGroupName dnsmig-rg-onprem `
  -DnsServerVmName dnsmig-onprem-vm-dns `
  -Verbose
```

### Phase 2 Success Criteria

✅ dnsmasq package installed  
✅ dnsmasq service is running  
✅ Service listening on port 53 (UDP and TCP)  
✅ Configuration file created: `/etc/dnsmasq.d/onprem.conf`  
✅ Local hosts file created: `/etc/dnsmasq.hosts`  
✅ Service survives restart: `systemctl restart dnsmasq`  
✅ Direct server query returns correct record:  
   `nslookup onprem-dns.onprem.pvt 10.10.1.10` → `10.10.1.10`

### Troubleshooting Phase 2

**Package installation fails:**

```bash
# SSH to DNS Server
ssh azureuser@<public-ip>

# Update apt cache and retry
sudo apt-get update
sudo apt-get install -y dnsmasq curl net-tools bind-utils
sudo systemctl status dnsmasq
```

**dnsmasq won't start:**

```bash
# Check syntax errors in config
sudo dnsmasq --test

# View service logs
sudo journalctl -u dnsmasq -n 50

# Check if port 53 is in use
sudo netstat -tuln | grep :53
```

**DNS queries fail:**

```bash
# Test from DNS Server itself
dig onprem-dns.onprem.pvt @127.0.0.1
nslookup onprem-dns.onprem.pvt 10.10.1.10

# Check configuration
cat /etc/dnsmasq.d/onprem.conf
cat /etc/dnsmasq.hosts
```

---

## Phase 3: Client DNS Resolution

### Objective

Configure the client VM to use the DNS Server and validate resolution of both internal and external domains.

### What Gets Configured

- Set client DNS resolver to 10.10.1.10
- Install DNS testing tools (dig, nslookup, host)
- Test local domain resolution
- Test public DNS resolution
- Test internet connectivity

### Deployment Commands

#### Configure Phase 3

```powershell
./scripts/phase3/05-configure-client.ps1 `
  -ResourceGroupName dnsmig-rg-onprem `
  -ClientVmName dnsmig-onprem-vm-client `
  -DnsServerIp 10.10.1.10 `
  -Verbose
```

**Expected Output:**

```
Phase 3: Client Configuration
──────────────────────────────
✓ Connecting to client VM (dnsmig-onprem-vm-client)
✓ Installing DNS tools
✓ Configuring DNS resolver to use 10.10.1.10
✓ Restarting systemd-resolved
✓ Verifying client DNS configuration

Client is ready to use DNS Server at 10.10.1.10
```

#### Verify Phase 3

```powershell
./scripts/phase3/06-verify-client.ps1 `
  -ResourceGroupName dnsmig-rg-onprem `
  -ClientVmName dnsmig-onprem-vm-client `
  -Verbose
```

### Phase 3 Success Criteria

✅ Client DNS resolver points to 10.10.1.10  
✅ Local domain resolves from client:  
   `dig onprem-dns.onprem.pvt +short` → `10.10.1.10`  
✅ Public DNS resolves from client:  
   `dig google.com +short` → returns IP  
✅ Client can reach Azure DNS:  
   `dig azure.microsoft.com +short` → returns IP  
✅ Client has internet connectivity: `ping 8.8.8.8`  
✅ No timeout or SERVFAIL errors in queries

### Troubleshooting Phase 3

**Client DNS not resolving:**

```bash
# SSH to client VM
ssh azureuser@<public-ip>

# Check DNS configuration
cat /etc/resolv.conf

# Test directly against DNS Server
dig onprem-dns.onprem.pvt @10.10.1.10

# Check systemd-resolved status
systemctl status systemd-resolved
```

**Public DNS failing:**

```bash
# Test internet connectivity
ping 8.8.8.8

# Test with explicit DNS server
dig google.com @8.8.8.8

# Check if forwarding is working on DNS Server
dig @10.10.1.10 google.com
```

---

## Phase 4: Hub Environment & Peering

### Objective

Deploy the hub VNet with its own DNS server and establish peering between on-prem and hub networks.

### What Gets Created

- Hub Resource Group: `dnsmig-rg-hub`
- Hub VNet: `dnsmig-hub-vnet` (10.20.0.0/16)
- Hub Subnet: `snet-vms` (10.20.1.0/24)
- Hub DNS Server VM: `dnsmig-hub-vm-dns` (10.20.1.10)
- VNet Peering: on-prem ↔ hub (bidirectional)
- NAT Gateway for hub outbound connectivity

### Deployment Commands

#### Deploy Phase 4

```powershell
./scripts/phase4/07-deploy-hub.ps1 `
  -SshPublicKeyPath ~/.ssh/dnsmig.pub `
  -Location centralus `
  -Prefix dnsmig
```

#### Configure Phase 4

```powershell
./scripts/phase4/08-configure-hub-dns.ps1 `
  -ResourceGroupName dnsmig-rg-hub `
  -HubDnsServerVmName dnsmig-hub-vm-dns `
  -HubDnsServerIp 10.20.1.10
```

#### Configure Forwarders (Phase 4)

```powershell
./scripts/phase4/09-configure-forwarders.ps1 `
  -OnPremResourceGroup dnsmig-rg-onprem `
  -OnPremDnsVmName dnsmig-onprem-vm-dns `
  -HubDnsServerIp 10.20.1.10
```

#### Verify Phase 4

```powershell
./scripts/phase4/10-verify-hub.ps1 `
  -OnPremResourceGroup dnsmig-rg-onprem `
  -HubResourceGroup dnsmig-rg-hub `
  -Verbose
```

### Phase 4 Success Criteria

✅ Hub VNet created and accessible  
✅ Hub DNS Server running dnsmasq with `azure.pvt` zone  
✅ VNet peering status is "Connected"  
✅ On-prem client can reach hub DNS Server (10.20.1.10)  
✅ On-prem DNS Server forwards `azure.pvt` queries to hub  
✅ Client can resolve `azure.pvt` records via on-prem DNS  
✅ No routing issues between VNets

---

## Phase 5: Azure Private DNS & Resolver

### Objective

Deploy Azure Private DNS, DNS Resolver, and storage endpoints with automatic private record creation.

### What Gets Created

- Spoke1 VNet: `dnsmig-spoke1-vnet` (10.30.0.0/16)
- Spoke2 VNet: `dnsmig-spoke2-vnet` (10.40.0.0/16)
- Peering: hub ↔ spoke1, hub ↔ spoke2
- Azure Private DNS Zone: `privatelink.blob.core.windows.net`
- Private Resolver (inbound endpoint, outbound endpoint)
- Forwarding Ruleset for `privatelink.blob.core.windows.net`
- Storage Account 1: with private endpoint in spoke1
- Storage Account 2: with private endpoint in spoke2
- Spoke VMs for testing

### Deployment Commands

#### Deploy Phase 5

```powershell
./scripts/phase5/11-deploy-spokes.ps1 `
  -SshPublicKeyPath ~/.ssh/dnsmig.pub `
  -Location centralus `
  -Prefix dnsmig
```

#### Deploy Private DNS

```powershell
./scripts/phase5/12-deploy-private-dns.ps1 `
  -HubResourceGroup dnsmig-rg-hub `
  -HubVnetName dnsmig-hub-vnet `
  -Location centralus
```

#### Deploy Resolver

```powershell
./scripts/phase5/13-deploy-resolver.ps1 `
  -HubResourceGroup dnsmig-rg-hub `
  -HubDnsServerIp 10.20.1.10
```

#### Verify Phase 5

```powershell
./scripts/phase5/14-verify-private-dns.ps1 `
  -Verbose
```

### Phase 5 Success Criteria

✅ Private DNS Zone created and linked to all VNets  
✅ Private Resolver endpoints created (inbound + outbound)  
✅ Storage accounts created with private endpoints  
✅ DNS records automatically created for `blob.core.windows.net`  
✅ Spoke clients can resolve private endpoint IPs  
✅ Storage connectivity works from spokes  
✅ Legacy DNS servers forward to Resolver inbound endpoint  
✅ All cross-VNet DNS resolution works

---

## Cleanup & Rollback

### Remove Specific Phase

```powershell
# Remove Phase 5 (Spokes + Private DNS)
az group delete -n dnsmig-rg-spoke1 --no-wait
az group delete -n dnsmig-rg-spoke2 --no-wait
Remove-AzPrivateDnsZone -Name privatelink.blob.core.windows.net -ResourceGroupName dnsmig-rg-hub

# Remove Phase 4 (Hub)
az group delete -n dnsmig-rg-hub --no-wait

# Remove Phase 1-2 (On-Prem)
az group delete -n dnsmig-rg-onprem --no-wait
```

### Complete Cleanup

```powershell
./scripts/cleanup-all.ps1 -Prefix dnsmig
```

---

## Quick Reference: Commands by Objective

### Test Local Domain Resolution

```bash
ssh azureuser@<client-ip>
dig onprem-dns.onprem.pvt
```

### Test Cross-VNet DNS

```bash
ssh azureuser@<client-ip>
dig azure-dns.azure.pvt
```

### Test Private Endpoint Records

```bash
ssh azureuser@<spoke-vm-ip>
dig blob.core.windows.net
```

### Check DNS Service Status

```bash
ssh azureuser@<dns-server-ip>
systemctl status dnsmasq
cat /etc/dnsmasq.d/*.conf
```

### Monitor DNS Queries

```bash
ssh azureuser@<dns-server-ip>
sudo journalctl -u dnsmasq -f
```

---

## Timeline & Dependencies

```
Phase 1 (15 min) ─────────────────┐
                                  ├─→ Phase 2 (10 min) ─┐
                                  │                      ├─→ Phase 3 (10 min) ─┐
                                                                               ├─→ Phase 4 (20 min) ─┐
                                                                                                    ├─→ Phase 5 (30 min)
```

**Total Time**: ~85 minutes (including validation at each stage)

---

## Success Metrics

| Phase | Metric | Target |
|-------|--------|--------|
| 1 | VM connectivity | 100% SSH access |
| 2 | DNS service | dnsmasq running + listening |
| 3 | Client resolution | 100% DNS queries successful |
| 4 | Cross-VNet DNS | All zones resolvable across VNets |
| 5 | Private DNS | 100% PE record auto-creation |

---

## Notes & Known Issues

- Cloud-init completion checking: Use `cloud-init status` on VMs
- Package installation: May timeout with slow internet (script has retries)
- NAT Gateway: Ensures reliable outbound connectivity for package downloads
- DNS restarts: Service auto-restarts on config changes (systemd)
- Security groups: Minimal rules (SSH + DNS); expand for production

---

## Next Steps

1. ✅ Review this runbook
2. ➡️ Deploy Phase 1 using `scripts/phase1/01-deploy-network.ps1`
3. ➡️ Verify Phase 1 using `scripts/phase1/02-verify-network.ps1`
4. ➡️ Proceed to Phase 2 once Phase 1 is validated
