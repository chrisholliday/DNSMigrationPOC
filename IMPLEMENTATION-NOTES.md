# DNS Migration POC - Simplified Phase 1 Implementation

**Date**: February 18, 2026  
**Status**: Ready for testing  
**Phase**: 1 - On-Prem Environment Only

## Summary of Changes

### What Was Done

I've restructured your DNS migration POC to take a phased, simplified approach. The goal is to validate core DNS functionality in isolation before scaling up to the full hub-and-spoke topology.

#### 1. ✅ Archived Existing Deployment Scripts

All previous scripts have been moved to `scripts-archive/`:

- `01-deploy-legacy.ps1` (complex multi-VNet deployment)
- `02-configure-dns-servers.ps1`
- `03-deploy-private-dns.ps1`
- `04-configure-legacy-forwarders.ps1`
- `05-migrate-spoke1.ps1`
- `06-migrate-spoke2.ps1`
- `teardown.ps1`
- `validate.ps1`

These can be restored later once Phase 1 is working reliably.

#### 2. ✅ Created Simplified Bicep Template: `simple-onprem.bicep`

**Single responsibility**: Deploy only the on-prem environment

**What it creates**:

```
Resource Group: dnsmig-rg-onprem
├── Virtual Network (10.10.0.0/16)
│   └── Subnet (10.10.1.0/24)
├── NAT Gateway (public outbound connectivity)
├── Network Security Group (SSH + DNS inbound)
├── DNS Server VM (Ubuntu 22.04, dnsmasq)
│   ├── Private IP: 10.10.1.10
│   ├── Cloud-init: Install dnsmasq, configure onprem.pvt zone
│   └── Automatic startup at deployment
└── Client VM (Ubuntu 22.04, testing tools)
    ├── Private IP: 10.10.1.20
    ├── Cloud-init: Install testing tools (curl, dig, nslookup)
    └── Configured to use DNS server at 10.10.1.10
```

**Key improvements over the original**:

- ✨ Single template file (not scattered across multiple modules)
- ✨ Cloud-init fully configured for dnsmasq in the template
- ✨ NAT Gateway for reliable outbound internet connectivity
- ✨ Proper security group rules for SSH and DNS
- ✨ Clear parameter structure for easy customization

#### 3. ✅ Created Deployment Script: `deploy-simple-onprem.ps1`

**Purpose**: Automated deployment with validation and user guidance

**Features**:

- ✓ Checks for Azure CLI and Bicep CLI
- ✓ Validates SSH key file before deployment
- ✓ Clear progress feedback
- ✓ Deployment via Azure subscription deployment scope
- ✓ Post-deployment summary with next steps
- ✓ SSH access commands for manual testing
- ✓ Helpful reference for DNS configuration

**Usage**:

```powershell
./scripts/deploy-simple-onprem.ps1 -SshPublicKeyPath ~/.ssh/id_rsa.pub
```

#### 4. ✅ Created Verification Script: `verify-dns.ps1`

**Purpose**: Comprehensive automated testing of DNS functionality

**Tests performed** (in order):

1. **Infrastructure Check**
   - Resource group existence
   - VM provisioning state
   - Private IP addresses

2. **DNS Server Tests**
   - dnsmasq service startup (with automatic retry)
   - Configuration file presence
   - Port 53 listening for DNS queries
   - Service logs

3. **DNS Query Tests (from DNS Server)**
   - Local domain: `onprem.pvt`
   - Local host: `onprem-dns.onprem.pvt`
   - Public DNS: `google.com`, `azure.microsoft.com`
   - Via direct server query (nslookup)

4. **Client VM Tests**
   - DNS configuration
   - DNS resolution from client VM
   - Public DNS queries via forwarding

5. **Internet Connectivity**
   - ICMP ping to 8.8.8.8
   - HTTPS GET to google.com
   - Validates outbound internet access

**Usage**:

```powershell
./scripts/verify-dns.ps1 -ResourceGroupName dnsmig-rg-onprem -Verbose
```

The `-Verbose` flag shows individual DNS query responses.

