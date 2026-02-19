# Phase 1.1 Quick Start Guide

## What I've Created

I've built focused, minimal automation for Phase 1.1 that **deploys only on-prem infrastructure** without attempting DNS configuration (which caused the previous overcomplicated script to fail).

### Files Added

```
/scripts/
  ├── phase1-1-deploy.ps1      # Main deployment script
  ├── phase1-1-test.ps1        # Validation tests
  ├── phase1-1-teardown.ps1    # Cleanup script
  └── README.md                # Detailed documentation

/bicep/
  └── phase1-1-main.bicep      # Infrastructure as Code template
```

---

## The Three-Command Workflow

### 1️⃣ Deploy (5-10 minutes)

```powershell
cd /Users/chris/Git/DNSMigrationPOC
./scripts/phase1-1-deploy.ps1 -Force
```

**What gets created:**

- Resource Group: `rg-onprem-dnsmig`
- VNet: `onprem-vnet` (10.0.0.0/16) with workload & Bastion subnets
- NAT Gateway: `onprem-natgw` (for OS updates via internet)
- Azure Bastion: `onprem-bastion` (for secure VM access)
- 2 Ubuntu VMs: `onprem-vm-dns` and `onprem-vm-client`
  - SSH key authentication (your `~/.ssh/dnsmig.pub` will be used)
  - Custom script extensions to update OS packages
  - DNS utilities pre-installed (`dnsutils`, `curl`, `net-tools`)

---

### 2️⃣ Validate (1-2 minutes)

```powershell
./scripts/phase1-1-test.ps1
```

**Tests performed:**

- ✓ Resource group exists
- ✓ VNet and all subnets created
- ✓ NAT Gateway deployed and associated
- ✓ Bastion online and accessible
- ✓ Both VMs created and running
- ✓ Network interfaces properly configured
- ✓ NSG rules correct

**Output:** PASS/FAIL summary and next steps

---

### 3️⃣ Manual Testing (via Azure Bastion)

