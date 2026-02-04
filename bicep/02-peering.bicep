targetScope = 'resourceGroup'

// Reference VNets created by phase 1
resource onpremVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: 'dnsmig-onprem-vnet'
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: 'dnsmig-hub-vnet'
}

resource spoke1Vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: 'dnsmig-spoke1-vnet'
}

resource spoke2Vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: 'dnsmig-spoke2-vnet'
}

// Peering: OnPrem <-> Hub
resource onpremToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: onpremVnet
  name: 'dnsmig-onprem-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource hubToOnpremPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVnet
  name: 'dnsmig-hub-to-onprem'
  properties: {
    remoteVirtualNetwork: {
      id: onpremVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Peering: Hub <-> Spoke1
resource hubToSpoke1Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVnet
  name: 'dnsmig-hub-to-spoke1'
  properties: {
    remoteVirtualNetwork: {
      id: spoke1Vnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource spoke1ToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: spoke1Vnet
  name: 'dnsmig-spoke1-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Peering: Hub <-> Spoke2
resource hubToSpoke2Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVnet
  name: 'dnsmig-hub-to-spoke2'
  properties: {
    remoteVirtualNetwork: {
      id: spoke2Vnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource spoke2ToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: spoke2Vnet
  name: 'dnsmig-spoke2-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

output peersCreated bool = true
