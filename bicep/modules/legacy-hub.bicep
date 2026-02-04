targetScope = 'resourceGroup'

type HubDnsIps = {
  dns: string
  onpremDns: string
  spoke1Vm: string
  spoke2Vm: string
}

param location string
param prefix string
param adminUsername string
@secure()
param sshPublicKey string
param vmSize string
param addressSpace string
param subnetVmPrefix string
param subnetInboundPrefix string
param subnetOutboundPrefix string
param dnsIps HubDnsIps
param vnetName string

var privatelinkZone = 'privatelink.blob.${environment().suffixes.storage}'
var nsgName = '${prefix}-hub-nsg'
var dnsVmName = '${prefix}-hub-vm-dns'

resource hubNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
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

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
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
  }
}

resource hubSubnetVm 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: hubVnet
  name: 'snet-vm'
  properties: {
    addressPrefix: subnetVmPrefix
    networkSecurityGroup: {
      id: hubNsg.id
    }
  }
}

resource hubSubnetInbound 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: hubVnet
  name: 'snet-dns-inbound'
  properties: {
    addressPrefix: subnetInboundPrefix
    delegations: [
      {
        name: 'dnsResolverDelegation'
        properties: {
          serviceName: 'Microsoft.Network/dnsResolvers'
        }
      }
    ]
  }
}

resource hubSubnetOutbound 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: hubVnet
  name: 'snet-dns-outbound'
  properties: {
    addressPrefix: subnetOutboundPrefix
    delegations: [
      {
        name: 'dnsResolverDelegation'
        properties: {
          serviceName: 'Microsoft.Network/dnsResolvers'
        }
      }
    ]
  }
}

resource dnsNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-hub-nic-dns'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: dnsIps.dns
          subnet: {
            id: hubSubnetVm.id
          }
        }
      }
    ]
  }
}

var hubDnsCloudInit = format(
  '''#cloud-config
package_update: true
packages:
  - dnsmasq
write_files:
  - path: /etc/dnsmasq.d/custom.conf
    content: |
      domain=azure.pvt
      local=/azure.pvt/
      addn-hosts=/etc/dnsmasq.d/azure.hosts
      local=/{0}/
      addn-hosts=/etc/dnsmasq.d/privatelink.hosts
      server=/onprem.pvt/{1}
      server=168.63.129.16
  - path: /etc/dnsmasq.d/azure.hosts
    content: |
      {2} hub-vm-dns.azure.pvt
      {3} spoke1-vm-app.azure.pvt
      {4} spoke2-vm-app.azure.pvt
  - path: /etc/dnsmasq.d/privatelink.hosts
    content: |
      10.30.2.4 legacyblob.{0}
runcmd:
  - systemctl enable dnsmasq
  - systemctl restart dnsmasq
''',
  privatelinkZone,
  dnsIps.onpremDns,
  dnsIps.dns,
  dnsIps.spoke1Vm,
  dnsIps.spoke2Vm
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
      customData: base64(hubDnsCloudInit)
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

output hubVnetId string = hubVnet.id
output hubDnsIp string = dnsIps.dns
