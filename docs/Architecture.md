# Architecture Overview

This sandbox models a minimal hub‑and‑spoke DNS topology with a staged migration of the `privatelink.blob.core.windows.net` zone from Linux DNS to Azure Private DNS.

## Topology Summary

- **On‑Prem VNet**: Linux DNS server authoritative for `onprem.pvt` and forwarding for `azure.pvt` and `privatelink.blob.core.windows.net`.
- **Hub VNet**: Linux DNS server authoritative for `azure.pvt` and legacy `privatelink.blob.core.windows.net`, plus Azure Private DNS Resolver.
- **Spoke1 VNet**: Workload VM + Storage private endpoint.
- **Spoke2 VNet**: Workload VM + Storage private endpoint.

## Mermaid Diagram

```mermaid
flowchart LR
  subgraph OnPrem[On-Prem VNet]
    OPDNS[onprem-vm-dns\nDNS: onprem.pvt]
    OPCL[onprem-vm-client]
  end

  subgraph Hub[Hub VNet]
    HBDNS[hub-vm-dns\nDNS: azure.pvt + legacy privatelink]
    PRIN[Private Resolver Inbound]
    PROUT[Private Resolver Outbound]
    PDNS[Private DNS: privatelink.blob.core.windows.net]
  end

  subgraph Spoke1[Spoke1 VNet]
    S1VM[spoke1-vm-app]
    S1PE[Storage PE]
  end

  subgraph Spoke2[Spoke2 VNet]
    S2VM[spoke2-vm-app]
    S2PE[Storage PE]
  end

  OPCL --> OPDNS
  OPDNS --> HBDNS
  HBDNS --> OPDNS

  S1VM --> HBDNS
  S2VM --> HBDNS

  OPDNS -.privatelink.-> PRIN
  HBDNS -.privatelink.-> PRIN
  PRIN --> PDNS
  PROUT --> OPDNS

  S1PE --> PDNS
  S2PE --> PDNS

  Hub --- Spoke1
  Hub --- Spoke2
  Hub --- OnPrem
```

## Migration Highlights

- **Phase 1**: All DNS served by Linux VMs (legacy).
- **Phase 2**: Azure Private DNS zone created and private endpoints auto‑register records.
- **Phase 3**: Linux DNS forwarders updated to the Resolver inbound endpoint.
- **Phase 4/5**: Spokes migrate one at a time to Azure‑provided DNS.
