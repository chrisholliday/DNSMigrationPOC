# DNS Migration POC - Deployment Inventory

> **Auto-generated inventory of deployed resources**  
> This document is updated by deployment scripts to track resource names, IPs, and DNS configurations.

## Resource Groups

| Environment | Resource Group | Location |
|------------|----------------|----------|
| On-Premises | rg-onprem-dnsmig | centralus |
| Hub | rg-hub-dnsmig | centralus |
| Spoke 1 | rg-spoke1-dnsmig | centralus |
| Spoke 2 | rg-spoke2-dnsmig | centralus |

---

## Virtual Networks

| VNet | Address Space | Resource Group | Subnets |
|------|---------------|----------------|---------|
| onprem-vnet | 10.0.0.0/16 | rg-onprem-dnsmig | default (10.0.10.0/24) |
| hub-vnet | 10.1.0.0/16 | rg-hub-dnsmig | default (10.1.10.0/24) |
| spoke1-vnet | 10.2.0.0/16 | rg-spoke1-dnsmig | default (10.2.10.0/24) |
| spoke2-vnet | 10.3.0.0/16 | rg-spoke2-dnsmig | default (10.3.10.0/24) |

---

## Virtual Machines

### On-Premises VMs

| VM Name | Private IP | DNS Name | Role | DNS Server |
|---------|-----------|----------|------|------------|
| onprem-vm-dns | 10.0.10.4 | dns.onprem.pvt | DNS Server (BIND9) | Self |
| onprem-vm-client | 10.0.10.5 | client.onprem.pvt | Client/Web | 10.0.10.4 |

### Hub VMs

| VM Name | Private IP | DNS Name | Role | DNS Server |
|---------|-----------|----------|------|------------|
| hub-vm-dns | 10.1.10.4 | dns.azure.pvt | DNS Server (BIND9) | Self |
| hub-vm-app | 10.1.10.5 | app.azure.pvt | Application Server | 10.1.10.4 |

### Spoke 1 VMs

| VM Name | Private IP | DNS Name | Role | DNS Server |
|---------|-----------|----------|------|------------|
| spoke1-vm-app | 10.2.10.4 | app.spoke1.pvt | Application Server | 10.1.10.4 |

### Spoke 2 VMs

| VM Name | Private IP | DNS Name | Role | DNS Server |
|---------|-----------|----------|------|------------|
| spoke2-vm-app | 10.3.10.4 | app.spoke2.pvt | Application Server | 10.1.10.4 |

---

## Storage Accounts

| Spoke | Storage Account Name | Public FQDN | Private Endpoint IP | Privatelink FQDN |
|-------|---------------------|-------------|---------------------|------------------|
| Spoke 1 | spoke1saskhwswl4vqpe6 | spoke1saskhwswl4vqpe6.blob.core.windows.net | 10.2.10.5 | spoke1saskhwswl4vqpe6.privatelink.blob.core.windows.net |
| Spoke 2 | spoke2saiwln2ddfdjx5o | spoke2saiwln2ddfdjx5o.blob.core.windows.net | 10.3.10.5 | spoke2saiwln2ddfdjx5o.privatelink.blob.core.windows.net |

---

## DNS Zones and Authority

### Phase 7: BIND9 DNS Servers

| Zone | Authoritative Server | Server IP | Records |
|------|---------------------|-----------|---------|
| onprem.pvt | onprem-vm-dns | 10.0.10.4 | dns, web, client |
| azure.pvt | hub-vm-dns | 10.1.10.4 | dns, web, client |
| blob.core.windows.net | hub-vm-dns | 10.1.10.4 | CNAME records |
| privatelink.blob.core.windows.net | hub-vm-dns | 10.1.10.4 | A records |

### Phase 9: Hybrid DNS (Future)

| Zone | Authority | Notes |
|------|-----------|-------|
| onprem.pvt | BIND9 (10.0.10.4) | Not yet migrated |
| azure.pvt | BIND9 (10.1.10.4) | Not yet migrated |
| privatelink.blob.core.windows.net | Azure Private DNS | Migrated via DNS Private Resolver |

### Phase 10: Full Azure Private DNS (Future)

| Zone | Authority | Notes |
|------|-----------|-------|
| onprem.pvt | Azure Private DNS | Fully migrated |
| azure.pvt | Azure Private DNS | Fully migrated |
| privatelink.blob.core.windows.net | Azure Private DNS | Fully migrated |

---

## DNS Private Resolver (Phase 8+)

| Component | Name | IP Address | VNet | Status |
|-----------|------|-----------|------|--------|
| DNS Private Resolver | *Not yet deployed* | - | hub-vnet | Not deployed |
| Inbound Endpoint | *Not yet deployed* | - | hub-vnet | Not deployed |
| Outbound Endpoint | *Not yet deployed* | - | hub-vnet | Not deployed |

---

## Quick Reference Commands

### Query Storage Account Names

```powershell
# Spoke 1 Storage Account
$spoke1Storage = az storage account list -g rg-spoke1-dnsmig --query '[0].name' -o tsv
Write-Host "Spoke1 Storage: $spoke1Storage"

# Spoke 2 Storage Account
$spoke2Storage = az storage account list -g rg-spoke2-dnsmig --query '[0].name' -o tsv
Write-Host "Spoke2 Storage: $spoke2Storage"
```

### List All VMs with IPs

```powershell
$rgs = @('rg-onprem-dnsmig', 'rg-hub-dnsmig', 'rg-spoke1-dnsmig', 'rg-spoke2-dnsmig')
foreach ($rg in $rgs) {
    Write-Host "`n=== $rg ===" -ForegroundColor Cyan
    az vm list -g $rg --show-details --query '[].{Name:name, PrivateIP:privateIps, State:powerState}' -o table
}
```

### Query Private Endpoint IPs

```powershell
# Get private endpoint details
az network private-endpoint list -g rg-spoke1-dnsmig --query '[].{Name:name, IP:customDnsConfigs[0].ipAddresses[0]}' -o table
az network private-endpoint list -g rg-spoke2-dnsmig --query '[].{Name:name, IP:customDnsConfigs[0].ipAddresses[0]}' -o table
```

---

## Deployment Status

| Phase | Status | Deployment Date | Notes |
|-------|--------|----------------|-------|
| Phase 1 | ✅ Deployed | - | Base infrastructure |
| Phase 2 | ✅ Deployed | - | VNet peering |
| Phase 3 | ✅ Deployed | - | DNS VMs deployed |
| Phase 4 | ✅ Deployed | - | BIND9 configured |
| Phase 5 | ✅ Deployed | - | Storage accounts |
| Phase 6 | ✅ Deployed | - | Private endpoints |
| Phase 7 | ✅ Deployed | - | DNS forwarding |
| Phase 8 | ⏳ Not deployed | - | DNS Private Resolver |
| Phase 9 | ⏳ Not deployed | - | Hybrid DNS |
| Phase 10 | ⏳ Not deployed | - | Full migration |

---

## Last Updated

**Date:** 2026-02-24 16:06:37  
**Updated By:** update-inventory.ps1
