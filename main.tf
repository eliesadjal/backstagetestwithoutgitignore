# Announcement of the TF provider that will be used in this infrastructure

provider "azurerm" {
  #skip_provider_registration = true
  features {}
}

# Creation of a Ressource Group

resource "azurerm_resource_group" "BackstageRG" {
  name     = "BackstageRG"
  location = "West Europe"
}

# Creation of the network services : Vnet and Subnet

resource "azurerm_virtual_network" "BackstageVnet" {
  name                = "BackstageVnet"
  location            = azurerm_resource_group.BackstageRG.location
  resource_group_name = azurerm_resource_group.BackstageRG.name
  address_space       = ["10.0.0.0/16"]
}

# Our PostgreSql flexible server wil be attached to this subnet. The subnet will be delegated to our Postgre

resource "azurerm_subnet" "PostgreSubnet" {
  name                 = "PostgreSubnet"
  resource_group_name  = azurerm_resource_group.BackstageRG.name
  virtual_network_name = azurerm_virtual_network.BackstageVnet.name
  address_prefixes     = ["10.0.2.0/24"]
  delegation {
    name = "flexibleserver"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Our AKS Cluster will have his node pool(s) attached to this subnet

resource "azurerm_subnet" "akssubnet" {
  name                 = "akssubnet"
  resource_group_name  = azurerm_resource_group.BackstageRG.name
  virtual_network_name = azurerm_virtual_network.BackstageVnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

# Creation of a private dns zone for the PostgreSQL database

resource "azurerm_private_dns_zone" "dnszone" {
  name                = "dnszone.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.BackstageRG.name
}

# Link to the vnet

resource "azurerm_private_dns_zone_virtual_network_link" "vnetlink" {
  name                  = "BackstageVnetZone.com"
  private_dns_zone_name = azurerm_private_dns_zone.dnszone.name
  virtual_network_id    = azurerm_virtual_network.BackstageVnet.id
  resource_group_name   = azurerm_resource_group.BackstageRG.name
}

# Creation of the PostgreSQL flexibe server instance (Free tier)

resource "azurerm_postgresql_flexible_server" "backstage-backend-postgresql-server" {
  name                   = "backstage-backend-postgresql-server"
  resource_group_name    = azurerm_resource_group.BackstageRG.name
  location               = azurerm_resource_group.BackstageRG.location
  version                = "13"
  delegated_subnet_id    = azurerm_subnet.PostgreSubnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.dnszone.id
  administrator_login    = "backendadmin"
  administrator_password = "spotify"
  zone                   = "1"

  storage_mb = 32768

  sku_name   = "B_Standard_B1ms"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.vnetlink]

}

# Creation of the AKS Cluster instance

resource "azurerm_kubernetes_cluster" "Backstageaks" {
  name                = "Backstageaks"
  location            = azurerm_resource_group.BackstageRG.location
  resource_group_name = azurerm_resource_group.BackstageRG.name
  dns_prefix          = "backstageaks"
  kubernetes_version  = "1.21.9"


  default_node_pool {
    name           = "backendpool"
    node_count     = 1
    vm_size        = "Standard_B2s"
    vnet_subnet_id = azurerm_subnet.akssubnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "kubenet"
    service_cidr       = "10.1.0.0/24"
    dns_service_ip     = "10.1.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }

}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.Backstageaks.kube_config.0.client_certificate
  sensitive = true
}

output "kube_config" {
  value = azurerm_kubernetes_cluster.Backstageaks.kube_config_raw

  sensitive = true
}
