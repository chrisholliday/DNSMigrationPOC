// peering.bicep
// Creates a single one-directional VNet peering from a source VNet to a destination VNet.
// Call this module twice (with swapped source/dest) for bidirectional peering.

targetScope = 'resourceGroup'

@description('Name of the existing source VNet (in this resource group)')
param sourceVnetName string

@description('Name for this peering resource')
param peeringName string

@description('Full resource ID of the remote (destination) VNet')
param remoteVnetId string

resource sourceVnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: sourceVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: sourceVnet
  name: peeringName
  properties: {
    remoteVirtualNetwork: { id: remoteVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

output peeringId string = peering.id
output peeringName string = peering.name
