// spoke.bicep
// Deploys a spoke VNet with a workload VM, Azure Bastion, NAT Gateway,
// a Storage account (blob), and a private endpoint for that storage account.
// No DNS zone group is created here — DNS records are added manually in Phase 3.

targetScope = 'resourceGroup'

@description('Name of the virtual network')
param vnetName string

@description('VNet address prefix (e.g. 10.2.0.0/16)')
param vnetAddressPrefix string

@description('Subnet prefix for the workload VM and private endpoint (e.g. 10.2.1.0/24)')
param appSubnetPrefix string

@description('Subnet prefix for Azure Bastion — must be /27 or larger')
param bastionSubnetPrefix string

@description('Name of the workload virtual machine')
param vmName string

@description('VM size')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VM OS')
param adminUsername string

@description('SSH public key value (the key data, not a file path)')
param sshPublicKey string

@description('Storage account name — must be globally unique, 3-24 lowercase alphanum chars')
param storageAccountName string

@description('Azure region for all resources')
param location string = resourceGroup().location

// ── NAT Gateway ───────────────────────────────────────────────────────────────

resource natGwPip 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: '${vnetName}-natgw-pip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource natGw 'Microsoft.Network/natGateways@2024-01-01' = {
  name: '${vnetName}-natgw'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIpAddresses: [{ id: natGwPip.id }]
    idleTimeoutInMinutes: 4
  }
}

// ── Bastion NSG ───────────────────────────────────────────────────────────────

resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${vnetName}-bastion-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpsInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 140
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowBastionHostCommunicationInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: ['8080', '5701']
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 150
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['22', '3389']
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBastionCommunicationOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: ['8080', '5701']
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowHttpOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
    ]
  }
}

// ── Virtual Network ───────────────────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [vnetAddressPrefix] }
  }
}

resource appSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'snet-app'
  properties: {
    addressPrefix: appSubnetPrefix
    natGateway: { id: natGw.id }
    // Private endpoint network policies are disabled to allow PE deployment
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'AzureBastionSubnet'
  dependsOn: [appSubnet]
  properties: {
    addressPrefix: bastionSubnetPrefix
    networkSecurityGroup: { id: bastionNsg.id }
  }
}

// ── Azure Bastion ─────────────────────────────────────────────────────────────

resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: '${vnetName}-bastion-pip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: '${vnetName}-bastion'
  location: location
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: bastionSubnet.id }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
  }
}

// ── Workload Virtual Machine ──────────────────────────────────────────────────

resource vmNic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: appSubnet.id }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-osdisk'
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Standard_LRS' }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: vmNic.id }]
    }
  }
}

// ── Storage Account + Private Endpoint ───────────────────────────────────────
// Public network access is disabled; access is only via the private endpoint.
// No DNS zone group in Phase 1 — the PE IP is manually registered in BIND9 (Phase 3).

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

var peName = '${storageAccountName}-pe-blob'

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: peName
  location: location
  properties: {
    subnet: { id: appSubnet.id }
    privateLinkServiceConnections: [
      {
        name: peName
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['blob']
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output vnetId string = vnet.id
output vnetName string = vnet.name
output appSubnetId string = appSubnet.id
output vmName string = vm.name
output vmPrivateIp string = vmNic.properties.ipConfigurations[0].properties.privateIPAddress
output storageAccountName string = storageAccount.name
output privateEndpointName string = privateEndpoint.name
