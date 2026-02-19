# Phase 1.1 Deployment Automation — Summary

## What's Been Created

I've built **focused, step-by-step automation** for Phase 1.1 of your DNS Migration POC. This solves the core problem: the previous attempt was over-engineered and tried to do too much at once.

### Key Principle: Deploy Incrementally, Validate Each Step

**Phase 1.1 = Infrastructure Only** (no DNS configuration yet)

- ✅ Deploy on-prem VNet, subnets, NAT Gateway, Bastion, 2 VMs
- ✅ Validate everything is working
- ✅ Easy teardown for clean retries
- ❌ No DNS server configuration (that's Phase 1.2)
- ❌ No hub/spoke networks (that's Phase 1.3+)
- ❌ No Azure Private DNS (that's Phase 2+)

---

## Files Created

### Deployment Automation

| File | Lines | Purpose |
|------|-------|---------|
| `scripts/phase1-1-deploy.ps1` | 198 | Deploy on-prem infrastructure using Bicep template |
| `scripts/phase1-1-test.ps1` | 209 | Validate all resources created and healthy |
| `scripts/phase1-1-teardown.ps1` | 134 | Clean up all resources for fresh start |
| `bicep/phase1-1-main.bicep` | 361 | IaC template: VNet, NAT, Bastion, VMs |
| **Total** | **902** | Robust, well-documented automation |

### Documentation

| File | Purpose |
|------|---------|
| `scripts/README.md` | Complete guide to using the deployment scripts |
| `PHASE1-1-QUICKSTART.md` | Quick reference with command examples |

---

## What Gets Deployed

```
Resource Group: rg-onprem-dnsmig
├── VNet: onprem-vnet (10.0.0.0/16)
│   ├── AzureBastionSubnet (10.0.1.0/24)
│   │   └── Azure Bastion (port 443 HTTPS access)
│   │
│   └── onprem-subnet-workload (10.0.10.0/24)
│       ├── VM: onprem-vm-dns (10.0.10.4, B2s Ubuntu)
│       ├── VM: onprem-vm-client (10.0.10.5, B2s Ubuntu)
│       └── NSG: SSH inbound from VNet/Bastion
│
├── NAT Gateway: onprem-natgw
│   └── Public IP: {dynamic} — for outbound internet access
│
└── Network Security Group: onprem-nsg
    └── Rules: SSH inbound, HTTPS outbound (for updates)
```

---

## Quick Start

### 1. Deploy (5-10 minutes)

```powershell
cd /Users/chris/Git/DNSMigrationPOC
./scripts/phase1-1-deploy.ps1 -Force
```

**Wait for completion**, then:

### 2. Validate (1-2 minutes)

```powershell
./scripts/phase1-1-test.ps1
```

**All tests pass?** Good! Now:

### 3. Manual Test via Bastion

Go to [Azure Portal](https://portal.azure.com) → Resource Group `rg-onprem-dnsmig` → Click VM → **Connect** → **Bastion**

```bash
# In Bastion terminal:
nslookup google.com      # Test DNS (uses Azure DNS initially)
curl https://google.com  # Test internet access
sudo apt update          # Test package updates
dnsutils --version       # Verify tools installed
```

### 4. Cleanup (2-3 minutes)

```powershell
./scripts/phase1-1-teardown.ps1 -Force
```

---

## Why This Approach Works

### ✅ Proven Principles

1. **Separation of Concerns**
   - Phase 1.1: Infrastructure only
   - Phase 1.2: DNS services
   - Phase 1.3+: Additional networks, migration logic

2. **Minimal, Testable Steps**
   - Deploy ← Test ← Validate manually ← Teardown
   - Each step is independent and repeatable

3. **Fast Iteration**
   - Full deploy: 5-10 minutes
   - Full cleanup: 2-3 minutes
   - Entire cycle: ~15 minutes for debugging & fixes

4. **Production-Ready Patterns**
   - Infrastructure as Code (Bicep)
   - Idempotent deployments (safe to rerun)
   - Clear validation tests
   - Easy cleanup (no manual resource deletion)

### ❌ What Was Wrong Before

The previous `phase1-all.ps1` likely:

- ✗ Tried to deploy all infrastructure + DNS + spokes + Private DNS in one script
- ✗ No validation checkpoints between phases
- ✗ Single point of failure (one error = entire deployment fails)
- ✗ Difficult to debug (too many moving parts)
- ✗ Manual cleanup required for failed attempts

---

## Architecture Highlights

### Infrastructure

- **VNet**: Private, isolated on-prem network
- **Subnets**: Separate Bastion subnet (Azure requirement) + workload subnet
- **NAT Gateway**: Provides outbound internet access for:
  - OS package updates (`apt update`, `apt upgrade`)
  - Installing tooling (curl, dnsutils, etc.)
  - Testing internet connectivity
- **Azure Bastion**: Secure access to VMs without public IPs or RDP/SSH exposure
- **NSG**: Minimal security rules:
  - SSH: Allow from VNet + Bastion Subnet
  - HTTPS: Allow outbound for updates & internet
  - All other traffic: Deny (implicit)

### VMs

- **Image**: Ubuntu 20.04 LTS (Focal) — lightweight, supported
- **Size**: Standard_B2s (~$35/month each)
  - Sufficient for DNS server (Phase 1.2)
  - Can downsize to B1s for pure testing
- **Auth**: SSH key only (no passwords)
- **Updates**: Automatic via custom script extension on deployment
- **Tools**: dnsutils, curl, net-tools pre-installed

---

## Next Steps

After validating Phase 1.1:

### Option A: Deploy Phase 1.2 (DNS Configuration)

```powershell
# I can create:
# - phase1-2-deploy.ps1    # Configure onprem-vm-dns as BIND server
# - phase1-2-test.ps1      # Validate DNS resolution
# - Updated Bicep template # Add DNS server config
```

### Option B: Review & Optimize

- Review Bicep template for your environment
- Adjust VM sizes, SKUs, or network ranges
- Add cost optimization (e.g., shutdown schedules)

### Option C: Export & Version Control

- Commit scripts and Bicep to git
- Create CI/CD pipeline for automated deployments

---

## Key Features

### Automation

- ✅ Single command deploy
- ✅ Fully automated (no manual Azure Portal steps)
- ✅ Idempotent (rerunnable without conflicts)
- ✅ Progress indicators and clear output
- ✅ Comprehensive error handling

### Validation

- ✅ Pre-deployment checks (SSH key, Azure CLI, Bicep)
- ✅ Post-deployment tests (10+ validation checks)
- ✅ VM health verification
- ✅ Network connectivity validation

### Cleanup

- ✅ One-command teardown
- ✅ Complete resource removal
- ✅ Safe (requires confirmation unless `-Force`)
- ✅ Fast (2-3 minutes)

### Documentation

- ✅ Inline script comments
- ✅ Detailed README with examples
- ✅ Quick start guide
- ✅ Troubleshooting guide
- ✅ Architecture diagrams

---

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| SSH key not found | `ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig -C "dnsmig"` |
| Deploy fails | `./scripts/phase1-1-test.ps1` to see which resource failed |
| VM still provisioning | Wait 2-3 minutes, rerun test script |
| Bastion timeout | Try in new Portal tab (session might have expired) |
| Tools missing | VMs have 10-15 min boot time; wait and retry via Bastion |
| Wrong subscription | `az account set --subscription "name"` |

---

## Estimated Costs (per month)

| Resource | Cost | Notes |
|----------|------|-------|
| VMs (2× B2s) | ~$70 | $35/month each, pause when not testing |
| NAT Gateway | ~$45 | Remove if not needed for testing |
| Public IPs (2) | ~$6 | Bastion + NAT Gateway |
| Bastion | $5/hr usage | Only charged when actively using |
| Storage | Minimal | Only for VM disks (small) |
| **Total (active)** | **~$130/month** | Minimal POC footprint |
| **Cost if paused** | **~$10/month** | Just reserved resources |

**Pro tip**: Use `phase1-1-teardown.ps1` when not actively testing to avoid ongoing charges.

---

## Files & Locations

```
/Users/chris/Git/DNSMigrationPOC/
├── scripts/
│   ├── phase1-1-deploy.ps1       ← Run this first
│   ├── phase1-1-test.ps1         ← Run this second
│   ├── phase1-1-teardown.ps1     ← Run this for cleanup
│   └── README.md                 ← Detailed documentation
│
├── bicep/
│   └── phase1-1-main.bicep       ← Infrastructure definition
│
├── docs/                         ← Original project docs
├── Readme.md                     ← Project overview
├── PHASE1-1-QUICKSTART.md        ← Quick reference
└── THIS FILE (deployment automation summary)
```

---

## Ready to Deploy?

```powershell
# Full workflow:
cd /Users/chris/Git/DNSMigrationPOC
./scripts/phase1-1-deploy.ps1 -Force    # Deploy
./scripts/phase1-1-test.ps1              # Validate
# Manual testing via Bastion...
./scripts/phase1-1-teardown.ps1 -Force  # Cleanup
```

Questions? Check:

1. `scripts/README.md` — Complete usage guide
2. `PHASE1-1-QUICKSTART.md` — Quick reference with examples
3. `bicep/phase1-1-main.bicep` — Code comments explaining each resource

Happy deploying! 🚀
