# Current Status

Date: 2026-02-20

## ✅ Phase 1 - COMPLETE (Multi-Resource-Group Infrastructure)

**Deployment Date:** 2026-02-20  
**Status:** All tests passed

### What Was Deployed

**Architecture:** Multi-resource-group deployment using subscription-level Bicep orchestrator with modules

**Resource Groups:**

- **rg-onprem-dnsmig:** On-prem environment resources
- **rg-hub-dnsmig:** Hub environment resources

**Infrastructure:**

- 2 VNets (10.0.0.0/16 and 10.1.0.0/16) - isolated, no peering
- 4 VMs with Bastion access
- Azure DNS (168.63.129.16) configured on all VMs
- Internet connectivity via NAT Gateways
- All VMs running and accessible

**Test Results:** ✓ All 26+ tests passed

- Resource groups created
- VNets deployed with correct address spaces
- All VMs running with correct IPs
- Azure DNS properly configured
- Internet connectivity verified
- No VNet peering (as expected for Phase 1)
- Bastions deployed and accessible

### Scripts Created

- `scripts/phase1-deploy.ps1` - Subscription-level deployment
- `scripts/phase1-test.ps1` - Infrastructure validation
- `bicep/phase1-main.bicep` - Subscription orchestrator
- `bicep/modules/onprem-infrastructure.bicep` - On-prem module
- `bicep/modules/hub-infrastructure.bicep` - Hub module

---

## ✅ Phase 2 - COMPLETE (VNet Peering)

**Deployment Date:** 2026-02-20  
**Status:** All tests passed

### What Was Deployed

**Goal:** Establish bidirectional VNet peering between on-prem and hub

**Changes:**

- Created hub-to-onprem peering (VNet access + forwarded traffic enabled)
- Created onprem-to-hub peering (VNet access + forwarded traffic enabled)
- Enabled cross-VNet connectivity between all VMs

**Test Results:** ✓ All tests passed

- Peering exists and is "Connected" in both directions
- Cross-VNet ping tests successful (OnPrem ↔ Hub)
- Internet connectivity still works post-peering

### Scripts Used

- `scripts/phase2-deploy.ps1` - VNet peering deployment
- `scripts/phase2-test.ps1` - Peering validation

---

## ✅ Phase 3 - COMPLETE (On-Prem DNS Configuration)

**Deployment Date:** 2026-02-20  
**Status:** All tests passed

### What Was Deployed

**Goal:** Configure BIND9 DNS server on on-prem VM (without activating it)

**Changes:**

- Installed BIND9 on onprem-vm-dns (10.0.10.4)
- Configured onprem.pvt authoritative zone
- Added DNS records: dns.onprem.pvt, client.onprem.pvt, ns1.onprem.pvt
- Configured forwarding to Azure DNS (168.63.129.16) for internet names
- **VNet DNS settings remain unchanged** (still using Azure DNS)

**Test Results:** ✓ All tests passed

- BIND9 installed and running
- Zone file validates correctly
- DNS records resolve when queried directly
- Forwarding to Azure DNS works for internet names
- VNet/VMs still use Azure DNS (custom DNS not active yet)

### Scripts Used

- `scripts/phase3-deploy.ps1` - On-prem DNS configuration
- `scripts/phase3-test.ps1` - DNS validation

---

## ✅ Phase 4 - COMPLETE (On-Prem DNS Cutover)

**Deployment Date:** 2026-02-20  
**Status:** All tests passed

### What Was Deployed

**Goal:** Activate custom DNS for on-prem VNet (cutover from Azure DNS)

**Changes:**

- Updated On-Prem VNet DNS settings to 10.0.10.4 (onprem-vm-dns)
- Restarted VMs to acquire new DNS settings via DHCP
- VMs now use custom DNS for all resolution
- **Custom DNS is now active for On-Prem VNet**

**Test Results:** ✓ All tests passed

