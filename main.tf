terraform {
  required_version = ">= 1.8.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}

locals {
  tags     = { purpose = "development", managed_by = "opentofu" }
  image_id = "/communityGalleries/fedora-5e266ba4-2250-406d-adad-5d73860d958f/images/Fedora-Cloud-44-x64/versions/${var.image_version}"
}

resource "azurerm_resource_group" "dev" {
  name     = "rg-${var.vm_name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "dev" {
  name                = "vnet-${var.vm_name}"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
  address_space       = ["10.42.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "dev" {
  name                 = "dev"
  resource_group_name  = azurerm_resource_group.dev.name
  virtual_network_name = azurerm_virtual_network.dev.name
  address_prefixes     = ["10.42.1.0/24"]
}

resource "azurerm_public_ip" "dev" {
  name                = "pip-${var.vm_name}"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zone == null ? null : [var.zone]
  tags                = local.tags
}

resource "azurerm_network_security_group" "dev" {
  name                = "nsg-${var.vm_name}"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
  tags                = local.tags

  security_rule {
    name                       = "SSH-from-configured-network"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ssh_allowed_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "dev" {
  name                = "nic-${var.vm_name}"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.dev.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.dev.id
  }
}

resource "azurerm_network_interface_security_group_association" "dev" {
  network_interface_id      = azurerm_network_interface.dev.id
  network_security_group_id = azurerm_network_security_group.dev.id
}

resource "azurerm_linux_virtual_machine" "dev" {
  name                            = var.vm_name
  resource_group_name             = azurerm_resource_group.dev.name
  location                        = azurerm_resource_group.dev.location
  size                            = var.vm_size
  zone                            = var.zone
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.dev.id]
  source_image_id                 = local.image_id
  disable_password_authentication = true
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  disk_controller_type            = "NVMe"
  patch_mode                      = "ImageDefault"
  tags                            = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(var.ssh_public_key)
  }

  os_disk {
    name                 = "osdisk-${var.vm_name}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  boot_diagnostics {}

  depends_on = [azurerm_network_interface_security_group_association.dev]
}

output "public_ip" {
  value = azurerm_public_ip.dev.ip_address
}

output "ssh_command" {
  value = "ssh -i /pfad/zum/privaten-key.pem ${var.admin_username}@${azurerm_public_ip.dev.ip_address}"
}

output "resource_group" {
  value = azurerm_resource_group.dev.name
}
