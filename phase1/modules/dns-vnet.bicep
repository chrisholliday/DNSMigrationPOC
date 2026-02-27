// dns-vnet.bicep
// Deploys a VNet with a DNS server VM, Azure Bastion, and NAT Gateway.
// Used for both the OnPrem and Hub VNets.

targetScope = 'resourceGroup'

@description('Name of the virtual network')
param vnetName string

@description('VNet address prefix (e.g. 10.0.0.0/16)')
param vnetAddressPrefix string

@description('Subnet prefix for the DNS VM (e.g. 10.0.1.0/24)')
param vmSubnetPrefix string

@description('Subnet prefix for Azure Bastion — must be /27 or larger')
param bastionSubnetPrefix string

@description('Name of the DNS virtual machine')
param vmName string

@description('VM size')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VM OS')
param adminUsername string

@description('SSH public key value (the key data, not a file path)')
param sshPublicKey string

@description('Azure region for all resources')
param location string = resourceGroup().location

// ── NAT Gateway ──────────────────────────────────────────────────────────────

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
// Required rules for Azure Bastion Basic tier.

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

// Subnets are created as child resources to allow clean symbolic references.
// Sequential dependsOn prevents concurrent subnet modification errors.

resource dnsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'snet-dns'
  properties: {
    addressPrefix: vmSubnetPrefix
    natGateway: { id: natGw.id }
  }
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'AzureBastionSubnet'
  dependsOn: [dnsSubnet]
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

// ── DNS Virtual Machine ───────────────────────────────────────────────────────
// cloud-init installs BIND9 at provisioning time.
// Zone configuration is performed in Phase 3 via az vm run-command.

var dnsCloudInit = '''
#cloud-config
packages:
  - bind9
  - bind9utils
  - dnsutils
runcmd:
  - systemctl enable named
  - systemctl start named
'''

resource vmNic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: dnsSubnet.id }
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
      customData: base64(dnsCloudInit)
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

// ── Outputs ───────────────────────────────────────────────────────────────────

output vnetId string = vnet.id
output vnetName string = vnet.name
output dnsSubnetId string = dnsSubnet.id
output vmName string = vm.name
output vmPrivateIp string = vmNic.properties.ipConfigurations[0].properties.privateIPAddress