- VNet DNS configuration updated to 10.0.10.4
- VMs acquired custom DNS via DHCP (verified with resolvectl status)
- VMs resolve onprem.pvt records using custom DNS server
- Internet names still work via forwarding to Azure DNS
- DNS port 53 accessible from all VMs
- VNet fully operational with custom DNS

### Scripts Used

- `scripts/phase4-deploy.ps1` - DNS cutover deployment
- `scripts/phase4-test.ps1` - Cutover validation (fixed IPv6 regex)

---

## Previous Work Notes

## Phase 1.1 - Ready for Clean Rebuild

### Recent Script Fixes (2026-02-20)

**Issue Found:** Deployment script errors at multiple steps

**Root Causes Identified & Fixed:**

1. **Bicep Validation Command** (scripts/phase1-1-deploy.ps1, line 125)
   - **Problem:** Missing required `--file` flag in `az bicep build` command
   - **Error:** "the following arguments are required: --file/-f"
   - **Fix:** Changed from `az bicep build $BicepTemplatePath` to `az bicep build --file $BicepTemplatePath`
   - **Result:** ✓ Bicep template now validates correctly

2. **Az PowerShell Module Loading** (scripts/phase1-1-deploy.ps1, lines 54-63)
   - **Problem:** Script uses `New-AzResourceGroupDeployment` but doesn't import Az modules
   - **Fix:** Added explicit module imports:

     ```powershell
     Import-Module Az.Accounts -ErrorAction SilentlyContinue
     Import-Module Az.Resources -ErrorAction SilentlyContinue
     ```

   - **Result:** ✓ Deployment cmdlets now available

## Phase 1.2 - Configuration Writing Fixed

### Previous Issues (from 2026-02-19) - RESOLVED

- **Issue 1**: Race condition between BIND restart and DNS validation test ✓
- **Issue 2**: systemctl using wrong service name (bind9 vs named) ✓
- **Issue 3**: Reboot sequence causing client VM to hang ✓
- **Issue 4**: PowerShell parser errors with query parameters ✓

### New Issue Found & Fixed (2026-02-20)

**Issue: BIND Configuration Files Not Written**

**Problem:** `az vm run-command invoke` configuration writing failed

- Manual VM inspection showed BIND9 installed correctly
- But zone file `/etc/bind/db.onprem.pvt` did not exist
- Config files were default installation files (dated Sep 2024)
- Error: "named-checkconf: command not found" (PATH issue in remote execution)

**Root Causes:**

1. Base64 strings passed as command arguments may have been too long
2. PATH not set correctly in `az vm run-command` environment
3. Heredoc approach had double-escaping issues (PowerShell → Bash)

**Fix Applied:** Base64 + Temp Files (Hybrid Approach)

- **Method:** Write base64 to temp files on VM, then decode to final location
- **Benefits:**
  - ✅ No escaping issues (base64 is opaque)
  - ✅ No command-line length limits (uses temp files)
  - ✅ Readable content in PowerShell
  - ✅ Single remote command for all files
  - ✅ Explicit PATH setting for BIND commands
- **Implementation:**

  ```bash
  # Write to temp file
  echo '$base64content' > /tmp/file.b64
  base64 -d /tmp/file.b64 | sudo tee /etc/bind/config
  rm /tmp/file.b64
  ```

- **Result:** ✓ Reliable configuration file writing

**Additional Fixes:**

- Absolute paths for all BIND commands (`/usr/sbin/named-checkconf`, `/usr/bin/dig`)
- Explicit PATH export in bash scripts
- Better error messages with full output on failure
- Service name confirmed as `named` (not `bind9`)

## Current Plan - Full Rebuild (IN PROGRESS)

**Strategy:** Teardown and rebuild from scratch to validate complete automation

**Status:** Phase 1.1 ✓ | Phase 1.2 - Debugging validation script

### Rebuild Attempt - Additional Issues Found (2026-02-20)

**Issue 3: Pattern Matching in Validation Checks**

