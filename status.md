# Current Status

Date: 2026-02-20

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
- `status.md` - This file

## Summary of Phase 1.2 Fixes

Total issues resolved today: **6**

1. ✓ Missing `--file` flag in bicep build command
2. ✓ Az PowerShell module loading
3. ✓ Pattern matching with `-like` instead of `-notmatch`
4. ✓ PowerShell escaping in double-quoted here-strings
5. ✓ VM restart check using proper JMESPath query
6. ✓ Boolean conversion in test script -match operations

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

## Next Action

Ready to proceed to **Phase 1.3** - Hub VNet deployment.
