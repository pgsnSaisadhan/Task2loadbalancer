variable "resource_group_name" {
  default = "windows-loadbalancer-rg"
}

variable "location" {
  default = "Central India"
}

variable "prefix" {
  default = "azuredemo"
}

variable "vm_size" {
  default = "Standard_B1s"
}

variable "admin_username" {
  default = "azureuser"
}

variable "admin_password" {
  description = "Administrator password for VMs"
  type        = string
  sensitive   = true
}