# Fedora 44 auf Azure mit OpenTofu

Erstellt eine neue, eigenständige Entwicklungs-VM. Die vorhandene VM `vm-sg-001` und deren Ressourcengruppe werden nicht übernommen oder verändert.

## Vorgaben

- East US (`eastus`), Zone 1
- `Standard_D2as_v7`: 2 vCPUs, 8 GiB RAM, NVMe
- Fedora Cloud 44 x64 aus der offiziellen Community Gallery
- Image-Version `44.20261105.0` aus dem Screenshot; alternativ `latest`
- Trusted Launch über Secure Boot und vTPM
- 64 GiB Standard SSD als persistente OS-Disk
- Eigene Ressourcengruppe, VNet, Subnetz, Netzwerkkarte, Standard Public IP und Firewallregel für SSH
- SSH-Key-Anmeldung, keine Passwortanmeldung

## 1. Einstellungen

Voraussetzungen: OpenTofu und Azure CLI. Befehle in diesem Ordner ausführen.

```bash
cp terraform.tfvars.example terraform.tfvars
```

In `terraform.tfvars` setzen:

- `subscription_id`: deine Azure-Abonnement-ID
- `ssh_public_key`: vollständiger öffentlicher OpenSSH-Key als eine Zeile
- `ssh_allowed_cidr`: standardmäßig `0.0.0.0/0` für SSH von allen IPv4-Adressen; optional auf dein Netz begrenzen

Port 22 ist standardmäßig weltweit über IPv4 erreichbar. Passwortanmeldung bleibt deaktiviert.

Falls du nur den privaten PEM-Key hast, lässt sich der öffentliche Schlüssel so anzeigen:

```bash
chmod 600 ~/.ssh/meine-azure-vm.pem
ssh-keygen -y -f ~/.ssh/meine-azure-vm.pem
```

Die ausgegebene Zeile (`ssh-rsa ...` oder `ssh-ed25519 ...`) in `ssh_public_key` kopieren. Der private Schlüssel wird weder hochgeladen noch von OpenTofu eingelesen oder im State gespeichert.

