// phase2/main.bicep
// Phase 2 — Network Connectivity
//
// Creates bidirectional VNet peerings:
//   • On-Prem ↔ Hub
//   • Hub ↔ Spoke1
//   • Hub ↔ Spoke2
//
// Prerequisite: Phase 1 must be deployed successfully.

targetScope = 'subscription'

// ── Construct VNet resource IDs ───────────────────────────────────────────────
// These IDs are deterministic based on the naming convention from Phase 1.

var subscriptionId = subscription().subscriptionId

var vnetOnpremId = '/subscriptions/${subscriptionId}/resourceGroups/rg-dnsmig-onprem/providers/Microsoft.Network/virtualNetworks/vnet-onprem'
var vnetHubId = '/subscriptions/${subscriptionId}/resourceGroups/rg-dnsmig-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub'
var vnetSpoke1Id = '/subscriptions/${subscriptionId}/resourceGroups/rg-dnsmig-spoke1/providers/Microsoft.Network/virtualNetworks/vnet-spoke1'
var vnetSpoke2Id = '/subscriptions/${subscriptionId}/resourceGroups/rg-dnsmig-spoke2/providers/Microsoft.Network/virtualNetworks/vnet-spoke2'

// ── Reference existing resource groups ────────────────────────────────────────

resource rgOnprem 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: 'rg-dnsmig-onprem'
}

resource rgHub 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: 'rg-dnsmig-hub'
}

resource rgSpoke1 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: 'rg-dnsmig-spoke1'
}

resource rgSpoke2 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: 'rg-dnsmig-spoke2'
}

// ── On-Prem ↔ Hub peerings ────────────────────────────────────────────────────

module onpremToHub 'modules/peering.bicep' = {
  scope: rgOnprem
  name: 'peering-onprem-to-hub'
  params: {
    sourceVnetName: 'vnet-onprem'
    peeringName: 'onprem-to-hub'
    remoteVnetId: vnetHubId
  }
}

module hubToOnprem 'modules/peering.bicep' = {
  scope: rgHub
  name: 'peering-hub-to-onprem'
  params: {
    sourceVnetName: 'vnet-hub'
    peeringName: 'hub-to-onprem'
    remoteVnetId: vnetOnpremId
  }
}

// ── Hub ↔ Spoke1 peerings ─────────────────────────────────────────────────────

module hubToSpoke1 'modules/peering.bicep' = {
  scope: rgHub
  name: 'peering-hub-to-spoke1'
  params: {
    sourceVnetName: 'vnet-hub'
    peeringName: 'hub-to-spoke1'
    remoteVnetId: vnetSpoke1Id
  }
  dependsOn: [hubToOnprem] // Serialize hub peerings to avoid API conflicts
}

module spoke1ToHub 'modules/peering.bicep' = {
  scope: rgSpoke1
  name: 'peering-spoke1-to-hub'
  params: {
    sourceVnetName: 'vnet-spoke1'
    peeringName: 'spoke1-to-hub'
    remoteVnetId: vnetHubId
  }
}

// ── Hub ↔ Spoke2 peerings ─────────────────────────────────────────────────────

module hubToSpoke2 'modules/peering.bicep' = {
  scope: rgHub
  name: 'peering-hub-to-spoke2'
  params: {
    sourceVnetName: 'vnet-hub'
    peeringName: 'hub-to-spoke2'
    remoteVnetId: vnetSpoke2Id
  }
  dependsOn: [hubToSpoke1] // Serialize hub peerings to avoid API conflicts
}

module spoke2ToHub 'modules/peering.bicep' = {
  scope: rgSpoke2
  name: 'peering-spoke2-to-hub'
  params: {
    sourceVnetName: 'vnet-spoke2'
    peeringName: 'spoke2-to-hub'
    remoteVnetId: vnetHubId
  }
}
