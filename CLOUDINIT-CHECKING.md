# Cloud-Init Completion Checking Guide

Since cloud-init has already completed on your VMs, here are **practical ways to confirm cloud-init status** without waiting:

## Quick Status Check

**For DNS Server:**

```bash
az vm run-command invoke -g dnsmig-rg-onprem -n dnsmig-onprem-vm-dns --command-id RunShellScript --scripts 'tail -20 /var/log/cloud-init.log'
```

**For Client VM:**

```bash
az vm run-command invoke -g dnsmig-rg-onprem -n dnsmig-onprem-vm-client --command-id RunShellScript --scripts 'tail -20 /var/log/cloud-init.log'
```

## Check Boot-Finished Marker

Cloud-init creates `/var/lib/cloud/instance/boot-finished` when it completes:

```bash
# DNS Server
az vm run-command invoke -g dnsmig-rg-onprem -n dnsmig-onprem-vm-dns --command-id RunShellScript --scripts 'ls -l /var/lib/cloud/instance/boot-finished'

# Client VM  
az vm run-command invoke -g dnsmig-rg-onprem -n dnsmig-onprem-vm-client --command-id RunShellScript --scripts 'ls -l /var/lib/cloud/instance/boot-finished'
```

If the file exists, cloud-init has completed.

## Check Service Status

For the DNS server, verify dnsmasq is running:

```bash
az vm run-command invoke -g dnsmig-rg-onprem -n dnsmig-onprem-vm-dns --command-id RunShellScript --scripts 'systemctl is-active dnsmasq && echo "Running" || echo "Not running"'
```

Expected output: `Running` (if packages installed successfully)

## Full Cloud-Init Status Report

Get detailed JSON status:

```bash
az vm run-command invoke -g dnsmig-rg-onprem -n dnsmig-onprem-vm-dns --command-id RunShellScript --scripts 'cloud-init status --format json'
```

Look for:

- `"status": "done"` or `"status": "error"`
- `"running": false` (not currently executing)
- If packages failed to install, you'll see warnings in `"recoverable\_errors"`

## Current Status (from previous run)

Your VMs already have:

- ✓ **Cloud-init completed**: `"finished": 68.82` seconds
- ⚠️ **Package installation warning**: apt package errors occurred
  - dnsmasq, curl, net-tools may not be installed
  - This is due to apt timing issues with NAT Gateway setup
  
## Next Actions

### Option 1: Skip waiting, try DNS tests anyway

```bash
./scripts/verify-dns.ps1 -ResourceGroupName dnsmig-rg-onprem -Verbose
```

### Option 2: Manually install missing packages

```bash
# SSH to DNS Server  
az ssh vm -g dnsmig-rg-onprem -n dnsmig-onprem-vm-dns --local-user azureuser

# Then run (as root):
sudo apt-get update
sudo apt-get install -y dnsmasq curl net-tools bind-utils
sudo systemctl restart dnsmasq
```

### Option 3: Redeploy with simpler packages

If you want automatic setup without package installation, you can remove the unnecessary packages from cloud-init config and redeploy.

---

## Why Cloud-Init Show Errors But Still "Completes"

Cloud-init by design:

- ✓ Creates `/var/lib/cloud/instance/boot-finished` marker
- ✓ Sets status to "done" after creating boot-finished
- ⚠️ May have **recoverable errors** (like package installation failures)
- ⚠️ Won't prevent VM from being usable

The "package installation error" in your case is likely due to apt handling with NAT Gateway. The VM is still fully functional for DNS - you just need to install dnsmasq manually.

---

## Manual Cloud-Init Verification Script

If you want a simpler check without waiting:

```powershell
# One-liner to check both VMs
"dnsmig-onprem-vm-dns","dnsmig-onprem-vm-client" | ForEach-Object {
    Write-Host "Checking $_..."
    az vm run-command invoke -g dnsmig-rg-onprem -n $_ --command-id RunShellScript --scripts 'test -f /var/lib/cloud/instance/boot-finished && echo "DONE" || echo "PENDING"' --query 'value[0].message' -o tsv
}
```

Expected output: `DONE` for both VMs
