targetScope = 'subscription'

type RgNames = {
  hub: string
  spoke1: string
  spoke2: string
}

type VnetNames = {
  hub: string
  spoke1: string
  spoke2: string
}

param location string = 'centralus'
param prefix string = 'dnsmig'
param rgNames RgNames = {
  hub: '${prefix}-rg-hub'
  spoke1: '${prefix}-rg-spoke1'
  spoke2: '${prefix}-rg-spoke2'
}

param vnetNames VnetNames = {
  hub: '${prefix}-hub-vnet'
  spoke1: '${prefix}-spoke1-vnet'
  spoke2: '${prefix}-spoke2-vnet'
}

param onpremDnsIp string = '10.10.1.4'
param hubDnsIp string = '10.20.1.4'
param linkSpoke2 bool = false

resource rgHub 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: rgNames.hub
}

resource rgSpoke1 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: rgNames.spoke1
}

resource rgSpoke2 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: rgNames.spoke2
}

module hub './modules/private-dns-hub.bicep' = {
  scope: rgHub
  params: {
    location: location
    prefix: prefix
    hubVnetName: vnetNames.hub
    spoke1VnetName: vnetNames.spoke1
    spoke2VnetName: vnetNames.spoke2
    spoke1RgName: rgNames.spoke1
    spoke2RgName: rgNames.spoke2
    onpremDnsIp: onpremDnsIp
    hubDnsIp: hubDnsIp
    linkSpoke2: linkSpoke2
  }
}

module spoke1 './modules/private-dns-spoke.bicep' = {
  scope: rgSpoke1
  params: {
    location: location
    prefix: prefix
    vnetName: vnetNames.spoke1
    subnetPeName: 'snet-pe'
    privateDnsZoneId: hub.outputs.privateDnsZoneId
    storageNameSuffix: 'spoke1'
  }
}

module spoke2 './modules/private-dns-spoke.bicep' = {
  scope: rgSpoke2
  params: {
    location: location
    prefix: prefix
    vnetName: vnetNames.spoke2
    subnetPeName: 'snet-pe'
    privateDnsZoneId: hub.outputs.privateDnsZoneId
    storageNameSuffix: 'spoke2'
  }
}

output inboundResolverIp string = hub.outputs.inboundResolverIp
output privatelinkZoneId string = hub.outputs.privateDnsZoneId
output spoke1StorageAccount string = spoke1.outputs.storageAccountName
output spoke2StorageAccount string = spoke2.outputs.storageAccountName
