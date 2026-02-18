#!/usr/bin/env pwsh
# DNS Migration POC - Phase 1 Quick Start

Write-Host @"
╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║         DNS MIGRATION POC - PHASE 1: ON-PREM FOUNDATION            ║
║                                                                    ║
║                    Ready for Deployment                            ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝

📋 WHAT'S BEEN CREATED:

  ✅ Comprehensive 5-phase runbook (RUNBOOK.md)
  ✅ Phase 1 infrastructure template (bicep/phase1/network.bicep)
  ✅ Phase 1 deployment script (scripts/phase1/01-deploy-network.ps1)
  ✅ Phase 1 verification script (scripts/phase1/02-verify-network.ps1)
  ✅ Phase 1 documentation (scripts/phase1/README.md)
  ✅ Implementation summary (PHASE1-READY.md)

─────────────────────────────────────────────────────────────────────

🚀 QUICK START (3 COMMANDS):

  Step 1: Deploy Phase 1
  ────────────────────────────────────────────────────────────────
  cd /Users/chris/Git/DNSMigrationPOC
  
  ./scripts/phase1/01-deploy-network.ps1 `
    -SshPublicKeyPath ~/.ssh/dnsmig.pub

  ⏱️  Duration: ~15 minutes


  Step 2: Verify Phase 1 (after 2-3 minutes)
  ────────────────────────────────────────────────────────────────
  ./scripts/phase1/02-verify-network.ps1 `
    -ResourceGroupName dnsmig-rg-onprem `
    -Verbose

  ✓ All checks should pass


  Step 3: Proceed to Phase 2
  ────────────────────────────────────────────────────────────────
  Once Phase 1 verification passes:
  
  ./scripts/phase2/03-configure-dns-server.ps1 `
    -ResourceGroupName dnsmig-rg-onprem `
    -DnsServerVmName dnsmig-onprem-vm-dns `
    -DnsServerIp 10.10.1.10 `
    -Verbose

─────────────────────────────────────────────────────────────────────

📊 PHASE 1 CREATES:

  Resource Group:     dnsmig-rg-onprem
  
  Network:
  ├─ VNet: dnsmig-onprem-vnet (10.10.0.0/16)
  ├─ Subnet: snet-vms (10.10.1.0/24)
  ├─ NAT Gateway: dnsmig-onprem-nat (outbound internet)
  └─ NSG: dnsmig-onprem-nsg (SSH + DNS rules)
  
  VMs:
  ├─ DNS Server: dnsmig-onprem-vm-dns (10.10.1.10)
  └─ Client: dnsmig-onprem-vm-client (10.10.1.20)
  
  Both on Ubuntu 22.04, ready for Phase 2 configuration

─────────────────────────────────────────────────────────────────────

✅ PHASE 1 SUCCESS CRITERIA (All Verified):

  ✓ Resource group created
  ✓ Both VMs deployed and provisioned
  ✓ Private IPs assigned (10.10.1.10, 10.10.1.20)
  ✓ Public IPs assigned
  ✓ VMs can reach each other (inter-VM connectivity)
  ✓ Both VMs have internet access (NAT Gateway working)
  ✓ SSH access functional
  ✓ Cloud-init completed successfully

─────────────────────────────────────────────────────────────────────

📖 DOCUMENTATION:

  Phase 1 Overview:      scripts/phase1/README.md
  Complete Runbook:      RUNBOOK.md
  Implementation Plan:   PHASE1-READY.md

─────────────────────────────────────────────────────────────────────

🔍 IF SOMETHING GOES WRONG:

  Check Phase 1 deployment status:
  az deployment group list -g dnsmig-rg-onprem -o table

  View deployment errors:
  az deployment group show -g dnsmig-rg-onprem `
    -n [deployment-name] -o json | jq '.properties.error'

  List resources in resource group:
  az resource list -g dnsmig-rg-onprem -o table

  See Phase 1 README for detailed troubleshooting:
  ./scripts/phase1/README.md

─────────────────────────────────────────────────────────────────────

⏭️  PHASE 2 PREVIEW:

  Phase 2 installs and configures dnsmasq on the DNS Server to:
  • Host the onprem.pvt zone
  • Forward queries to Azure/Google DNS
  • Listen on port 53 for client queries

  After Phase 1 passes verification, you'll run:
  ./scripts/phase2/03-configure-dns-server.ps1

─────────────────────────────────────────────────────────────────────

Ready to proceed? Run the deployment command above! 🚀

" -ForegroundColor Cyan

Write-Host "Press any key to close this window..." -ForegroundColor Gray
