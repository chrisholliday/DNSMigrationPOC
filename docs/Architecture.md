# Architecture Overview

This sandbox models a minimal hub‑and‑spoke DNS topology with a staged migration of the `privatelink.blob.core.windows.net` zone from Linux DNS to Azure Private DNS.

## DNS Zones

- **`onprem.pvt`**: This zone fills the role of an onprem dns zone hosting records "outside" of the cloud. It will host the dns record for any virtual machines in the `rg-dnsmig-onprem` resource group
- **`azure.pvt`**: This zone fills the role of a cloud based dns zone hosting records of virtual machines within the cloud. It should host records for all virtual machines in the project that are NOT in the `rg-dnsmig-onprem` resource group
- **`privatelink.blob.core.windows.net`**: This zone will host the records for any storage account in this project. It will initially be hosted by the vm-hub-dns virtual machine, but eventually will be hosted by Azure Private DNS.

## Topology Summary

- **On‑Prem VNet**: Linux DNS server authoritative for `onprem.pvt` and forwarding for `azure.pvt` and `privatelink.blob.core.windows.net`.
- **Hub VNet**: Linux DNS server authoritative for `azure.pvt` and legacy `privatelink.blob.core.windows.net`, and in later stages, Azure Private DNS and Azure Private Resolver.
- **Spoke1 VNet**: Workload VM + Storage private endpoint.
- **Spoke2 VNet**: Workload VM + Storage private endpoint.

## Significant Objects to Create

### Resource examples (naming)

| Resource Group        | Resource Name       | Resource Type           | Role                                      |
| ---                   | ---                 | ---                     | ---                                       |
| rg-dnsmig-onprem      | vnet-onprem         | virtual network         | on-prem network                           |
| rg-dnsmig-onprem      | vm-onprem-dns       | virtual machine         | Linux DNS server for `onprem.pvt` zone    |
| rg-dnsmig-hub         | vnet-hub            | virtual network         | hub network                               |
| rg-dnsmig-hub         | vm-hub-dns          | virtual machine         | Linux DNS server for `azure.pvt` zone     |
| rg-dnsmig-spoke1      | vm-spoke1           | virtual machine         | basic VM to test name resolution          |
| rg-dnsmig-spoke1      | `saspoke1{unique}`  | storage account         | storage account with unique name          |
| rg-dnsmig-spoke2      | vm-spoke2           | virtual machine         | basic VM to test name resolution          |
| rg-dnsmig-spoke2      | `saspoke2{unique}`  | storage account         | storage account with unique name          |

## Access to objects

- Objects should exist within a self-contained set of virtual networks.
- Virtual networks should allow outbound (to the internet) access only; no inbound access via public IPs.
- Internet access should be via NAT Gateway.
- Inbound access to virtual machines is restricted to Azure Bastion.
- Remotely running commands via `az` CLI or PowerShell is preferred over direct Bastion access.
- Traffic between networks should be freely open (this is not a network security exercise).

## Migration & Demonstration Highlights

- **Phase 1**: All DNS served by Linux VMs (legacy).
- **Phase 2**: Azure Private DNS zone created and private endpoints auto‑register records.
- **Phase 3**: HUB DNS forwarders updated to the Resolver inbound endpoint.
- **Phase 4/5**: Spokes migrate one at a time to Azure Private DNS.
