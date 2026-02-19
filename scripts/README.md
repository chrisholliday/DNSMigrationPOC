# Phase 1.1 Deployment Scripts

This directory contains the focused, minimal automation for deploying Phase 1.1 of the DNS Migration POC.

## Overview

**Phase 1.1 Goal**: Deploy on-prem VNet infrastructure with basic networking, VMs, Bastion, and NAT Gateway.

- No DNS configuration yet (that's Phase 1.2)
- Two Ubuntu VMs with SSH access
- Azure Bastion for secure VM access
- NAT Gateway for internet access (OS updates, package installation)

## Scripts

### 1. **phase1-1-deploy.ps1** — Deploy Phase 1.1

Deploys the complete on-prem infrastructure using the Bicep template.

**Prerequisites:**

- Azure CLI installed: <https://aka.ms/azure-cli>
- PowerShell 7+ (optional, but recommended for cross-platform compatibility)
- SSH public key (see below)
- Azure subscription with appropriate permissions

**SSH Key Setup:**

If you don't have an SSH key, generate one:

```bash
# macOS / Linux
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig -C "dnsmig"

# Windows PowerShell
ssh-keygen -t rsa -b 4096 -f $HOME\.ssh\dnsmig -C "dnsmig"
```

**Usage:**

```powershell
# Deploy with defaults (centralus region, uses ~/.ssh/id_rsa.pub or ~/.ssh/dnsmig.pub)
./phase1-1-deploy.ps1

# Deploy to different region
./phase1-1-deploy.ps1 -Location eastus

# Use specific SSH key
./phase1-1-deploy.ps1 -SshPublicKeyPath ~/.ssh/my-key.pub

# Skip confirmation prompts
./phase1-1-deploy.ps1 -Force
```

**What Gets Deployed:**

- Resource Group: `rg-onprem-dnsmig`
- VNet: `onprem-vnet` (10.0.0.0/16)
  - Workload Subnet: `onprem-subnet-workload` (10.0.10.0/24)
  - Bastion Subnet: `AzureBastionSubnet` (10.0.1.0/24)
- NAT Gateway: `onprem-natgw` + Public IP
- Azure Bastion: `onprem-bastion` (for secure VM access without public IPs)
- Network Security Group: `onprem-nsg`
- 2 Ubuntu VMs:
  - `onprem-vm-dns` (B2s, will host DNS later in Phase 1.2)
  - `onprem-vm-client` (B2s, for testing resolution)

**Typical Deployment Time:** 5-10 minutes

---

### 2. **phase1-1-test.ps1** — Validate Deployment

Runs automated tests to confirm all resources were deployed correctly and the VMs are healthy.

**Prerequisites:**

- `phase1-1-deploy.ps1` completed successfully
- Azure CLI must be available

**Usage:**

```powershell
# Run standard tests
./phase1-1-test.ps1

# With verbose output
./phase1-1-test.ps1 -VerboseOutput

# Against different resource group
./phase1-1-test.ps1 -ResourceGroupName my-rg
```

**Tests Performed:**

- ✓ Resource group exists
- ✓ VNet created (`onprem-vnet`)
- ✓ NAT Gateway created and configured
- ✓ Azure Bastion deployed
- ✓ Both VMs created (`onprem-vm-dns`, `onprem-vm-client`)
- ✓ Both VMs are in "running" state
- ✓ Network interfaces attached to VMs
- ✓ NSG configured for inbound SSH

**Output:**
The script reports pass/fail status for each test and provides next steps if all tests pass.

---

### 3. **phase1-1-teardown.ps1** — Cleanup

Deletes the entire `rg-onprem-dnsmig` resource group and all contained resources.

⚠️ **WARNING**: This is permanent and cannot be undone.

**Usage:**

```powershell
# Teardown with confirmation prompt
./phase1-1-teardown.ps1

# Teardown without confirmation (be careful!)
./phase1-1-teardown.ps1 -Force

# Teardown and wait for completion
./phase1-1-teardown.ps1 -Force -WaitForDeletion $true
```

**When to Use:**

- Between deployment attempts
- To start fresh after testing
- Cost cleanup when POC is complete

---

## Typical Workflow

### First Time Deployment

```powershell
# 1. Generate SSH key (if needed)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig -C "dnsmig"

# 2. Deploy Phase 1.1
./phase1-1-deploy.ps1 -Force

# 3. Verify everything worked
./phase1-1-test.ps1

# 4. Test manually via Bastion (see next section)
```

### Testing VMs Manually

After deployment completes, access VMs via Azure Bastion:

1. Go to Azure Portal
2. Navigate to Resource Group: `rg-onprem-dnsmig`
3. Click on `onprem-vm-dns` or `onprem-vm-client`
4. Click **Connect** → **Bastion** → **Open in new tab**
5. In the Bastion terminal, run tests:

```bash
# Test DNS resolution (will use Azure DNS initially)
nslookup google.com
nslookup microsoft.com

# Test internet connectivity via NAT Gateway
curl https://www.google.com

# Check for OS updates
sudo apt update
sudo apt list --upgradable

# Verify installed tools (custom script extensions)
which dnsutils
which curl
which net-tools
```

### Between Deployment Attempts

```powershell
# Clean up everything
./phase1-1-teardown.ps1 -Force

# Wait a minute for deletion to complete...
Start-Sleep -Seconds 60

# Deploy fresh
./phase1-1-deploy.ps1 -Force
```

---

## Troubleshooting

### SSH Key Not Found

```powershell
# Explicitly specify the path
./phase1-1-deploy.ps1 -SshPublicKeyPath ~/.ssh/dnsmig.pub

# Or generate and try again
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig -C "dnsmig"
```

### Deployment Fails

```powershell
# Check current Azure subscription
az account show

# Switch subscription if needed
az account set --subscription "My Subscription Name"

# Validate Bicep syntax
az bicep build-params ../bicep/phase1-1-main.bicep

# Check resource group state
az group show -n rg-onprem-dnsmig

# View recent deployments
az deployment group list -g rg-onprem-dnsmig -o table
```

### Tests Fail

Check Azure Portal for:

- VM provisioning status (Compute > Virtual machines > onprem-vm-dns / onprem-vm-client)
- Network interface status (Networking > Network interfaces)
- NSG rules (Networking > Network security groups > onprem-nsg)

If VMs are still provisioning, wait 2-3 minutes and re-run tests.

---

### 4. **phase1-2-deploy.ps1** — Configure On-Prem DNS

Configures the on-prem DNS VM (BIND), creates the `onprem.pvt` zone, and updates the VNet to use the DNS VM.

**Usage:**

```powershell
# Configure DNS using defaults
./phase1-2-deploy.ps1 -Force

# Use a different zone name
./phase1-2-deploy.ps1 -ZoneName corp.pvt -Force
```

**What It Does:**

- Installs `bind9` and DNS utilities on `onprem-vm-dns`
- Creates the `onprem.pvt` zone with basic A records
- Sets VNet DNS servers to the DNS VM private IP

---

### 5. **phase1-2-test.ps1** — Validate DNS Configuration

Validates that:

- VNet DNS servers point to the DNS VM
- BIND is running
- `dns.onprem.pvt` resolves from the client VM

**Usage:**

```powershell
./phase1-2-test.ps1
```

### Cannot Connect via Bastion

1. Verify Bastion is in "running" state: Portal > `onprem-bastion`
2. Check NSG allows SSH from Bastion Subnet (should be automatic)
3. Check VM network interface NSG rules
4. Try again in a new Portal tab if timeout occurs

---

## Architecture Notes

The Bicep template (`../bicep/phase1-1-main.bicep`) creates:

- **VNet** with two subnets:
  - **AzureBastionSubnet**: Required for Bastion deployment
  - **onprem-subnet-workload**: For VMs (associated with NAT Gateway)

- **NAT Gateway**: Provides outbound internet access for:
  - OS updates (`apt-get update/upgrade`)
  - Package installation
  - Public DNS queries
  - All outbound traffic originating from the subnet

- **Network Security Group**: Minimal rules:
  - Allow SSH from VNet and Bastion Subnet
  - Allow HTTP/HTTPS outbound (for updates and internet access)

- **VMs**: Ubuntu 20.04 LTS (focal)
  - SSH key authentication only (no passwords)
  - Custom script extensions to:
    - Update package lists (`apt-get update`)
    - Upgrade packages (`apt-get upgrade -y`)
    - Install DNS utilities (`dnsutils`)
    - Install network tools (`net-tools`, `curl`)

---

## Cost Optimization Tips

- **NAT Gateway**: ~$45/month per region. Consider removing for pure POC.
- **VMs**: Standard_B2s (~$35/month each). Use B1s for lighter testing.
- **Bastion**: ~$5/hour active use. Don't leave it deployed unused.
- **Public IPs**: Standard SKU charged for unused time. NAT Gateway + Bastion = 2 Public IPs (~$3/month each).

To reduce costs:

1. Deploy with `-Force` and `-NoNewline` to save a few seconds of compute
2. Use `phase1-1-teardown.ps1` when not actively testing
3. Consider VM size tuning (B1s instead of B2s for lighter workloads)

---

## Next Steps

After Phase 1.1 is validated:

- **Phase 1.2**: Configure on-prem DNS VM
- **Phase 1.3**: Deploy hub VNet infrastructure
- **Phase 1.4**: Configure hub DNS VM
- **Phase 1.5-1.6**: Add spoke networks and storage accounts
- **Phase 2+**: Azure Private DNS and migration

See [../docs/Deployment-Guide.md](../docs/Deployment-Guide.md) for the full plan.
