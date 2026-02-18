# Phase 1: On-Prem Network Foundation

## Overview

Phase 1 deploys the basic network infrastructure for the on-premises environment without any DNS configuration. This phase establishes:

- **Virtual Network**: 10.10.0.0/16
- **Subnet**: 10.10.1.0/24  
- **Network Security Group**: SSH + DNS rules
- **NAT Gateway**: Outbound internet connectivity
- **Two VMs**: DNS Server (10.10.1.10) and Client (10.10.1.20)

## Timeline

**Duration**: ~15 minutes deployment + 2-3 minutes for VMs to fully start

## Prerequisites

```bash
# Install prerequisites (macOS)
brew install bicep

# Ensure Azure CLI is installed and authenticated
az login

# Create SSH key pair (if you don't have one)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig -N ""
```

## Files

```
bicep/phase1/
├── network.bicep              # Infrastructure-only template

scripts/phase1/
├── 01-deploy-network.ps1      # Deployment script
└── 02-verify-network.ps1      # Verification script
```

## Step 1: Deploy Phase 1

```powershell
cd /Users/chris/Git/DNSMigrationPOC

./scripts/phase1/01-deploy-network.ps1 `
  -SshPublicKeyPath ~/.ssh/dnsmig.pub `
  -Location centralus `
  -Prefix dnsmig
```

### Expected Output

```
============================================================
Phase 1: On-Prem Network Deployment
============================================================

Checking prerequisites...
✓ Bicep CLI: Bicep CLI version X.X.X
✓ SSH public key loaded: ~/.ssh/dnsmig.pub
✓ Using subscription: [Your Subscription]

Deployment Configuration
────────────────────────────────────────
  Resource Group: dnsmig-rg-onprem
  Location: centralus
  Prefix: dnsmig
  VNet: 10.10.0.0/16
  Subnet: 10.10.1.0/24
  DNS Server IP: 10.10.1.10
  Client VM IP: 10.10.1.20

Creating resource group...
✓ Resource group created: dnsmig-rg-onprem
✓ Deployment succeeded!

Deployment Outputs
────────────────────────────────────────
VNet Name:              dnsmig-onprem-vnet
VNet ID:                /subscriptions/.../resourceGroups/dnsmig-rg-onprem/providers/Microsoft.Network/virtualNetworks/dnsmig-onprem-vnet

DNS Server Name:        dnsmig-onprem-vm-dns
DNS Server Private IP:  10.10.1.10
DNS Server VM ID:       /subscriptions/.../Microsoft.Compute/virtualMachines/dnsmig-onprem-vm-dns

Client VM Name:         dnsmig-onprem-vm-client
Client VM Private IP:   10.10.1.20
Client VM ID:           /subscriptions/.../Microsoft.Compute/virtualMachines/dnsmig-onprem-vm-client

NAT Gateway Public IP:  [public-ip-address]

SSH Access
────────────────────────────────────────
DNS Server:   ssh azureuser@[public-ip]
Client VM:    ssh azureuser@[public-ip]

Next Steps
────────────────────────────────────────
1. Verify Phase 1 deployment:
   ./02-verify-network.ps1 -ResourceGroupName dnsmig-rg-onprem -Verbose

2. Wait 1-2 minutes for VMs to fully start and public IPs to be assigned

3. Test connectivity to VMs:
   ssh azureuser@[public-ip] 'hostname && uptime'

4. Once verified, proceed to Phase 2 (DNS Server configuration):
   ./scripts/phase2/03-configure-dns-server.ps1 -ResourceGroupName dnsmig-rg-onprem
```

## Step 2: Verify Phase 1

Wait 1-2 minutes for VMs to fully start, then verify:

```powershell
./scripts/phase1/02-verify-network.ps1 `
  -ResourceGroupName dnsmig-rg-onprem `
  -Verbose
```

### Expected Output

```
================================================================
Phase 1: Network Deployment Verification
================================================================

═ Checking Azure CLI authentication...
⟳ Azure CLI authenticated...
✓ Azure CLI authenticated

Phase 1a: Infrastructure Existence
──────────────────────────────────────────────

═ Verifying resource group: dnsmig-rg-onprem
✓ Resource group exists
═ Checking DNS Server VM...
✓ DNS Server VM exists (state: VM running)
═ Checking Client VM...
✓ Client VM exists (state: VM running)

Phase 1b: Provisioning State
──────────────────────────────────────────────

═ DNS Server provisioning state: Succeeded
✓ DNS Server fully provisioned
═ Client VM provisioning state: Succeeded
✓ Client VM fully provisioned

Phase 1c: Network Configuration
──────────────────────────────────────────────

═ DNS Server Private IP: 10.10.1.10
═ Client VM Private IP: 10.10.1.20
✓ DNS Server Public IP: [public-ip]
✓ Client VM Public IP: [public-ip]

Phase 1d: Connectivity Tests
──────────────────────────────────────────────

