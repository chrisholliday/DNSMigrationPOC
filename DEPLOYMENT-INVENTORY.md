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

> ⚠️ **Note:** Some VM names differ from DNS names for clarity in different contexts.

### On-Premises VMs

| VM Name | Private IP | **Actual DNS Name** | Role | DNS Server |
|---------|-----------|----------|------|------------|
| onprem-vm-dns | 10.0.10.4 | **dns.onprem.pvt** | DNS Server (BIND9) | Self (10.0.10.4) |
| onprem-vm-client | 10.0.10.5 | **client.onprem.pvt** | Client/Web | 10.0.10.4 |

### Hub VMs

| VM Name | Private IP | **Actual DNS Name** | Role | DNS Server |
|---------|-----------|----------|------|------------|
| hub-vm-dns | 10.1.10.4 | **dns.azure.pvt** | DNS Server (BIND9) | Self (10.1.10.4) |
| hub-vm-app | 10.1.10.5 | **client.azure.pvt** | Application Server | 10.1.10.4 |

### Spoke 1 VMs

| VM Name | Private IP | **Actual DNS Name** | Role | DNS Server |
|---------|-----------|----------|------|------------|
| spoke1-vm-app | 10.2.10.4 | **app1.azure.pvt** | Application Server | 10.1.10.4 |

### Spoke 2 VMs

| VM Name | Private IP | **Actual DNS Name** | Role | DNS Server |
|---------|-----------|----------|------|------------|
| spoke2-vm-app | 10.3.10.4 | **app2.azure.pvt** | Application Server | 10.1.10.4 |

---

## Storage Accounts

| Spoke | Storage Account Name | Public FQDN | Private Endpoint IP | Privatelink FQDN |
|-------|---------------------|-------------|---------------------|------------------|
| Spoke 1 | spoke1saskhwswl4vqpe6 | spoke1saskhwswl4vqpe6.blob.core.windows.net | 10.2.10.5 | spoke1saskhwswl4vqpe6.privatelink.blob.core.windows.net |
| Spoke 2 | spoke2saiwln2ddfdjx5o | spoke2saiwln2ddfdjx5o.blob.core.windows.net | 10.3.10.5 | spoke2saiwln2ddfdjx5o.privatelink.blob.core.windows.net |

---

## DNS Zones and Authority

### Phase 7: BIND9 DNS Servers

| Zone | Authoritative Server | Server IP | **Actual Records** |
|------|---------------------|-----------|---------|
| onprem.pvt | onprem-vm-dns | 10.0.10.4 | dns (10.0.10.4), client (10.0.10.5) |
| azure.pvt | hub-vm-dns | 10.1.10.4 | dns (10.1.10.4), client (10.1.10.5), app1 (10.2.10.4), app2 (10.3.10.4) |
| blob.core.windows.net | **Forwarded to Azure DNS** | 168.63.129.16 | CNAMEs provided by Azure (not hosted locally) |
| privatelink.blob.core.windows.net | hub-vm-dns | 10.1.10.4 | spoke1saskhwswl4vqpe6 (10.2.10.5), spoke2saiwln2ddfdjx5o (10.3.10.5) |

#### Storage Account DNS Resolution Flow

This follows Azure's native Private Endpoint DNS pattern:

1. **Client queries**: `spoke1saskhwswl4vqpe6.blob.core.windows.net`
2. **Hub DNS forwards** to Azure DNS (168.63.129.16)
3. **Azure DNS returns CNAME**: `spoke1saskhwswl4vqpe6.privatelink.blob.core.windows.net`
4. **Hub DNS hosts** privatelink zone locally
5. **Returns A record**: `10.2.10.5` (private endpoint IP)

This approach:

- ✅ Matches Azure Private DNS Zone architecture
- ✅ Automatic CNAMEs from Azure (no manual maintenance)
- ✅ Only override privatelink resolution with private IPs
- ✅ Scalable to new storage accounts without config changes

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

## DNS Testing Quick Reference

### Names That Actually Resolve

```bash
# On-Prem Zone (works from any VM)
nslookup dns.onprem.pvt       # Returns 10.0.10.4 (onprem-vm-dns)
nslookup client.onprem.pvt    # Returns 10.0.10.5 (onprem-vm-client)

# Azure Hub Zone (works from any VM)
nslookup dns.azure.pvt        # Returns 10.1.10.4 (hub-vm-dns)
nslookup client.azure.pvt     # Returns 10.1.10.5 (hub-vm-app)

# Azure Spoke VMs (added in Phase 7)
nslookup app1.azure.pvt       # Returns 10.2.10.4 (spoke1-vm-app)
nslookup app2.azure.pvt       # Returns 10.3.10.4 (spoke2-vm-app)

# Storage Accounts (work from any VM)
nslookup spoke1saskhwswl4vqpe6.blob.core.windows.net      # Returns 10.2.10.5 (via CNAME chain)
nslookup spoke2saiwln2ddfdjx5o.blob.core.windows.net      # Returns 10.3.10.5 (via CNAME chain)
```

### Testing DNS Resolution from VMs

```powershell
# Test from hub-vm-app (client.azure.pvt)
az vm run-command invoke --resource-group rg-hub-dnsmig --name hub-vm-app `
    --command-id RunShellScript `
    --scripts @"
echo '=== My DNS Config ==='
cat /etc/resolv.conf | grep nameserver
echo ''
echo '=== Test On-Prem Resolution ==='
nslookup client.onprem.pvt
nslookup dns.onprem.pvt
echo ''
echo '=== Test Azure Hub Resolution ==='
nslookup client.azure.pvt
nslookup dns.azure.pvt
echo ''
echo '=== Test Azure Spoke VM Resolution ==='
nslookup app1.azure.pvt
nslookup app2.azure.pvt
echo ''
echo '=== Test Storage Account Resolution ==='
nslookup spoke1saskhwswl4vqpe6.blob.core.windows.net
"@ `
    --query 'value[0].message' -o tsv

# Test ping to spoke VMs (by DNS name)
az vm run-command invoke --resource-group rg-hub-dnsmig --name hub-vm-app `
    --command-id RunShellScript `
    --scripts 'ping -c 2 app1.azure.pvt; ping -c 2 app2.azure.pvt' `
    --query 'value[0].message' -o tsv
```

### Known Issues & Limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| VM names differ from DNS names | Confusing during demos | Refer to inventory table for DNS mappings |
| Storage accounts work correctly | None - this is correct! | Use full FQDN with blob.core.windows.net |

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

**Date:** 2026-02-25 (DNS records verified)  
**Updated By:** Manual verification of BIND9 zone files  
**Status:** ⚠️ DNS names do not match VM names - use this inventory for testing