Alternativ einen neuen Schlüssel erstellen:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/azure-fedora
cat ~/.ssh/azure-fedora.pub
```

## 2. Anmelden, prüfen und erstellen

```bash
az login
az account list --output table
tofu init
tofu validate
tofu plan
tofu apply
```

Der Provider verwendet die in `terraform.tfvars` angegebene Subscription. Der angemeldete Benutzer muss dort Ressourcen erstellen dürfen. `tofu apply` zeigt die geplanten Änderungen und fragt vor der Erstellung nach Bestätigung. Die tatsächliche Kapazität und Berechtigung in Azure werden erst bei der Bereitstellung endgültig geprüft.

Die erzeugte `.terraform.lock.hcl` für reproduzierbare Provider-Versionen behalten und bei Nutzung von Git mit versionieren.

## 3. Verbinden

```bash
ssh -i ~/.ssh/meine-azure-vm.pem "azureuser@$(tofu output -raw public_ip)"
```

Bei geändertem `admin_username` den Namen im Befehl anpassen. Der Output `ssh_command` enthält ebenfalls einen Befehl mit dem konfigurierten Benutzernamen; dort den privaten Schlüsselpfad ersetzen.

Das ergänzte Ansible-Playbook installiert die Entwicklungswerkzeuge automatisch. Zusätzliche Systemupdates können bei Bedarf manuell erfolgen:

```bash
sudo dnf upgrade --refresh -y
sudo dnf install -y git podman
```

Nach Kernel-Updates gegebenenfalls neu starten. Nur bei einer selbst gesetzten IP-Beschränkung: Ändert sich deine öffentliche IP, `ssh_allowed_cidr` anpassen und `tofu apply` erneut ausführen.

## 4. Nach der Nutzung

Vollständig entfernen:

```bash
tofu destroy
```

Das löscht alle von dieser Konfiguration verwalteten Ressourcen einschließlich OS-Disk und darauf gespeicherter Arbeit. Zuvor benötigte Daten sichern. Keine fremden Ressourcen in diese eigens angelegte Ressourcengruppe hinzufügen.

Alternativ die VM samt Daten behalten und nur deallokieren (bei angepassten Namen die Argumente entsprechend ändern):

```bash
az vm deallocate --resource-group rg-vm-fedora-dev --name vm-fedora-dev --subscription DEINE-ABONNEMENT-ID
az vm start --resource-group rg-vm-fedora-dev --name vm-fedora-dev --subscription DEINE-ABONNEMENT-ID
```

Bei Deallokierung bleiben Kosten für Datenträger, öffentliche IP und gegebenenfalls andere Ressourcen bestehen. Ein erneutes `tofu apply` ist kein Startbefehl für eine deallokierte VM.

## Änderungen und State

- `vm_size` kann angepasst werden. Die Konfiguration setzt einen NVMe-Controller voraus; bei älteren Größen deren Kompatibilität prüfen.
- `zone = null` entfernt die feste Zonenvorgabe; Änderungen an vorhandenen Ressourcen können Neuerstellung auslösen. Immer den Plan lesen.
- Das Community-Image muss in der ausgewählten Region verfügbar sein. East US ist anhand deiner vorhandenen VM gewählt.
- Ein Wechsel der festgelegten `image_version` ersetzt die VM. `latest` wird bei Neuerstellung aufgelöst, aktualisiert aber keine laufende VM automatisch.
- Der State liegt standardmäßig lokal. Ordner und State zwischen Aufrufen behalten, sonst kann OpenTofu die erstellten Ressourcen nicht mehr zuverlässig zuordnen. Für mehrere Rechner später einen gemeinsamen Remote-State einrichten.
- `.gitignore` schließt State, private Schlüssel und persönliche `.tfvars` aus.

## Quellen

- AzureRM VM-Ressource: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine
- Offizieller Fedora-Gallery-Weg (älteres Versionsbeispiel): https://fedoramagazine.org/launch-fedora-40-in-microsoft-azure/
- Image-ID, Region, Version und VM-Größe: deine bereitgestellten Azure-Screenshots.

## Lokale Prüfung

`tofu fmt -check` und `tofu validate` erfolgreich mit OpenTofu 1.13.2 und AzureRM 4.81.0. Kein Azure-Plan oder Deployment ausgeführt.

## Azure-Dienstregistrierungen

Automatische Dienstregistrierungen sind deaktiviert (`resource_provider_registrations = "none"`). Die benötigten Dienste Microsoft.Compute und Microsoft.Network müssen im Zielabonnement bereits registriert sein; bei einer vorhandenen VM mit Netzwerk ist das üblicherweise der Fall. Bei Bedarf mit `az provider show --namespace Microsoft.Compute --query registrationState -o tsv` bzw. Microsoft.Network prüfen (zuvor mit `az account set --subscription DEINE-ABONNEMENT-ID` das richtige Abonnement wählen). Fehlende Dienste gezielt mit `az provider register --namespace Microsoft.Compute --wait` bzw. Microsoft.Network registrieren; dafür sind entsprechende Berechtigungen erforderlich.


## Automatische Einrichtung mit Ansible

Die zusätzliche Datei `ansible.tf` wird von OpenTofu automatisch geladen. `terraform_data.configure` führt nach der VM-Erstellung `python3 ansible/run.py` lokal aus. Das Playbook wartet bis zu zehn Minuten auf SSH/Python und anschließend auf cloud-init. SSH und passwortloses sudo des Azure-Administrators werden vorausgesetzt.

### Auf deinem Homeserver vorbereiten

Python 3, OpenSSH und Ansible müssen auf dem Rechner installiert sein, auf dem `tofu apply` läuft, nicht vorab in der VM. Empfohlen ist aktuelles Ansible Core (2.20 oder neuer) für das Python der Fedora-44-VM. Zum Beispiel in einer Python-Umgebung auf einem ausreichend aktuellen Python:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install 'ansible-core>=2.20,<2.22'
ansible-playbook --version
```

Ansible Core 2.20 benötigt auf dem Steuerrechner Python 3.12 oder neuer. Die virtuelle Umgebung auch vor späteren `tofu apply`-Aufrufen aktivieren. Alternativ Ansible aus einer passenden Distribution installieren.