- **Problem:** Script validation failing even though operations succeeded
- **Error:** "BIND installation did not complete successfully" despite seeing "BIND installation complete" in output
- **Root Cause:** Using `-notmatch` regex operator which failed with Azure CLI's formatted output containing `[stdout]` and `[stderr]` markers
- **Fix:** Changed to `-like '*string*'` wildcard matching (more robust for substring checks)
- **Lines Changed:**
  - Line ~165: `if (-not ($installOutput -like '*BIND installation complete*'))`
  - Line ~212: `if ($LASTEXITCODE -ne 0 -or -not ($configOutput -like '*successfully*'))`
- **Result:** ✓ Validation now correctly identifies success messages

**Issue 4: PowerShell Escaping in Double-Quoted Here-Strings**

- **Problem:** Bash syntax error in validation script
- **Error:** `/var/lib/waagent/run-command/download/3/script.sh: line 4: export: 'Running named-checkconf...': not a valid identifier`
- **Root Cause:** Used `\$PATH` (bash escape) in PowerShell double-quoted here-string `@"..."@`
  - The backslash was treated as a bash line continuation character
  - Made the next echo statement part of the export command
- **Fix:** Changed `\`$PATH` to `` `$PATH `` (correct PowerShell escaping for double-quoted strings)
- **Lines Changed:**
  - Config script (line ~178): `export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH`
  - Validation script (line ~222): `export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH`
- **Note:** Install script uses single-quoted here-string `@'...'@`, so `$PATH` without escape is correct there
- **Result:** ✓ Bash scripts now have correct syntax

**Issue 5: VM Restart Check Logic**

- **Problem:** VM restart timeout after 60 attempts (120 seconds)
- **Error:** "onprem-vm-dns failed to restart within timeout period"
- **Root Cause:** JMESPath query returned array `["PowerState/running"]` instead of string
  - Check `$vmState.powerState -like '*running*'` compared against array object, always failed
  - VM was actually running but check never detected it
- **Original Query:**

  ```powershell
  --query "{powerState:instanceView.statuses[?starts_with(code, 'powerState')].code, provisioningState:provisioningState}" -o json
  ```

- **Fix:** Simplified query to extract first PowerState code as plain text (TSV)

  ```powershell
  --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" -o tsv
  if ($vmState -eq 'PowerState/running')
  ```

- **Lines Changed:**
  - DNS VM check (line ~293): TSV output + direct string comparison
  - Client VM check (line ~325): Same fix for consistency
- **Result:** ✓ VM restart detection now works correctly

**Phase 1.2 Deployment Status:** ✓ **COMPLETED** - Deployment script finished without errors

**Issue 6: Boolean Conversion in Test Script**

- **Problem:** Test script failed on line 96 with type conversion error
- **Error:**

  ```
  Cannot process argument transformation on parameter 'Success'. Cannot convert value "System.Object[]" to type
  "System.Boolean". Boolean parameters accept only Boolean values and numbers, such as $True, $False, 1 or 0.
  ```

- **Root Cause:** `-match` operator returns array of matching items when applied to array input
  - `az vm run-command invoke --query 'value[0].message' -o tsv` can return multiline output
  - PowerShell treats multiline output as array
  - `$array -match 'pattern'` returns matching items (array), not boolean
  - Test-Result function expects `[bool]` parameter
- **Affected Lines:**
  - Line 96: `$bindActive = $bindStatus -match 'active'`
  - Line 112: `$resolved = $resolveOutput -match '\b\d{1,3}(\.\d{1,3}){3}\b'`
- **Fix:** Explicit boolean cast using `[bool]()` wrapper

  ```powershell
  $bindActive = [bool]($bindStatus -match 'active')
  $resolved = [bool]($resolveOutput -match '\b\d{1,3}(\.\d{1,3}){3}\b')
  ```

- **Result:** ✓ Test script now properly converts match results to boolean

### Escaping Reference for Future Fixes

**PowerShell Here-String Types:**

```powershell
# Single-quoted (no expansion) - use for pure bash scripts
$script = @'
export PATH=$PATH  # No escaping needed, PowerShell doesn't expand
'@

