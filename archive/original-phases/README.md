# Original Phase Implementation - Archive

**Date Archived:** 2026-02-20

**Reason for Archive:** Refactoring to fix dependency order and improve modularity

## What's Archived Here

This folder contains the original Phase 1.1-1.3 implementation that was developed and partially deployed during initial POC development.

### Archived Files

**Bicep Templates:**

- `bicep/phase1-3-main.bicep` - Hub VNet infrastructure template

**Scripts:**

- `scripts/phase1-3-deploy.ps1` - Hub deployment script
- `scripts/phase1-3-setup-peering.ps1` - VNet peering setup script
- `scripts/phase1-3-test.ps1` - Hub validation tests

**Note:** Phase 1.1 and 1.2 files remain active as they successfully deployed and are working correctly.

---

## Why Refactor?

### Root Problem Identified

**DNS Dependency Deadlock:**

- Hub VNet was configured to use on-prem DNS (10.0.10.4) at deployment time
- VNet peering did not exist yet (separate script)
- Hub VMs could not reach on-prem DNS during deployment
- VM extensions and deployments failed due to DNS resolution issues

### Architectural Issues in Original Design

1. **Tight Coupling:** Infrastructure deployment coupled with DNS configuration
2. **Dependency Inversion:** DNS configured before network connectivity established
3. **Cross-VNet Dependencies:** Resources depending on other VNets before peering
4. **Mixed Concerns:** Network setup, DNS setup, and configuration in same phase

### Lessons Learned

#### ✅ What Worked Well

1. **Modular Scripts:** Separating peering into its own script was correct approach
2. **Base64 Configuration Technique:** Writing config files via base64+temp files worked perfectly
3. **Comprehensive Testing:** Test scripts caught issues early
4. **Error Handling Patterns:** Boolean casting, PATH handling, pattern matching fixes
5. **VM Configuration:** BIND installation and zone configuration scripts reliable
6. **Documentation:** Status tracking helped debug issues systematically

#### ❌ What Didn't Work

1. **DNS Before Connectivity:** Setting custom DNS before establishing peering
2. **Phase Boundaries:** Phases mixed infrastructure, connectivity, and configuration
3. **Deployment Atomicity:** Couldn't easily roll back or retry individual components
4. **Dependency Order:** Resources deployed before their dependencies were ready

---

## Issues Resolved During Original Development

### Issue 1-6: Phase 1.2 Issues (RESOLVED)

1. ✓ Missing `--file` flag in bicep build command
2. ✓ Az PowerShell module loading
3. ✓ Pattern matching with `-like` instead of `-notmatch`
4. ✓ PowerShell escaping in double-quoted here-strings
5. ✓ VM restart check using proper JMESPath query
6. ✓ Boolean conversion in test script -match operations

### Issue 7: Bicep Cross-Resource-Group Scope (RESOLVED)

- **Problem:** BCP165 error trying to create peering in different resource group
- **Solution:** Separated peering into dedicated script using Azure CLI
- **Learning:** Bicep files are scoped to single resource group, use scripts for cross-RG

### Issue 8: DNS Dependency Deadlock (Led to Refactor)

- **Problem:** Hub deployment failed because DNS pointed to unreachable on-prem server
- **Root Cause:** VNet peering didn't exist yet, DNS configured too early
- **Solution:** Full refactor to infrastructure-first approach

---

## New Architecture Approach

### Key Principle: **Infrastructure → Connectivity → Configuration**

**Phase 1: Foundation Infrastructure**

- All VNets + VMs deployed with **Azure DNS** (no dependencies)
- Everything works out-of-the-box with internet access

**Phase 2: Network Connectivity**

- VNet peering established
- Network connectivity validated

**Phase 3-6: DNS Configuration & Cutover**

- DNS servers configured while VNets still use Azure DNS
- DNS cutover happens only after servers are ready and accessible
- Incremental validation at each step

### Benefits of New Approach

1. **No Cross-VNet Dependencies During Deployment:** Each VNet deploys independently
2. **Work with Defaults First:** Azure DNS always works, custom DNS is enhancement
3. **Atomic Operations:** Each phase can be deployed, tested, rolled back independently
4. **Clear Dependency Order:** Infrastructure → Connectivity → Configuration
5. **Easier Troubleshooting:** Network issues separate from DNS issues
6. **Production-Ready Pattern:** Mirrors real-world deployment practices

---

## Reusable Components from Original Work

These patterns and techniques are being carried forward to the new implementation:

### Configuration Management

```powershell
# Base64 + temp file approach for reliable config writing
echo '$base64content' > /tmp/file.b64
base64 -d /tmp/file.b64 | sudo tee /etc/bind/config
rm /tmp/file.b64
```

### Error Handling

```powershell
# Boolean casting for -match results
$result = [bool]($output -match 'pattern')

# Pattern matching with wildcards
if ($output -like '*success*')

# Absolute paths for BIND commands
/usr/sbin/named-checkconf
```

### Testing Patterns

```powershell
function Test-Result {
    param([string]$Name, [bool]$Success, [string]$Message)
    # Consistent test output format
}
```

### Peering Setup

- Idempotent peering script (checks if exists before creating)
- Bidirectional peering in separate script is correct pattern
- Status verification after creation

---

## File Reference

### Successfully Deployed Components (Still Active)

- **Phase 1.1:** On-prem VNet, VMs, Bastion, NAT Gateway ✓
- **Phase 1.2:** On-prem DNS configuration (BIND + onprem.pvt zone) ✓

### Archived Components (Never Deployed)

- **Phase 1.3:** Hub VNet with on-prem DNS dependency ✗

---

## Migration Notes for Future Reference

If you need to reference the original Phase 1.3 design:

1. **Bicep Template Structure:** `bicep/phase1-3-main.bicep` shows hub VNet layout
2. **NSG Rules:** DNS port 53 allowed from on-prem is still needed
3. **IP Addressing:** 10.1.0.0/16 for hub (vs 10.0.0.0/16 for on-prem) is good pattern
4. **VM Naming:** hub-vm-dns and hub-vm-app naming convention maintained
5. **Peering Script:** `phase1-3-setup-peering.ps1` is solid and reusable as-is

---

## Timeline

- **2026-02-19:** Phase 1.1 and 1.2 development and debugging
- **2026-02-20:** Phase 1.2 completed successfully
- **2026-02-20:** Phase 1.3 development, discovered DNS dependency issue
- **2026-02-20:** Decided to refactor for cleaner architecture
- **2026-02-20:** Archived original Phase 1.3 work for reference

---

## Status at Time of Archive

- ✅ Phase 1.1: Deployed and working
- ✅ Phase 1.2: Deployed and working  
- ❌ Phase 1.3: Never deployed due to DNS dependency issue
- 🔄 Full refactor initiated

---

*This archive preserves valuable lessons learned and reusable components from the original implementation.*