In deiner vorhandenen `terraform.tfvars` ergänzen:

```hcl
ssh_private_key_path = "~/.ssh/meine-azure-vm.pem"
```

Dieser private Key muss zu `ssh_public_key` passen. Der Dateiinhalt wird nicht in OpenTofu eingelesen; nur sein Pfad steht in der Konfiguration bzw. im State. Bei einem verschlüsselten Schlüssel vorab `ssh-add ~/.ssh/meine-azure-vm.pem` in einem laufenden SSH-Agent ausführen.

```bash
tofu init
tofu plan
tofu apply
```

`apply` meldet erst dann Erfolg, wenn auch Ansible erfolgreich war. Bei einem Ansible-Fehler bleibt die VM erhalten. Ursache beheben und `tofu apply` erneut ausführen. Änderungen an Playbook, Einstellungen und Runner sowie eine neu erstellte VM lösen einen neuen Lauf aus. Ein unverändertes Apply führt Ansible nicht erneut aus. Bewusst erneut ausführen:

```bash
tofu apply -replace=terraform_data.configure
```

Dabei wird nur der Einrichtungsschritt erneut ausgeführt, nicht die VM ersetzt.

### Inhalt und bewusste Entscheidungen

- Fedora-Pakete: Moby/Docker-Engine und Docker CLI, kind, git, k9s, kubectl, Tilt, Helm, OpenSSL, mkcert, yq, wget, curl, Vim und Archivwerkzeuge. Docker wird gestartet und dauerhaft aktiviert.
- Der SSH-Benutzer erhält Zugriff auf Docker über die Gruppe `docker` (entspricht weitreichenden Root-Rechten). Bei bereits offener SSH-Sitzung neu anmelden.
- Go 1.27.3 unter `/opt/go-1.27.3`, verlinkt über `/usr/local/go`. PATH wird für den SSH-Benutzer und root ergänzt, vorhandene Bash-Einstellungen bleiben erhalten.
- Go Task als Nightly unter `/usr/local/bin/task`. Das mehrdeutige Fedora-Paket `task` und das zwischenzeitlich wieder entfernte Cloudsmith-Repository aus der History werden nicht installiert. Downloads werden gegen veröffentlichte SHA256-Prüfsummen geprüft.
- `ansible/settings.yml` steuert Go-Version, Task-Release und optionales Klonen von Platform Mesh. Das Repository wurde in deiner History zuletzt gelöscht; deshalb ist `clone_platform_mesh: false` voreingestellt. Bei `true` wird es im Home-Verzeichnis des SSH-Benutzers angelegt. Bestehende lokale Änderungen werden nicht zurückgesetzt.
- `helm registry login ghcr.io`, `task tilt:ci` und `mkcert -install` werden nicht automatisch ausgeführt. Das Playbook installiert Werkzeuge, startet aber keinen Kubernetes-Cluster oder Projektstack und erzeugt keine lokale CA.
- Nightly und Fedora-Pakete sind nicht auf exakte Builds fixiert. Für reproduzierbare Task-Builds `task_release` auf einen festen Release-Tag setzen. Ein neuer Nightly-Build allein löst keinen OpenTofu-Lauf aus.
- Hostschlüssel werden beim ersten Kontakt automatisch akzeptiert und unter `ansible/.runtime/known_hosts` gespeichert. Weitere Verbindungen prüfen sie. Jede neu erstellte Azure-VM erhält über ihre UUID einen eigenen Hostalias; die Datei nicht unnötig löschen.

### Prüfumfang

Ansible-Syntax und OpenTofu-Konfiguration werden lokal geprüft. Die Paketinstallation und das komplette Zusammenspiel sind noch nicht auf einer Fedora-VM ausgeführt worden. DNF-Paketnamen orientieren sich an deiner erfolgreichen manuellen Installation; falls Fedora-Repositories diese ändern, bricht Ansible mit dem konkreten Paketnamen ab.

Quellen: https://opentofu.org/docs/language/resources/tf-data/ und https://taskfile.dev/docs/installation