═ Testing DNS Server internal connectivity...
✓ DNS Server responding via Azure run-command
═ Testing Client VM internal connectivity...
✓ Client VM responding via Azure run-command
═ Testing network connectivity between VMs...
✓ Client can reach DNS Server (10.10.1.10)
═ Testing internet connectivity (DNS Server)...
✓ DNS Server has internet connectivity via NAT Gateway
═ Testing internet connectivity (Client VM)...
✓ Client VM has internet connectivity via NAT Gateway
```

## Phase 1 Success Criteria

✅ Resource group created  
✅ Both VMs in "Succeeded" provisioning state  
✅ Public IPs assigned to both VMs  
✅ VMs can reach each other (10.10.1.10 ↔ 10.10.1.20)  
✅ Both VMs have internet connectivity (can ping 8.8.8.8)  
✅ Cloud-init completed without errors  

## Manual Testing (Optional)

### SSH to DNS Server

```bash
# Get public IP from deployment output
ssh azureuser@<public-ip>

# Check system info
hostname
uname -a
uptime

# Check cloud-init status
cloud-init status
sudo journalctl -u cloud-init -n 20
```

### SSH to Client VM

```bash
# Get public IP from deployment output
ssh azureuser@<public-ip>

# Check system info
hostname
ifconfig  # or ip addr

# Test internet connectivity
ping 8.8.8.8
curl -I https://www.google.com
```

### Test Inter-VM Connectivity

```bash
# From client VM, test reaching DNS server
ping 10.10.1.10
curl telnet 10.10.1.10 53  # Will fail (no service listening yet) but proves network works
```

## Troubleshooting Phase 1

### Deployment Fails

```powershell
# Check prerequisites
az account show
bicep --version

# Review deployment status
az deployment group list -g dnsmig-rg-onprem -o table

# Get detailed error information
az deployment group show -g dnsmig-rg-onprem -n [deployment-name] -o json | jq '.properties.error'
```

### VMs Not Accessible

```powershell
# Check if VMs exist
az vm list -g dnsmig-rg-onprem -o table

# Check VM details
az vm show -d -g dnsmig-rg-onprem -n dnsmig-onprem-vm-dns -o table

# Check network interfaces
az network nic list -g dnsmig-rg-onprem -o table

# Check NSG rules
az network nsg rule list -g dnsmig-rg-onprem --nsg-name dnsmig-onprem-nsg -o table
```

### Internet Connectivity Failing

```powershell
# Check NAT Gateway
az network nat list -g dnsmig-rg-onprem -o table

# Check Public IP
az network public-ip list -g dnsmig-rg-onprem -o table

# Get NAT Gateway Public IP (should match in VM tests)
az network public-ip show -g dnsmig-rg-onprem -n dnsmig-onprem-nat-pip --query ipAddress
```

### Public IPs Not Assigned

This is normal for new deployments. Wait 2-3 minutes and check again:

```powershell
./scripts/phase1/02-verify-network.ps1 -ResourceGroupName dnsmig-rg-onprem
```

## Next Phase

Once Phase 1 is verified, proceed to **Phase 2: DNS Server Configuration**:

```powershell
./scripts/phase2/03-configure-dns-server.ps1 `
  -ResourceGroupName dnsmig-rg-onprem `
  -DnsServerVmName dnsmig-onprem-vm-dns `
  -DnsServerIp 10.10.1.10 `
  -Verbose
```

Phase 2 will:

- Install dnsmasq on the DNS server
- Create the `onprem.pvt` zone  
- Add local host entries
- Verify DNS service is running

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│ Resource Group: dnsmig-rg-onprem                   │
│                                                     │
│  ┌────────────────────────────────────────┐        │
│  │ VNet: 10.10.0.0/16                     │        │
│  │                                        │        │
│  │  ┌──────────────────────────────────┐ │        │
│  │  │ Subnet: 10.10.1.0/24             │ │        │
│  │  │                                  │ │        │
│  │  │  ┌──────────────────────────┐   │ │        │
│  │  │  │ DNS Server VM            │   │ │        │
│  │  │  │ (dnsmig-onprem-vm-dns)   │   │ │        │
│  │  │  │ 10.10.1.10               │   │ │        │
│  │  │  │ - Ubuntu 22.04           │   │ │        │
│  │  │  │ - Cloud-init ready       │   │ │        │
│  │  │  └──────────────────────────┘   │ │        │
│  │  │                                  │ │        │
│  │  │  ┌──────────────────────────┐   │ │        │
│  │  │  │ Client VM                │   │ │        │
│  │  │  │ (dnsmig-onprem-vm-client)│   │ │        │
│  │  │  │ 10.10.1.20               │   │ │        │
│  │  │  │ - Ubuntu 22.04           │   │ │        │
│  │  │  │ - Cloud-init ready       │   │ │        │
│  │  │  └──────────────────────────┘   │ │        │
│  │  │                                  │ │        │
│  │  └──────────────────────────────────┘ │        │
│  │  NSG: Allow SSH + DNS                  │        │
│  └────────────────────────────────────────┘        │
│                                                     │
│  NAT Gateway: dnsmig-onprem-nat                    │
│  └─ Public IP: [auto-assigned]                    │
│      (Provides outbound internet for both VMs)    │
└─────────────────────────────────────────────────────┘
```

## References

- [RUNBOOK.md](../RUNBOOK.md) - Complete 5-phase runbook
- [Azure Virtual Networks](https://learn.microsoft.com/en-us/azure/virtual-network/)
- [NAT Gateway](https://learn.microsoft.com/en-us/azure/virtual-network/nat-gateway/)
- [Network Security Groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
