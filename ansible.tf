variable "ssh_private_key_path" {
  description = "Lokaler Pfad zum passenden privaten SSH-Key auf dem OpenTofu-Rechner. Nur der Pfad wird gespeichert."
  type        = string
}

resource "terraform_data" "configure" {
  triggers_replace = {
    vm_id     = azurerm_linux_virtual_machine.dev.virtual_machine_id
    public_ip = azurerm_public_ip.dev.ip_address
    user      = var.admin_username
    key_path  = pathexpand(var.ssh_private_key_path)
    playbook  = filesha256("${path.module}/ansible/dev.yml")
    settings  = filesha256("${path.module}/ansible/settings.yml")
    runner    = filesha256("${path.module}/ansible/run.py")
  }

  provisioner "local-exec" {
    working_dir = path.module
    command     = "python3 ansible/run.py"
    environment = {
      DEV_HOST    = azurerm_public_ip.dev.ip_address
      DEV_USER    = var.admin_username
      DEV_SSH_KEY = pathexpand(var.ssh_private_key_path)
      DEV_VM_ID   = azurerm_linux_virtual_machine.dev.virtual_machine_id
    }
  }
}