#### 5. ✅ Created Quick Start Guide: `QUICKSTART.md`

Complete walkthrough including:

- Prerequisites and installation
- Step-by-step deployment
- Verification procedure
- DNS configuration details
- Interactive testing commands
- Troubleshooting guide
- Cleanup instructions
- Path forward for scaling up

---

## Architecture Diagram

### Phase 1: On-Prem Only (Current)

```
┌──────────────────────────────────────────┐
│         Azure Subscription                │
├──────────────────────────────────────────┤
│                                          │
│  ┌─ dnsmig-rg-onprem ────────────────┐  │
│  │                                   │  │
│  │  10.10.0.0/16 [dnsmig-onprem-vnet]   │
│  │  ┌─────────────────────────────┐ │  │
│  │  │ 10.10.1.0/24 [snet-vms]     │ │  │
│  │  │                             │ │  │
│  │  │  [DNS Server]               │ │  │
│  │  │  10.10.1.10                 │ │  │
│  │  │  └─ dnsmasq                 │ │  │
│  │  │     ├─ onprem.pvt (local)  │ │  │
│  │  │     └─ forward to:         │ │  │
│  │  │        - 168.63.129.16 (Azure DNS)
│  │  │        - 8.8.8.8 (Google)  │ │  │
│  │  │                             │ │  │
│  │  │  [Client VM]                │ │  │
│  │  │  10.10.1.20                 │ │  │
│  │  │  └─ Tests DNS resolution   │ │  │
│  │  │     Tests internet access   │ │  │
│  │  │                             │ │  │
│  │  └─────────────────────────────┘ │  │
│  │                                   │  │
│  │  [NAT Gateway] ──> [Public IP]    │  │
│  │  └─ Outbound internet access      │  │
│  │                                   │  │
│  └───────────────────────────────────┘  │
│                                          │
└──────────────────────────────────────────┘
```

### Future Phase 2: Add Hub VNet

```
[On-Prem] ←→ [Hub] (DNS Resolver)
                │
                ├→ [Spoke1] (Storage + Private Endpoint)
                └→ [Spoke2] (Storage + Private Endpoint)
```

---

## Key Design Decisions

### 1. **Cloud-Init Configuration in Bicep**

- ✅ **Pro**: Everything in one file, easier to review and debug
- ✅ **Pro**: No separate configuration scripts needed
- ✅ **Pro**: Faster feedback loop - fix and redeploy
- ⚠️ **Con**: Base64 encoding makes it harder to read (but necessary)

### 2. **dnsmasq for DNS Server**

- ✅ **Pro**: Lightweight and easy to configure
- ✅ **Pro**: Built-in caching and forwarding
- ✅ **Pro**: Supports local zone hosting (onprem.pvt)
- ✅ **Pro**: Standard on Linux distributions

### 3. **Azure DNS (168.63.129.16) as Upstream**

- ✅ **Pro**: Authoritative for Azure resources
- ✅ **Pro**: No external dependency
- ⚠️ **Con**: Only works from within VNet (not from on-prem in production)
- 📝 **Note**: For hybrid scenarios, will need DNS Resolver in Phase 2

### 4. **Public DNS (8.8.8.8) as Backup**

- ✅ **Pro**: Reliable fallback
- ✅ **Pro**: Tests outbound internet connectivity
- ⚠️ **Con**: External dependency

### 5. **NAT Gateway for Internet**

- ✅ **Pro**: Works for all VMs automatically
- ✅ **Pro**: Single public IP for all outbound
- ✅ **Pro**: Better than public IPs on VMs
- ⚠️ **Con**: Small additional cost

---

## Testing Flow

