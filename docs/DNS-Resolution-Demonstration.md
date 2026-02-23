# DNS Resolution Demonstration Guide

## Purpose

This guide provides manual commands to demonstrate DNS name resolution at different phases of the migration POC. Use these commands to:

- Prove that name resolution is working correctly
- Identify which DNS server is authoritative for each zone
- Show the complete resolution chain for private endpoints
- Compare resolution behavior before and after migration (Phases 7 vs 9-10)

## Environment State by Phase

### Phase 7: Custom BIND9 DNS (Current State)

**DNS Architecture:**

- **On-prem DNS (10.0.10.4)**: Authoritative for `onprem.pvt`, forwards `azure.pvt` and blob zones to hub
- **Hub DNS (10.1.10.4)**: Authoritative for `azure.pvt`, `blob.core.windows.net`, `privatelink.blob.core.windows.net`
- **VM DNS Configuration**: All VMs use their local DNS server (10.0.10.4 for on-prem, 10.1.10.4 for hub/spoke)

**Zones and Records:**

- `onprem.pvt`: on-prem resources (web, dns, client VMs)
- `azure.pvt`: hub resources (web, dns, client VMs)
- `blob.core.windows.net`: CNAME records pointing to privatelink zone
- `privatelink.blob.core.windows.net`: A records with private endpoint IPs

### Phase 9: Hybrid DNS (Migration In Progress)

**DNS Architecture:**

- **Azure Private DNS**: Zones for `privatelink.blob.core.windows.net` (migrated from BIND9)
- **DNS Private Resolver**: Inbound endpoint for on-prem queries, outbound rules for forwarding
- **Hub DNS (BIND9)**: Still authoritative for `azure.pvt` and `blob.core.windows.net`
- **On-prem DNS (BIND9)**: Still authoritative for `onprem.pvt`

**What Changed:**

- Privatelink zone moved from BIND9 to Azure Private DNS
- Resolution still works via DNS Private Resolver inbound endpoint

### Phase 10: Full Azure Private DNS (Migration Complete)

**DNS Architecture:**

- **Azure Private DNS**: All zones (`onprem.pvt`, `azure.pvt`, `privatelink.blob.core.windows.net`)
- **DNS Private Resolver**: Handles all inbound queries from on-prem
- **BIND9 DNS Servers**: Decommissioned or read-only

**What Changed:**

- All zones migrated to Azure Private DNS
- Resolution now handled entirely by Azure DNS infrastructure

---

## Demonstration Commands

### 1. Verify VM DNS Configuration

**Purpose:** Confirm which DNS server each VM is using.

**Command:**

```bash
# On any VM (Linux)
cat /etc/resolv.conf

# Expected output format:
# nameserver 10.0.10.4    # On-prem VMs
# nameserver 10.1.10.4    # Hub/Spoke VMs
```

**PowerShell (if testing from jumpbox):**

```powershell
# Query each VM
$vms = @('onprem-vm-web', 'hub-vm-web', 'spoke1-vm-web1', 'spoke2-vm-web1')
foreach ($vm in $vms) {
    $rg = if ($vm -like 'onprem-*') { 'onprem-rg' } elseif ($vm -like 'spoke1-*') { 'spoke1-rg' } elseif ($vm -like 'spoke2-*') { 'spoke2-rg' } else { 'hub-rg' }
    Write-Host "`n$vm DNS Configuration:" -ForegroundColor Cyan
    az vm run-command invoke --resource-group $rg --name $vm `
        --command-id RunShellScript --scripts 'cat /etc/resolv.conf' `
        --query 'value[0].message' -o tsv | Select-String 'nameserver'
}
```

---

### 2. Basic Name Resolution Tests

**Purpose:** Prove that names resolve correctly across all zones.

**Commands (run from any VM):**

```bash
# Test on-prem zone resolution
nslookup web.onprem.pvt
nslookup dns.onprem.pvt
nslookup client.onprem.pvt

# Test hub (azure) zone resolution
nslookup web.azure.pvt
nslookup dns.azure.pvt
nslookup client.azure.pvt