# Double-quoted (expansion enabled) - escape with backtick
$script = @"
export PATH=`$PATH  # Backtick escapes the dollar sign
echo "$variable"    # This WILL expand from PowerShell scope
"@
```

## Files Modified Today

- `scripts/phase1-1-deploy.ps1` - Bicep validation fix, Az module imports
- `scripts/phase1-2-deploy.ps1` - Base64+temp file config writing, absolute paths, pattern matching fixes, PowerShell escaping fixes, VM restart check logic fix
- `scripts/phase1-2-test.ps1` - Boolean conversion fix for -match operator results
- `archive/original-phases/` - **NEW** Archive folder with Phase 1.3 work and lessons learned
- `status.md` - This file (refactoring documentation)

## Summary of Issues Resolved

Total issues identified and resolved: **8**

1. ✓ Missing `--file` flag in bicep build command
2. ✓ Az PowerShell module loading
3. ✓ Pattern matching with `-like` instead of `-notmatch`
4. ✓ PowerShell escaping in double-quoted here-strings
5. ✓ VM restart check using proper JMESPath query
6. ✓ Boolean conversion in test script -match operations
7. ✓ Bicep cross-resource-group scope with modular script approach
8. ✓ DNS dependency deadlock - resolved via architecture refactor

**Key Learning:** Proper dependency ordering (Infrastructure → Connectivity → Configuration) is critical for reliable deployment automation.

**Progress:** Phase 1.2 deployment completed successfully. Test script fixed and ready to run.

## Phase 1.2 - ✅ COMPLETED

**Status:** All tests passed! Manual validation confirmed.

**Test Results:**

- ✓ VNet DNS configuration points to DNS VM
- ✓ BIND9 service running on DNS VM
- ✓ Name resolution working from client VM
- ✓ Manual validation: onprem.pvt zone resolution confirmed
- ✓ Manual validation: Internet DNS names resolving correctly

### Observation: systemd-resolved Behavior

**User Question:** Why does the client VM report localhost as the DNS server?

**Answer:** This is expected behavior for modern Ubuntu systems (18.04+):

- Ubuntu uses **systemd-resolved** by default, which creates a local stub resolver
- `/etc/resolv.conf` shows `nameserver 127.0.0.53` (localhost)
- The stub resolver forwards queries to the actual configured DNS servers
- Actual upstream DNS servers are configured via DHCP/netplan
- Check real DNS config with: `resolvectl status` or `systemd-resolve --status`

**Why this works:**

1. Azure DHCP provides the DNS VM IP to the client VM
2. systemd-resolved receives this configuration
3. Applications query 127.0.0.53 (stub resolver)
4. systemd-resolved forwards to the DNS VM (10.0.0.4 in this case)
5. DNS resolution works correctly end-to-end

This is not an issue - it's the standard Ubuntu DNS architecture working as intended.

## Phase 1.3 - ❌ ARCHIVED (DNS Dependency Issue)

**Status:** Phase 1.3 development revealed fundamental architectural issue requiring full refactor.

**Issue 8: DNS Dependency Deadlock**

- **Problem:** Hub deployment failed during VM provisioning
- **Error:** DNS resolution failures during deployment, VMs couldn't reach configured DNS server
- **Root Cause:** **Circular dependency in deployment order**
  - Hub VNet configured to use on-prem DNS (10.0.10.4) in Bicep template
  - VNet peering deployed in *separate script* (runs after Bicep)
  - Hub VMs deploy before peering exists
  - VMs can't reach on-prem DNS without peering
  - VM extensions and configurations fail due to DNS issues
- **Analysis:** This is an architectural problem, not a scripting bug
  - Can't configure DNS before network connectivity established
  - Infrastructure and configuration phases were interleaved incorrectly
  - Phases mixed concerns: network setup + DNS config + VM deployment
  
**Decision: Full Architecture Refactor**

