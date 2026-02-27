# Project Deployment Guide

## Goals

The goal of this project is to reproduce a very simplified environment using cloud-hosted DNS servers for DNS resolution, and to demonstrate the required actions to migrate DNS resolution to Azure Private DNS while still allowing on-prem devices to resolve cloud DNS zones and ensuring on-prem namespaces are still resolved.

This is not intended to serve as a foundation for production code; the key objective is to get a working environment stood up quickly so the migration steps can be demonstrated.

The deployment follows a phased approach.

### Phase 1: Foundation Infrastructure

**Goal:** Deploy base networking with working defaults (Azure DNS).

- Deploy On-Prem VNet (10.0.0.0/16)
  - Resource Group: `rg-dnsmig-onprem`
  - VM: `vm-onprem-dns`
  - Azure Bastion, NAT Gateway
- Deploy Hub VNet (10.1.0.0/16)
  - Resource Group: `rg-dnsmig-hub`
  - VM: `vm-hub-dns`
  - Azure Bastion, NAT Gateway
- Deploy Spoke1 VNet (10.2.0.0/16)
  - Resource Group: `rg-dnsmig-spoke1`
  - VM: `vm-spoke1`
  - Storage account: example `saspoke1{unique}`
  - Azure Bastion, NAT Gateway
- Deploy Spoke2 VNet (10.3.0.0/16)
  - Resource Group: `rg-dnsmig-spoke2`
  - VM: `vm-spoke2`
  - Storage account: example `saspoke2{unique}`
  - Azure Bastion, NAT Gateway

- **DNS:** All VNets use Azure DNS (168.63.129.16)
- **Testing:** VM provisioning, internet connectivity, package updates

### Phase 2: Network Connectivity

**Goal:** Establish VNet peering and validate cross-VNet communication

- Create bidirectional peering: On-Prem ↔ Hub, Hub ↔ Spoke1, Hub ↔ Spoke2
- Validate network connectivity between VNets
- **Testing:** Cross-VNet ping, routing validation

### Phase 3: DNS Configuration

**Goal:** Configure DNS servers while VNets still uses Azure DNS

- Install BIND9 (or equivilant) on DNS servers
- Configure onprem.pvt DNS zone (create record for onprem vm)
- Configure azure.pvt DNS Zone (create record for hub vm)
- Configure privatelink.blob.core.windows.net zone (legacy) (create records for storage accounts)
- Configure forwarding to Azure DNS for internet names
- **VNet DNS:** Still uses Azure DNS (servers ready but not active)
- **Testing:** Query DNS servers directly, but VNets still uses Azure DNS

### Phase 4: Hosted DNS Cutover

**Goal:** Switch VNets to use the custom DNS servers (BIND9 on VMs).

- Update On-Prem VNet DNS setting to point to `vm-onprem-dns`.
- Update Hub and Spoke VNets to point to `vm-hub-dns`.
- Validate DHCP renewal propagates DNS changes to VMs.
- Configure forwarding from `vm-onprem-dns` → `vm-hub-dns` for `azure.pvt` and `privatelink.blob.core.windows.net`.
- Configure forwarding from `vm-hub-dns` → `vm-onprem-dns` for on-prem zones as needed.
- Configure forwarding from `vm-hub-dns` → Azure DNS for other internet names.

- **Testing:** All VMs resolve records in hosted zones and common internet DNS names.

### Phase 5: Azure Private DNS + Resolver + Forwarding

**Goal:** Deploy Azure Private DNS infrastructure and configure DNS forwarding.

- Create Azure Private DNS zone for `privatelink.blob.core.windows.net`.
- Deploy Private DNS Resolver (inbound and outbound endpoints).
- Link private endpoints to the Private DNS zone (enable auto-registration where applicable).
- Configure `vm-hub-dns` to forward `privatelink` queries → Resolver inbound endpoint.
- Configure `vm-onprem-dns` to forward `privatelink` queries → Resolver inbound endpoint.

- **Testing:** Resolution works via both paths (legacy BIND9 and Azure Private DNS).

### Phase 6: Spoke1 Migration

**Goal:** Migrate Spoke1 to Azure Private DNS.

- Switch Spoke1 VNet DNS to Azure-provided DNS (168.63.129.16).
- Link Spoke1 VNet to the Private DNS zone.
- Remove Spoke1 storage records from `vm-hub-dns` BIND9 (legacy cleanup).

- **Testing:** Spoke1 resolves via Azure Private DNS; Spoke2 remains on legacy BIND9.

### Phase 7: Spoke2 Migration

**Goal:** Complete migration by moving Spoke2 to Azure Private DNS.

- Switch Spoke2 VNet DNS to Azure-provided DNS (168.63.129.16).
- Link Spoke2 VNet to the Private DNS zone.
- Remove the `privatelink` zone from `vm-hub-dns` BIND9 (legacy cleanup complete).

- **Testing:** Both spokes resolve via Azure Private DNS and migration is complete.

## Validation

-- A validation script should be available at each phase to confirm proper configuration. See `./scripts` for phase-specific checks (if present).

## Scripts

- `./scripts/validate.ps1 -Phase <n>`: Phase-aware validation helper that runs `az` CLI checks and reports missing items.
- `./scripts/destroy.ps1`: Deletes the POC resource groups (`rg-dnsmig-*`). Use `-Force` to skip confirmation.

Run validation after each phase and run `destroy.ps1` to tear down the POC when finished.