# Test storage account resolution (replace with actual storage account names)
nslookup <spoke1-storage-account>.blob.core.windows.net
nslookup <spoke2-storage-account>.blob.core.windows.net
```

**Expected Results:**

- All names should resolve successfully
- On-prem names should return 10.0.x.x IPs
- Hub names should return 10.1.x.x IPs
- Storage accounts should return 10.2.x.x or 10.3.x.x (private endpoint IPs)

**PowerShell Test Script:**

```powershell
# From jumpbox - test resolution from hub-vm-web
$testScript = @'
#!/bin/bash
echo "=== On-Prem Zone Resolution ==="
nslookup web.onprem.pvt
echo ""
echo "=== Azure Zone Resolution ==="
nslookup web.azure.pvt
echo ""
echo "=== Storage Account Resolution ==="
nslookup $(az storage account list -g spoke1-rg --query '[0].name' -o tsv).blob.core.windows.net
'@

az vm run-command invoke --resource-group hub-rg --name hub-vm-web `
    --command-id RunShellScript --scripts $testScript `
    --query 'value[0].message' -o tsv
```

---

### 3. Identify Source of Authority

**Purpose:** Prove which DNS server is authoritative for each zone.

**Commands using `dig` (run from any VM):**

```bash
# Query on-prem zone - check AA (Authoritative Answer) flag
dig web.onprem.pvt

# Query azure zone - check AA flag
dig web.azure.pvt

# Query privatelink zone - check AA flag
dig <storage-account>.privatelink.blob.core.windows.net
```

**What to look for:**

- The `flags` line in the output: look for `aa` (authoritative answer)
- The `ANSWER SECTION`: shows the resolved IP
- The `AUTHORITY SECTION`: shows the NS records
- The `Query time`: indicates if forwarding occurred

**Example Output (Authoritative):**

```
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 1
                ^^
              This indicates authoritative answer
```

**Example Output (Non-Authoritative/Forwarded):**

```
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0
           ^^
         No 'aa' flag = forwarded from another server
```

---

### 4. Direct DNS Server Queries

**Purpose:** Query each DNS server directly to understand forwarding behavior.

**Commands (run from any VM with access to both DNS servers):**

```bash
# Query on-prem DNS directly
dig @10.0.10.4 web.onprem.pvt        # Should be authoritative (AA flag)
dig @10.0.10.4 web.azure.pvt          # Should be forwarded (no AA flag)

# Query hub DNS directly
dig @10.1.10.4 web.azure.pvt          # Should be authoritative (AA flag)
dig @10.1.10.4 web.onprem.pvt         # Should be forwarded (no AA flag)

# Query storage account from both servers
dig @10.1.10.4 <storage>.blob.core.windows.net   # Hub DNS (authoritative)
dig @10.0.10.4 <storage>.blob.core.windows.net   # On-prem DNS (forwarded to hub)
```

**PowerShell Test Script:**

```powershell
# Test from hub-vm-web (has access to both DNS servers)
$testScript = @'
#!/bin/bash
echo "=== Query On-Prem DNS for On-Prem Zone (Authority Check) ==="
dig @10.0.10.4 web.onprem.pvt | grep -E "flags:|ANSWER SECTION" -A 2

echo ""
echo "=== Query On-Prem DNS for Azure Zone (Forwarding Check) ==="
dig @10.0.10.4 web.azure.pvt | grep -E "flags:|ANSWER SECTION" -A 2

echo ""
echo "=== Query Hub DNS for Azure Zone (Authority Check) ==="
dig @10.1.10.4 web.azure.pvt | grep -E "flags:|ANSWER SECTION" -A 2

echo ""
echo "=== Query Hub DNS for On-Prem Zone (Forwarding Check) ==="
dig @10.1.10.4 web.onprem.pvt | grep -E "flags:|ANSWER SECTION" -A 2
'@

az vm run-command invoke --resource-group hub-rg --name hub-vm-web `
    --command-id RunShellScript --scripts $testScript `
    --query 'value[0].message' -o tsv
```

---

### 5. Trace Storage Account Resolution Chain

**Purpose:** Show the complete CNAME chain for private endpoint resolution.

**Commands:**

```bash
# Get storage account name first
STORAGE=$(az storage account list -g spoke1-rg --query '[0].name' -o tsv)

# Trace the full resolution chain
dig $STORAGE.blob.core.windows.net

