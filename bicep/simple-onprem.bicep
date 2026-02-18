targetScope = 'resourceGroup'

param location string = 'centralus'
param prefix string = 'dnsmig'
param adminUsername string = 'azureuser'

@secure()
param sshPublicKey string

param vmSize string = 'Standard_B2s'
param vnetAddressSpace string = '10.10.0.0/16'
param vmSubnetPrefix string = '10.10.1.0/24'

// DNS Server IP (first usable IP in subnet)
param dnsServerIp string = '10.10.1.10'
// Client VM IP 
param clientVmIp string = '10.10.1.20'

/////////////////////
// NETWORKING
/////////////////////

// Public IP for NAT Gateway (internet connectivity)
resource natPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${prefix}-onprem-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// NAT Gateway for outbound internet access
resource natGateway 'Microsoft.Network/natGateways@2023-09-01' = {
  name: '${prefix}-onprem-nat'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
  }
}

// Network Security Group - allows SSH and DNS traffic
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${prefix}-onprem-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-Internal'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-DNS-Internal'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${prefix}-onprem-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    dhcpOptions: {
      dnsServers: [
        dnsServerIp
      ]
    }
    subnets: [
      {
        name: 'snet-vms'
        properties: {
          addressPrefix: vmSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          natGateway: {
            id: natGateway.id
          }
        }
      }
    ]
  }
}

/////////////////////
// DNS SERVER VM
/////////////////////

// Network Interface for DNS Server
resource dnsNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-onprem-nic-dns'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: dnsServerIp
          subnet: {
            id: '${vnet.id}/subnets/snet-vms'
          }
        }
      }
    ]
  }
}

// Cloud-init script to configure dnsmasq
var dnsServerCloudInit = base64('''#cloud-config
package_update: true
packages:
  - dnsmasq
  - curl
  - net-tools
  - bind-utils

runcmd:
  - |
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    
    # Configure dnsmasq
    mkdir -p /etc/dnsmasq.d
    cat > /etc/dnsmasq.d/onprem.conf <<'EOF'
    # Local domain configuration
    address=/onprem.pvt/${dnsServerIp}
    
    # DNS server options
    listen-address=127.0.0.1,::1
    listen-address=${dnsServerIp}
    
    # Upstream DNS servers (Azure DNS and public DNS)
    server=168.63.129.16
    server=8.8.8.8
    server=8.8.4.4
    
    # Add local hosts file
    addn-hosts=/etc/dnsmasq.hosts
    EOF
    
    # Create local hosts file
    cat > /etc/dnsmasq.hosts <<'EOF'
    ${dnsServerIp} onprem-dns.onprem.pvt
    ${dnsServerIp} onprem-dns
    EOF
    
    # Enable and restart dnsmasq
    systemctl enable dnsmasq
    systemctl restart dnsmasq
    
    # Log that DNS server is ready
    echo "DNS Server (${dnsServerIp}) is ready" > /tmp/dns-ready.log

write_files:
  - path: /etc/cloud/cloud.cfg.d/99-dns.cfg
    content: |
      system_info:
        distro: ubuntu
''')

// DNS Server VM
resource dnsVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${prefix}-onprem-vm-dns'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${prefix}-onprem-vm-dns'
      adminUsername: adminUsername
      customData: dnsServerCloudInit
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
          id: dnsNic.id
        }
      ]
    }
  }
}

/////////////////////
// CLIENT VM
/////////////////////

// Network Interface for Client VM
resource clientNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-onprem-nic-client'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: clientVmIp
          subnet: {
            id: '${vnet.id}/subnets/snet-vms'
          }
        }
      }
    ]
  }
}

// Cloud-init script for client VM
var clientCloudInit = base64('''#cloud-config
package_update: true
packages:
  - curl
  - net-tools
  - bind-utils
  - dnsutils
  - vim
  - jq

runcmd:
  - |
    # Configure DNS resolution to use the DNS server
    # This should already be set by VNET DHCP settings, but ensure it's correct
    echo "DNS configured via VNET settings to ${dnsServerIp}"
    
    # Verify DNS is working
    nslookup onprem.pvt 127.0.0.1 > /tmp/dns-test.log 2>&1 || true
    
    # Create a test script
    cat > /usr/local/bin/test-dns.sh <<'EOF'
    #!/bin/bash
    echo "=== DNS Resolution Tests ==="
    echo "Testing local domain (onprem.pvt):"
    nslookup onprem.pvt
    echo ""
    echo "Testing Azure DNS:"
    nslookup azure.microsoft.com
    echo ""
    echo "Current DNS servers:"
    systemctl status systemd-resolved || cat /etc/resolv.conf
    EOF
    
    chmod +x /usr/local/bin/test-dns.sh

''')

// Client VM
resource clientVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${prefix}-onprem-vm-client'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${prefix}-onprem-vm-client'
      adminUsername: adminUsername
      customData: clientCloudInit
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
          id: clientNic.id
        }
      ]
    }
  }
}

/////////////////////
// OUTPUTS
/////////////////////

output resourceGroupName string = resourceGroup().name
output dnsServerPrivateIp string = dnsServerIp
output dnsServerVmName string = dnsVm.name
output clientVmName string = clientVm.name
output clientPrivateIp string = clientVmIp
output vnetName string = vnet.name
output vnetId string = vnet.id
output natGatewayPublicIp string = natPublicIp.properties.ipAddress
