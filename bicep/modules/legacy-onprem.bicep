targetScope = 'resourceGroup'

type OnpremDnsIps = {
  dns: string
  client: string
  hubDns: string
}

param location string
param prefix string
param adminUsername string
@secure()
param sshPublicKey string
param vmSize string
param addressSpace string
param subnetPrefix string
param dnsIps OnpremDnsIps
param vnetName string

var privatelinkZone = 'privatelink.blob.${environment().suffixes.storage}'

var nsgName = '${prefix}-onprem-nsg'
var dnsVmName = '${prefix}-onprem-vm-dns'
var clientVmName = '${prefix}-onprem-vm-client'

// NAT Gateway resources
resource onpremNatGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${prefix}-onprem-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource onpremNatGateway 'Microsoft.Network/natGateways@2023-09-01' = {
  name: '${prefix}-onprem-nat'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: onpremNatGatewayPublicIp.id
      }
    ]
  }
}

resource onpremNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-VNet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource onpremVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    dhcpOptions: {
      dnsServers: [
        dnsIps.dns
      ]
    }
    subnets: [
      {
        name: 'snet-vm'
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: onpremNsg.id
          }
          natGateway: {
            id: onpremNatGateway.id
          }
        }
      }
    ]
  }
}

resource dnsNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-onprem-nic-dns'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: dnsIps.dns
          subnet: {
            id: '${onpremVnet.id}/subnets/snet-vm'
          }
        }
      }
    ]
  }
}

resource clientNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-onprem-nic-client'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: dnsIps.client
          subnet: {
            id: '${onpremVnet.id}/subnets/snet-vm'
          }
        }
      }
    ]
  }
}

var onpremDnsCloudInit = format(
  '''#cloud-config
package_update: true
packages:
  - dnsmasq
write_files:
  - path: /etc/dnsmasq.d/custom.conf
    content: |
      domain=onprem.pvt
      local=/onprem.pvt/
      addn-hosts=/etc/dnsmasq.d/onprem.hosts
      server=/azure.pvt/{0}
      server=/{1}/{0}
      server=168.63.129.16
  - path: /etc/dnsmasq.d/onprem.hosts
    content: |
      {2} onprem-vm-dns.onprem.pvt
      {3} onprem-vm-client.onprem.pvt
runcmd:
  - systemctl enable dnsmasq
  - systemctl restart dnsmasq
''',
  dnsIps.hubDns,
  privatelinkZone,
  dnsIps.dns,
  dnsIps.client
)

resource dnsVm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: dnsVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: dnsVmName
      adminUsername: adminUsername
      customData: base64(onpremDnsCloudInit)
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
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: dnsNic.id
        }
      ]
    }
  }
}

resource clientVm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: clientVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: clientVmName
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
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: clientNic.id
        }
      ]
    }
  }
}

output onpremVnetId string = onpremVnet.id
output onpremDnsIp string = dnsIps.dns