# You should see:
# 1. Query: <storage>.blob.core.windows.net
# 2. CNAME: <storage>.privatelink.blob.core.windows.net
# 3. A Record: 10.2.x.x (private endpoint IP)
```

**Example Output:**

```
;; ANSWER SECTION:
mystorageacct.blob.core.windows.net. 300 IN CNAME mystorageacct.privatelink.blob.core.windows.net.
mystorageacct.privatelink.blob.core.windows.net. 300 IN A 10.2.10.5
```

**PowerShell Detailed Trace:**

```powershell
$storage = (az storage account list -g spoke1-rg --query '[0].name' -o tsv)
Write-Host "Tracing resolution for: $storage.blob.core.windows.net" -ForegroundColor Cyan

$traceScript = @"
#!/bin/bash
STORAGE=$storage
echo "Step 1: Query blob.core.windows.net zone"
dig \$STORAGE.blob.core.windows.net +noall +answer

echo ""
echo "Step 2: Query privatelink zone directly"
dig \$STORAGE.privatelink.blob.core.windows.net +noall +answer

echo ""
echo "Step 3: Show full trace with authorities"
dig \$STORAGE.blob.core.windows.net
"@

az vm run-command invoke --resource-group hub-rg --name hub-vm-web `
    --command-id RunShellScript --scripts $traceScript `
    --query 'value[0].message' -o tsv
```

---

### 6. Check DNS Server Zone Files (Phase 7)

**Purpose:** Confirm zone configuration directly on DNS servers.

**Commands (run on DNS servers):**

```bash
# On on-prem DNS server (10.0.10.4)
sudo cat /etc/bind/db.onprem.pvt                # View zone file
sudo rndc status                                 # Check BIND9 status
sudo named-checkzone onprem.pvt /etc/bind/db.onprem.pvt   # Validate zone

# On hub DNS server (10.1.10.4)
sudo cat /etc/bind/db.azure.pvt                 # View zone file
sudo cat /etc/bind/db.privatelink.blob.core.windows.net
sudo rndc status
sudo named-checkzone azure.pvt /etc/bind/db.azure.pvt
```

**PowerShell Script to View Zones:**

```powershell
Write-Host "=== On-Prem DNS Zone File ===" -ForegroundColor Cyan
az vm run-command invoke --resource-group onprem-rg --name onprem-vm-dns `
    --command-id RunShellScript --scripts 'sudo cat /etc/bind/db.onprem.pvt' `
    --query 'value[0].message' -o tsv

Write-Host "`n=== Hub DNS Zone Files ===" -ForegroundColor Cyan
az vm run-command invoke --resource-group hub-rg --name hub-vm-dns `
    --command-id RunShellScript --scripts 'sudo cat /etc/bind/db.azure.pvt' `
    --query 'value[0].message' -o tsv
```

---

### 7. Check DNS Query Logs (Advanced)

**Purpose:** See DNS queries in real-time to understand resolution patterns.

**Commands (run on DNS servers):**

```bash
# Enable query logging (if not already enabled)
sudo rndc querylog on

# View logs in real-time
sudo tail -f /var/log/syslog | grep named

# From another VM, run some queries:
# nslookup web.azure.pvt
# nslookup web.onprem.pvt

# You should see logs showing:
# - Queries received
# - Forwarding decisions
# - Responses sent
```

**Example Log Output:**

```
Feb 23 10:15:23 hub-vm-dns named[1234]: client 10.1.10.5#54321 (web.azure.pvt): query: web.azure.pvt IN A +E (10.1.10.4)
Feb 23 10:15:23 hub-vm-dns named[1234]: client 10.0.10.5#54322 (web.onprem.pvt): query: web.onprem.pvt IN A +E (10.1.10.4)
```

---

## Comparison Matrix: Phase 7 vs Phase 9-10

| Zone | Phase 7 Authority | Phase 9 Authority | Phase 10 Authority |
|------|------------------|-------------------|-------------------|
| `onprem.pvt` | BIND9 (10.0.10.4) | BIND9 (10.0.10.4) | Azure Private DNS |
| `azure.pvt` | BIND9 (10.1.10.4) | BIND9 (10.1.10.4) | Azure Private DNS |
| `blob.core.windows.net` | BIND9 (10.1.10.4) | BIND9 (10.1.10.4) | Azure Private DNS |
| `privatelink.blob.core.windows.net` | BIND9 (10.1.10.4) | **Azure Private DNS** | Azure Private DNS |

**Key Observation:**

- Name resolution continues to work at all phases
- Only the source of authority changes
- VMs don't need reconfiguration during migration
- Forwarding ensures seamless transition

---

## Quick Demonstration Script

**Purpose:** Run all key tests in sequence for a complete demonstration.

```powershell
# Save as: scripts/demo-dns-resolution.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = 'hub-rg',
    
    [Parameter(Mandatory=$false)]
    [string]$VMName = 'hub-vm-web'
)

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'DNS Resolution Demonstration' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# Get storage account for testing
$storage1 = (az storage account list -g spoke1-rg --query '[0].name' -o tsv)
$storage2 = (az storage account list -g spoke2-rg --query '[0].name' -o tsv)

