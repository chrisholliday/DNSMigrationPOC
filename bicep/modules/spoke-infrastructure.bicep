// Spoke Infrastructure Module
// Contains: VNet, VM, Storage Account, Private Endpoint
// No Bastion/NAT Gateway (uses Hub's via peering)

metadata description = 'Spoke infrastructure module (resource group scope)'

@description('Azure region for resources')
param location string

@description('SSH public key for VM authentication')
param sshPublicKey string

@description('VM admin username')
param vmAdminUsername string = 'azureuser'

@description('Spoke identifier (spoke1 or spoke2)')
param spokeName string

@description('VNet address prefix')
param vnetAddressPrefix string

@description('Workload subnet prefix')
param workloadSubnetPrefix string

@description('VM IP address')
param vmIpAddress string

@description('DNS server IP (hub DNS server)')
param dnsServerIp string = '10.1.10.4'

// Naming convention
var vnetName = '${spokeName}-vnet'
var workloadSubnetName = '${spokeName}-subnet-workload'
var nsgName = '${spokeName}-nsg'
var vmName = '${spokeName}-vm-app'
var storageAccountName = '${spokeName}sa${uniqueString(resourceGroup().id)}'
var privateEndpointName = '${spokeName}-pe-storage'

// ===============================
// NETWORK SECURITY GROUP
// ===============================
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-08-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSHFromHub'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.1.0.0/16'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSSHFromOnprem'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/16'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ===============================
// VIRTUAL NETWORK
// ===============================
resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    dhcpOptions: {
      dnsServers: [
        dnsServerIp
      ]
    }
    subnets: [
      {
        name: workloadSubnetName
        properties: {
          addressPrefix: workloadSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// ===============================
// VIRTUAL MACHINE
// ===============================
resource vmNic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: vmIpAddress
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

// Install basic tools via custom script extension
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  parent: vm
  name: 'CustomScript'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'apt-get update && apt-get install -y curl dnsutils'
    }
  }
}

// ===============================
// STORAGE ACCOUNT
// ===============================
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// ===============================
// PRIVATE ENDPOINT
// ===============================
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-08-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// ===============================
// OUTPUTS
// ===============================
output vnetId string = vnet.id
output vnetName string = vnet.name
output vmName string = vm.name
output vmPrivateIp string = vmIpAddress
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output privateEndpointId string = privateEndpoint.id
output privateEndpointName string = privateEndpoint.name
// Get NIC ID from private endpoint for IP extraction
output privateEndpointNicId string = privateEndpoint.properties.networkInterfaces[0].id
