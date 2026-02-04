targetScope = 'resourceGroup'

param location string
param prefix string
param hubVnetName string
param spoke1VnetName string
param spoke2VnetName string
param spoke1RgName string
param spoke2RgName string
param onpremDnsIp string
param hubDnsIp string
param linkSpoke2 bool

var privatelinkZone = 'privatelink.blob.${environment().suffixes.storage}'

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: hubVnetName
}

resource inboundSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: hubVnet
  name: 'snet-dns-inbound'
}

resource outboundSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: hubVnet
  name: 'snet-dns-outbound'
}

resource dnsResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: '${prefix}-hub-dns-resolver'
  location: location
  properties: {
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: dnsResolver
  name: 'inbound'
  location: location
  properties: {
    ipConfigurations: [
      {
        privateIpAllocationMethod: 'Dynamic'
        subnet: {
          id: inboundSubnet.id
        }
      }
    ]
  }
}

resource outboundEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = {
  parent: dnsResolver
  name: 'outbound'
  location: location
  properties: {
    subnet: {
      id: outboundSubnet.id
    }
  }
}

resource ruleset 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' = {
  name: '${prefix}-hub-ruleset'
  location: location
  properties: {
    dnsResolverOutboundEndpoints: [
      {
        id: outboundEndpoint.id
      }
    ]
  }
}

resource ruleOnprem 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2022-07-01' = {
  parent: ruleset
  name: 'onprem-pvt'
  properties: {
    domainName: 'onprem.pvt'
    targetDnsServers: [
      {
        ipAddress: onpremDnsIp
        port: 53
      }
    ]
  }
}

resource ruleAzure 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2022-07-01' = {
  parent: ruleset
  name: 'azure-pvt'
  properties: {
    domainName: 'azure.pvt'
    targetDnsServers: [
      {
        ipAddress: hubDnsIp
        port: 53
      }
    ]
  }
}

resource rulesetLinkHub 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = {
  parent: ruleset
  name: 'link-hub'
  properties: {
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

resource rulesetLinkSpoke1 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = {
  parent: ruleset
  name: 'link-spoke1'
  properties: {
    virtualNetwork: {
      id: resourceId(subscription().subscriptionId, spoke1RgName, 'Microsoft.Network/virtualNetworks', spoke1VnetName)
    }
  }
}

resource rulesetLinkSpoke2 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = if (linkSpoke2) {
  parent: ruleset
  name: 'link-spoke2'
  properties: {
    virtualNetwork: {
      id: resourceId(subscription().subscriptionId, spoke2RgName, 'Microsoft.Network/virtualNetworks', spoke2VnetName)
    }
  }
}

resource privatelinkZoneResource 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privatelinkZone
  location: 'global'
}

resource zoneLinkHub 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privatelinkZoneResource
  name: 'link-hub'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: hubVnet.id
    }
    registrationEnabled: false
  }
}

resource zoneLinkSpoke1 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privatelinkZoneResource
  name: 'link-spoke1'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: resourceId(subscription().subscriptionId, spoke1RgName, 'Microsoft.Network/virtualNetworks', spoke1VnetName)
    }
    registrationEnabled: false
  }
}

resource zoneLinkSpoke2 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (linkSpoke2) {
  parent: privatelinkZoneResource
  name: 'link-spoke2'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: resourceId(subscription().subscriptionId, spoke2RgName, 'Microsoft.Network/virtualNetworks', spoke2VnetName)
    }
    registrationEnabled: false
  }
}

output inboundResolverIp string = inboundEndpoint.properties.ipConfigurations[0].privateIpAddress
output privateDnsZoneId string = privatelinkZoneResource.id
output rulesetId string = ruleset.id