$demoScript = @"
#!/bin/bash

echo "=== DNS Configuration ==="
cat /etc/resolv.conf | grep nameserver

echo ""
echo "=== On-Prem Zone Resolution ==="
dig +short web.onprem.pvt
dig +short dns.onprem.pvt
dig +short client.onprem.pvt

echo ""
echo "=== Azure Zone Resolution ==="
dig +short web.azure.pvt
dig +short dns.azure.pvt
dig +short client.azure.pvt

echo ""
echo "=== Storage Account Resolution ==="
echo "Spoke1 Storage: $storage1"
dig +short $storage1.blob.core.windows.net
echo ""
echo "Spoke2 Storage: $storage2"
dig +short $storage2.blob.core.windows.net

echo ""
echo "=== Authority Check: On-Prem Zone ==="
dig @10.0.10.4 web.onprem.pvt | grep -E "flags:|ANSWER" -A 2

echo ""
echo "=== Authority Check: Azure Zone ==="
dig @10.1.10.4 web.azure.pvt | grep -E "flags:|ANSWER" -A 2

echo ""
echo "=== Forwarding Check: Cross-Zone Query ==="
dig @10.0.10.4 web.azure.pvt | grep -E "flags:|ANSWER" -A 2

echo ""
echo "=== Storage Resolution Chain ==="
dig $storage1.blob.core.windows.net | grep -E "ANSWER SECTION" -A 5

echo ""
echo "=== Demonstration Complete ==="
"@

Write-Host "Running demonstration on VM: $VMName" -ForegroundColor Yellow
Write-Host ''

$output = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VMName `
    --command-id RunShellScript `
    --scripts $demoScript `
    --query 'value[0].message' -o tsv

Write-Host $output

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host 'Demonstration Complete!' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
```

---

## Troubleshooting Tips

### Resolution Fails

1. **Check VM DNS configuration:** Ensure `/etc/resolv.conf` points to correct DNS server
2. **Check DNS server status:** `sudo systemctl status bind9`
3. **Validate zone files:** `sudo named-checkzone <zone> /etc/bind/db.<zone>`
4. **Check forwarding configuration:** `sudo cat /etc/bind/named.conf.local`

### No Authoritative Answer (AA) Flag

1. **Global `forward only` issue:** Check `/etc/bind/named.conf.options` - should NOT have `forward only` in global options
2. **Zone not loaded:** Check `sudo rndc status` and zone list
3. **Syntax errors:** Check `/var/log/syslog` for BIND9 errors

### Storage Accounts Resolve to Public IPs

1. **Private endpoint not working:** Check Azure portal for private endpoint status
2. **DNS not configured:** Ensure privatelink zone exists and has correct A records
3. **On-prem forwarding missing:** Check that on-prem DNS forwards blob queries to hub DNS

---

## Next Steps

After Phase 7 demonstration:

1. **Phase 8:** Deploy Azure Private DNS + DNS Private Resolver
2. **Phase 9:** Migrate privatelink zone, re-run these tests to show authority change
3. **Phase 10:** Migrate all zones, re-run tests to show full Azure Private DNS operation

Use this guide at each phase to demonstrate that:

- ✅ Name resolution continues to work
- ✅ Source of authority shifts from BIND9 to Azure
- ✅ No VM reconfiguration required
- ✅ Migration is transparent to applications