```
1. Deploy Infrastructure
   ↓
2. Wait 2-3 min for cloud-init
   ↓
3. Run Verification Script (automated)
   ├→ Check infrastructure
   ├→ Check dnsmasq service
   ├→ Test DNS queries from DNS server
   ├→ Test DNS queries from client
   └→ Test internet connectivity
   ↓
4. Manual Testing (if needed)
   ├→ SSH to DNS server
   │  └→ View logs, test queries
   ├→ SSH to client VM
   │  └→ Test resolution, connectivity
   └→ Check dnsmasq config
   ↓
5. Once working:
   ├→ Add Phase 2 (Hub VNet + DNS Resolver)
   ├→ Add Phase 3 (Spoke VNets)
   ├→ Update in-scope original scripts based on learnings
   └→ Full deployment pipeline ready
```

---

## Files Structure

### New Files

```
DNSMigrationPOC/
├── bicep/
│   └── simple-onprem.bicep          [NEW] Simplified template
├── scripts/
│   ├── deploy-simple-onprem.ps1     [NEW] Deployment automation
│   └── verify-dns.ps1               [NEW] Verification suite
├── scripts-archive/                 [NEW] Archived old scripts
│   ├── 01-deploy-legacy.ps1
│   ├── 02-configure-dns-servers.ps1
│   └── ... (others)
└── QUICKSTART.md                    [NEW] Setup guide
```

### Modified Files

- None (backward compatible)

---

## Success Criteria for Phase 1

✓ When you can confirm all of the following, Phase 1 is complete:

1. **Deployment**: `deploy-simple-onprem.ps1` completes without errors
2. **Cloud-Init**: Both VMs complete cloud-init (2-3 minutes)
3. **DNS Server**: dnsmasq service is running and listening on port 53
4. **Local Resolution**: `nslookup onprem.pvt` returns `10.10.1.10`
5. **Client Resolution**: Client VM can resolve `onprem.pvt`
6. **Internet Access**: `ping 8.8.8.8` and `curl` work from both VMs
7. **Verification Script**: `verify-dns.ps1` passes all checks
8. **Logs**: No errors in dnsmasq logs

---

## Next Steps

Once Phase 1 is working reliably:

### Phase 2: Add Hub & DNS Resolver

- New Bicep template: `simple-hub.bicep`
- Create second VNet (10.20.0.0/16)
- Deploy DNS Resolver (inbound + outbound endpoints)
- Add VNet peering (on-prem ↔ hub)
- Test cross-VNet DNS resolution

### Phase 3: Add Spoke VNets

- New Bicep template: `simple-spokes.bicep`
- Create spoke VNets with test VMs
- Add peering to hub
- Test DNS from spokes

### Phase 4: Azure Private DNS

- Create Private DNS zones
- Link to VNets
- Test automatic record creation with storage private endpoints

### Phase 5: Migration Testing

- Validate cutover procedures
- Document DNS cutover steps
- Create rollback procedures

---

## Known Limitations

### Phase 1 Specific

1. ⚠️ Only on-prem local domain (`onprem.pvt`)
2. ⚠️ No hybrid DNS resolution yet (Hub comes in Phase 2)
3. ⚠️ No Private DNS zones yet
4. ⚠️ No DNS Resolver yet (comes in Phase 2)
5. 📝 May not represent all production considerations (security, high availability, etc.)

### To Address in Later Phases

- [ ] Multi-region deployment
- [ ] DNS failover scenarios
- [ ] Security hardening (NSG, private endpoints)
- [ ] Monitoring and alerting
- [ ] Backup/restore procedures
- [ ] Compliance and audit logging

---

## Quick Reference

### Deploy

```bash
./scripts/deploy-simple-onprem.ps1 -SshPublicKeyPath ~/.ssh/id_rsa.pub
```

### Verify

```bash
./scripts/verify-dns.ps1 -I dnsmig-rg-onprem -Verbose
```

### SSH to DNS Server

```bash
az ssh vm -g dnsmig-rg-onprem -n dnsmig-onprem-vm-dns --local-user azureuser
```

### SSH to Client

```bash
az ssh vm -g dnsmig-rg-onprem -n dnsmig-onprem-vm-client --local-user azureuser
```

### Cleanup

```bash
az group delete -n dnsmig-rg-onprem --yes --no-wait
```

---

**Ready to test!** 🚀

See `QUICKSTART.md` for detailed walkthrough.
