output "load_balancer_public_ip" {
  value = azurerm_public_ip.lb_pip.ip_address
}

output "vm1_public_ip" {
  value = azurerm_public_ip.vm_pip[0].ip_address
}

output "vm2_public_ip" {
  value = azurerm_public_ip.vm_pip[1].ip_address
}