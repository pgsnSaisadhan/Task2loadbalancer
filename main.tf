# ============================================================
# main.tf
# Azure Load Balancer + 2 Windows IIS VMs
# ============================================================

# ============================================================
# Resource Group
# ============================================================

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# ============================================================
# Virtual Network
# ============================================================

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# ============================================================
# Subnet
# ============================================================

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ============================================================
# Network Security Group
# ============================================================

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ============================================================
# Public IPs for VMs
# ============================================================

resource "azurerm_public_ip" "vm_pip" {
  count               = 2
  name                = "${var.prefix}-vm${count.index + 1}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ============================================================
# Network Interfaces
# ============================================================

resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "${var.prefix}-vm${count.index + 1}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip[count.index].id
  }
}

# ============================================================
# Associate NSG with NICs
# ============================================================

resource "azurerm_network_interface_security_group_association" "assoc" {
  count                     = 2
  network_interface_id      = azurerm_network_interface.nic[count.index].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ============================================================
# Windows Virtual Machines
# ============================================================

resource "azurerm_windows_virtual_machine" "vm" {
  count               = 2
  name                = "${var.prefix}-vm${count.index + 1}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size

  admin_username = var.admin_username
  admin_password = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.nic[count.index].id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

# ============================================================
# Install IIS + Deploy HTML Page
# ============================================================

resource "azurerm_virtual_machine_extension" "iis" {
  count              = 2
  name               = "iis-install-${count.index}"
  virtual_machine_id = azurerm_windows_virtual_machine.vm[count.index].id

  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"Install-WindowsFeature -Name Web-Server -IncludeManagementTools; Set-Content -Path 'C:\\inetpub\\wwwroot\\index.html' -Value '<html><head><title>VM${count.index + 1}</title><style>body{font-family:Arial;text-align:center;padding-top:100px;background:#0078d4;color:white;}h1{font-size:60px;}h2{font-size:30px;}</style></head><body><h1>🚀 VM ${count.index + 1}</h1><h2>Served by Azure Load Balancer</h2><p>Host: VMHero${count.index + 1}</p></body></html>'\""
  })
}

# ============================================================
# Load Balancer Public IP
# ============================================================

resource "azurerm_public_ip" "lb_pip" {
  name                = "${var.prefix}-lb-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ============================================================
# Azure Load Balancer
# ============================================================

resource "azurerm_lb" "lb" {
  name                = "${var.prefix}-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
  }
}

# ============================================================
# Backend Address Pool
# ============================================================

resource "azurerm_lb_backend_address_pool" "backend" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "BackendPool"
}

# ============================================================
# Associate NICs with Backend Pool
# ============================================================

resource "azurerm_network_interface_backend_address_pool_association" "backend_assoc" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.backend.id
}

# ============================================================
# Health Probe
# ============================================================

resource "azurerm_lb_probe" "probe" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "http-probe"
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

# ============================================================
# Load Balancer Rule
# ============================================================

resource "azurerm_lb_rule" "rule" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "http-rule"
  protocol        = "Tcp"

  frontend_port = 80
  backend_port  = 80

  frontend_ip_configuration_name = "PublicIPAddress"

  backend_address_pool_ids = [
    azurerm_lb_backend_address_pool.backend.id
  ]

  probe_id = azurerm_lb_probe.probe.id

  idle_timeout_in_minutes = 4
  enable_floating_ip      = false
}