After consultation, decided to refactor entire POC to fix dependency order issues:

### Why Refactor?

1. **Dependency Inversion:** Custom DNS configured before connectivity ready
2. **Tight Coupling:** Infrastructure deployment coupled with DNS configuration  
3. **Cross-VNet Dependencies:** Resources depending on unreachable services
4. **Phase Boundaries Wrong:** Mixed infrastructure, connectivity, and configuration

### New Architecture Principle: **Infrastructure → Connectivity → Configuration**

**Phase 1: Foundation Infrastructure**

- Deploy all VNets + VMs with **Azure DNS** (default - always works)
- No cross-VNet dependencies during deployment
- Focus: Working infrastructure with defaults

**Phase 2: Network Connectivity**  

- Establish all VNet peering
- Validate cross-VNet connectivity
- Focus: Network layer working

**Phase 3: On-Prem DNS Setup**

- Install BIND, configure zones
- VNets still use Azure DNS (servers ready but not active)
- Focus: DNS server configuration

**Phase 4: On-Prem DNS Cutover**

- Update VNet DNS settings to on-prem VM
- Test custom DNS resolution
- Focus: DNS transition

**Phase 5: Hub DNS Setup**

- Install BIND, configure zones, set up forwarding
- Hub VNet still uses Azure DNS
- Focus: Hub DNS server configuration

**Phase 6: Hub DNS Cutover**

- Update VNet DNS settings to hub VM
- Test end-to-end resolution
- Focus: Complete DNS architecture

### Benefits of New Approach

✅ **No deployment deadlocks** - infrastructure uses working defaults  
✅ **Atomic operations** - each phase independently deployable/testable  
✅ **Clear dependencies** - infrastructure before connectivity before config  
✅ **Easier debugging** - network issues separate from DNS issues  
✅ **Production pattern** - mirrors real-world deployment practices  
✅ **Incremental rollback** - can stop/revert at any phase boundary

### Archived Files

Phase 1.3 work has been preserved in `archive/original-phases/` for reference:

- `bicep/phase1-3-main.bicep` - Hub VNet template (with DNS dependency issue)
- `scripts/phase1-3-deploy.ps1` - Hub deployment script
- `scripts/phase1-3-setup-peering.ps1` - VNet peering script (reusable as-is)
- `scripts/phase1-3-test.ps1` - Hub validation tests
- `README.md` - Comprehensive lessons learned documentation

### Reusable Components

From original Phase 1-3 work, carrying forward:

- ✅ Peering script pattern (idempotent, separate from deployment)
- ✅ BIND configuration techniques (base64 + temp files)
- ✅ Test patterns and error handling
- ✅ Hub VNet structure (NSG rules, IP addressing, VM layout)
- ✅ All 7 issues/fixes documented during Phase 1.2

---

## 🔄 REFACTOR IN PROGRESS

**Current Work:** Redesigning phases with proper dependency ordering

### New Phase Structure

| Phase | Focus | Key Principle |
|-------|-------|---------------|
| Phase 1 | Infrastructure | Deploy with working defaults (Azure DNS) |
| Phase 2 | Connectivity | Establish peering, validate network |
| Phase 3 | On-Prem DNS Config | Configure server while VNet uses Azure DNS |
| Phase 4 | On-Prem DNS Cutover | Switch VNet to custom DNS |
| Phase 5 | Hub DNS Config | Configure server + forwarding |
| Phase 6 | Hub DNS Cutover | Complete custom DNS architecture |

### Status

- ✅ Refactoring plan approved
- ✅ Phase 1.3 work archived with lessons learned
- ✅ Documentation updated
- 🔄 Creating new Bicep templates
- ⏳ Creating new deployment scripts
- ⏳ Creating new test scripts

---

## Next Action

**Continue refactoring:**

1. Create consolidated infrastructure Bicep template (Phase 1)
2. Build Phase 1 deployment script
3. Test Phase 1 deployment
4. Continue through remaining phases