Via [Azure Portal](https://portal.azure.com):

1. Navigate to Resource Group: `rg-onprem-dnsmig`
2. Click on `onprem-vm-dns` or `onprem-vm-client`
3. Click **Connect** → **Bastion** → **Use Bastion**
4. Run tests in the Bastion terminal:

```bash
# Test DNS resolution (currently using Azure DNS)
nslookup google.com
nslookup microsoft.com

# Test internet connectivity
curl https://www.google.com

# Check package updates are available
sudo apt update
sudo apt list --upgradable

# Verify utilities are installed
which dnsutils
which curl
```

---

### 4️⃣ Cleanup (2-3 minutes)

```powershell
./scripts/phase1-1-teardown.ps1 -Force
```

**Deletes:** All resources in `rg-onprem-dnsmig` resource group

⚠️ **This is permanent and cannot be undone.**

---

## Key Design Decisions

### ✅ Why This Approach Works

1. **Phase 1.1 Only**: No DNS configuration complexity. Just infrastructure.
2. **Azure Bastion**: Secure access to VMs without public IPs.
3. **NAT Gateway**: Outbound internet access for OS updates (required for any workload).
4. **Custom Script Extensions**: VMs auto-update on deployment.
5. **Idempotent**: Run deploy multiple times—resources update cleanly.
6. **Simple Teardown**: One command removes everything for clean retries.

### ❌ What's NOT Included (Yet)

- DNS server configuration (Phase 1.2)
- Hub VNet, spokes (Phase 1.3+)
- Azure Private DNS (Phase 2+)
- Storage accounts, Private Endpoints (later phases)

---

## Prerequisites

You already have everything needed:

```bash
✓ Azure CLI installed
✓ Azure subscription access (you're logged in)
✓ SSH keys available (~/.ssh/dnsmig.pub exists)
```

Optional but recommended:

```bash
# PowerShell 7+ for better output formatting
brew install powershell  # macOS
choco install powershell  # Windows
```

---

## Typical Use Cases

### First-Time Deploy & Test

```powershell
# 1. Deploy
./scripts/phase1-1-deploy.ps1 -Force

# 2. Wait for completion, then validate
./scripts/phase1-1-test.ps1

# 3. Manually test via Bastion (see instructions above)

# 4. If all is well, proceed to Phase 1.2 development
```

### Retry After Troubleshooting

```powershell
# Clean everything
./scripts/phase1-1-teardown.ps1 -Force

# Wait for deletion
Start-Sleep -Seconds 60

# Try again cleanly
./scripts/phase1-1-deploy.ps1 -Force
```

### Different Azure Region

```powershell
# Deploy to East US instead of Central US
./scripts/phase1-1-deploy.ps1 -Location eastus -Force
```

### Different SSH Key

```powershell
# Use a specific SSH key
./scripts/phase1-1-deploy.ps1 -SshPublicKeyPath ~/.ssh/mykey.pub -Force
```

---

## Expected Output

### Deploy Script Success

```
╔════════════════════════════════════════════════════════════╗
║  Phase 1.1 Deployment - On-Prem Infrastructure            ║
╚════════════════════════════════════════════════════════════╝

[1/5] Validating prerequisites...
✓ SSH public key loaded from: ~/.ssh/dnsmig.pub
✓ Bicep template found: ./bicep/phase1-1-main.bicep

[2/5] Setting Azure context...
✓ Using current subscription: abc123...

[3/5] Creating resource group: rg-onprem-dnsmig
✓ Resource group created/updated

[4/5] Validating Bicep template...
✓ Template is valid

[5/5] Deploying infrastructure (this may take 5-10 minutes)...

✓ Deployment completed successfully!

Deployment Outputs:
  vnetId: /subscriptions/.../resourceGroups/rg-onprem-dnsmig/providers/Microsoft.Network/virtualNetworks/onprem-vnet
  vnetName: onprem-vnet
  dnsVmPrivateIp: 10.0.10.4
  clientVmPrivateIp: 10.0.10.5
  bastionName: onprem-bastion
  natGatewayPublicIp: 20.45.123.45

Next Steps:
  1. Run validation tests: ./scripts/phase1-1-test.ps1
  2. Connect to VMs via Bastion in the Azure Portal
  3. When done, clean up with: ./scripts/phase1-1-teardown.ps1
```

### Test Script Success

```
╔════════════════════════════════════════════════════════════╗
║  Phase 1.1 Validation Tests - On-Prem Infrastructure      ║
╚════════════════════════════════════════════════════════════╝

─────────────────────────────────────────────────────────────
Resource Group Validation
─────────────────────────────────────────────────────────────

[TEST] Resource Group Exists
  ✓ PASS

[TEST] VNet Created (onprem-vnet)
  ✓ PASS

[TEST] NAT Gateway Created (onprem-natgw)
  ✓ PASS

... (all tests passing)

╔════════════════════════════════════════════════════════════╗
║  Test Summary                                              ║
╚════════════════════════════════════════════════════════════╝

Passed: 13
Failed: 0
Total:  13

All tests passed! ✓

Next Steps:
  1. Access VMs via Azure Bastion...
  2. Manual tests to run on VMs...
  3. When testing is complete, clean up...
```

---

## Troubleshooting

### ❌ "SSH public key not found"

```powershell
# Generate one
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig -C "dnsmig"

# Then deploy
./scripts/phase1-1-deploy.ps1 -Force
```

### ❌ "Deployment failed" or "Error BCP..." messages

```powershell
# Validate Bicep syntax
az bicep build --file ./bicep/phase1-1-main.bicep

# Check your Azure subscription
az account show

# Look at the detailed deployment error in Azure Portal
az deployment group list -g rg-onprem-dnsmig --query "[0].{name:name, state:properties.provisioningState, error:properties.error}" -o json
```

### ❌ "VM not found" in test script

This usually means the VMs are still provisioning. Wait 2-3 minutes and run the test again:

```powershell
./scripts/phase1-1-test.ps1
```

---

## Next: Phase 1.2

Once Phase 1.1 is validated and you're ready to configure DNS, I can create:

- `phase1-2-deploy.ps1` — Add DNS server configuration to on-prem-vm-dns
- `phase1-2-test.ps1` — Validate DNS server is responding correctly
- Updated Bicep to configure BIND DNS with `onprem.pvt` zone

Would you like me to proceed with Phase 1.2 automation once you've tested Phase 1.1?

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│  Azure Subscription                                     │
├─────────────────────────────────────────────────────────┤
│  Resource Group: rg-onprem-dnsmig                       │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  VNet: onprem-vnet (10.0.0.0/16)                 │  │
│  ├───────────────────┬───────────────────────────────┤  │
│  │AzureBastionSubnet │onprem-subnet-workload        │  │
│  │(10.0.1.0/24)      │(10.0.10.0/24)                │  │
│  │                   │                              │  │
│  │┌─────────────┐    │┌──────────────┐             │  │
│  ││   Bastion   │    ││ onprem-vm-dns│             │  │
│  ││ [Public IP] │    ││ 10.0.10.4    │             │  │
│  │└─────────────┘    │├──────────────┤             │  │
│  │                   ││ NSG: SSH OK  │             │  │
│  │                   │└──────────────┘             │  │
│  │                   │                              │  │
│  │                   │┌──────────────────┐         │  │
│  │                   ││onprem-vm-client  │         │  │
│  │                   ││ 10.0.10.5        │         │  │
│  │                   │├──────────────────┤         │  │
│  │                   ││ NSG: SSH OK      │         │  │
│  │                   │└──────────────────┘         │  │
│  │                   │       ▲                     │  │
│  │                   │       │                     │  │
│  │                   │    (NAT GW)                 │  │
│  │                   │   [Public IP]               │  │
│  │                   │   Outbound ─→ Internet      │  │
│  └───────────────────┴───────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘

Legend:
  ✓ VMs: Ubuntu 20.04 LTS, SSH key auth, B2s size
  ✓ NAT: All outbound traffic → Public IP
  ✓ Bastion: Secure non-SSH access via RDP/SSH
  ✓ NSG: Minimal rules (SSH inbound, HTTPS outbound)
```

---

Feel free to reach out with any questions or issues!
