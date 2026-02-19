# Validation Guide

This guide matches the phases in the runbook and explains expected outcomes.

## Phase: Legacy

Expected behavior:

- `onprem.pvt` resolves from on‑prem and spokes.
- `azure.pvt` resolves from on‑prem and spokes.
- `privatelink.blob.core.windows.net` is still hosted on the hub Linux DNS server.

## Phase: AfterPrivateDns

Expected behavior:

- Private DNS zone exists in the hub resource group.
- Private endpoints have registered A‑records automatically via DNS Zone Groups.

## Phase: AfterForwarders

Expected behavior:

- Linux DNS servers forward `privatelink.blob.core.windows.net` to the Resolver inbound endpoint.
- On‑prem client resolves private endpoint FQDNs to private IPs.

## Phase: AfterSpoke1

Expected behavior:

- Spoke1 uses Azure‑provided DNS.
- Spoke1 resolves `privatelink.blob.core.windows.net` via Private DNS.
- Spoke2 still uses the hub Linux DNS server and continues to work.

Run:

## Phase: AfterSpoke2

Expected behavior:

- Spoke2 is linked to Private DNS and uses Azure‑provided DNS.
- Both spokes resolve private endpoint records from Private DNS.
- Legacy DNS remains authoritative for `onprem.pvt` and `azure.pvt`.
