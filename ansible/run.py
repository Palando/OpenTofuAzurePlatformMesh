#!/usr/bin/env python3
"""Local Ansible launcher. No private key content is read into OpenTofu."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent
key = Path(os.environ['DEV_SSH_KEY']).expanduser().resolve()
if not key.is_file():
    raise SystemExit(f'SSH-Schlüssel nicht gefunden: {key}')
if not shutil.which('ansible-playbook'):
    raise SystemExit('ansible-playbook fehlt auf dem Rechner, auf dem tofu apply läuft.')
identity = os.environ['DEV_VM_ID']
if not re.fullmatch(r'[a-zA-Z0-9-]+', identity):
    raise SystemExit('Ungültige VM-ID für SSH-Hostalias')
state = root / '.runtime'
state.mkdir(mode=0o700, exist_ok=True)
# First contact is accepted; changed keys for the same VM are rejected.
# A new Azure VM UUID gets a fresh alias even if its public IP was reused.
ssh_args = shlex.join([
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', f'UserKnownHostsFile={state / "known_hosts"}',
    '-o', f'HostKeyAlias=azure-{identity}',
    '-o', 'IdentitiesOnly=yes',
])
inventory = {'all': {'children': {'dev': {'hosts': {'fedora': {
    'ansible_host': os.environ['DEV_HOST'],
    'ansible_user': os.environ['DEV_USER'],
    'ansible_ssh_private_key_file': str(key),
    'ansible_ssh_common_args': ssh_args,
    'ansible_python_interpreter': '/usr/bin/python3',
}}}}}}
with tempfile.TemporaryDirectory(prefix='inventory-', dir=state) as temp:
    path = Path(temp) / 'inventory.json'
    path.write_text(json.dumps(inventory))
    path.chmod(0o600)
    result = subprocess.run(['ansible-playbook', '-i', str(path), str(root / 'dev.yml')])
    raise SystemExit(result.returncode)
