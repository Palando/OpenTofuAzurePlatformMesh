variable "subscription_id" {
  description = "Azure-Abonnement-ID; Anmeldung über az login."
  type        = string
}

variable "ssh_public_key" {
  description = "Öffentlicher OpenSSH-Key, eine Zeile. Niemals den privaten PEM-Key eintragen."
  type        = string
  validation {
    condition     = can(regex("^ssh-(rsa|ed25519) [A-Za-z0-9+/]+={0,3}( .*)?$", trimspace(var.ssh_public_key)))
    error_message = "Bitte einen öffentlichen RSA- oder Ed25519-Key im OpenSSH-Format eintragen."
  }
}

variable "ssh_allowed_cidr" {
  description = "IPv4-Netz für SSH; Standard erlaubt alle IPv4-Adressen."
  type        = string
  default     = "0.0.0.0/0"
  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "Bitte ein gültiges IPv4-CIDR angeben, z. B. 0.0.0.0/0."
  }
}

variable "vm_name" {
  type    = string
  default = "vm-fedora-dev"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "zone" {
  type        = string
  default     = "1"
  description = "Verfügbarkeitszone; null für keine feste Zone."
}

variable "vm_size" {
  type        = string
  default     = "Standard_D2as_v7"
  description = "Wie im Screenshot: 2 vCPUs, 8 GiB. Bei Änderung NVMe-Kompatibilität beachten."
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "image_version" {
  type        = string
  default     = "44.20261105.0"
  description = "Version aus deinem Screenshot, für reproduzierbare Erstellung fixiert. Alternativ latest."
}
