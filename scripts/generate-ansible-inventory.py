#!/usr/bin/env python3
"""
Generate Ansible inventory from Terraform outputs.
This ensures Terraform is the single source of truth for VM node configuration.
Bare metal nodes are preserved from existing config and not overwritten.

Features:
- Auto-generates VM workers from Terraform outputs
- Preserves manually configured baremetal_workers section
- Can auto-detect disks on bare metal nodes via talosctl (--detect-baremetal-disks)
"""

import json
import sys
import subprocess
import re
import argparse
from pathlib import Path


def get_baremetal_disks(ip: str) -> dict:
    """
    Query a bare metal node's disks via talosctl and determine install/longhorn disks.

    Logic:
    - Install disk: Prefer NVMe, fallback to smallest non-USB disk
    - Longhorn disk: Largest non-NVMe disk (SATA/SAS SSD preferred)

    Returns dict with 'install_disk' and 'longhorn_disk' or None if unreachable.
    """
    try:
        result = subprocess.run(
            ['talosctl', 'get', 'disks', '-n', ip, '--insecure', '-o', 'json'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode != 0:
            print(f"   ⚠ Could not query disks on {ip}: {result.stderr.strip()}", file=sys.stderr)
            return None

        disks = []
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            try:
                disk_data = json.loads(line)
                spec = disk_data.get('spec', {})
                disk_id = disk_data.get('metadata', {}).get('id', '')

                # Skip loop devices and read-only disks
                if disk_id.startswith('loop') or spec.get('readonly', False):
                    continue

                # Skip very small disks (likely USB boot media < 10GB)
                size = spec.get('size', 0)
                if size < 10 * 1024 * 1024 * 1024:  # 10GB
                    continue

                disks.append({
                    'id': disk_id,
                    'size': size,
                    'size_gb': round(size / (1024**3), 1),
                    'transport': spec.get('transport', ''),
                    'model': spec.get('model', ''),
                    'is_nvme': disk_id.startswith('nvme'),
                    'is_sata': spec.get('transport', '') == 'sata',
                })
            except json.JSONDecodeError:
                continue

        if not disks:
            print(f"   ⚠ No suitable disks found on {ip}", file=sys.stderr)
            return None

        # Sort disks: NVMe first, then by size
        nvme_disks = [d for d in disks if d['is_nvme']]
        non_nvme_disks = [d for d in disks if not d['is_nvme']]

        # Install disk: prefer smallest NVMe, fallback to smallest non-NVMe
        if nvme_disks:
            install_disk = min(nvme_disks, key=lambda d: d['size'])
        else:
            install_disk = min(non_nvme_disks, key=lambda d: d['size'])

        # Longhorn disk: prefer largest non-NVMe (SATA SSD), fallback to largest NVMe
        if non_nvme_disks:
            longhorn_disk = max(non_nvme_disks, key=lambda d: d['size'])
        elif len(nvme_disks) > 1:
            # If only NVMe disks, use largest one for Longhorn (different from install)
            longhorn_disk = max([d for d in nvme_disks if d['id'] != install_disk['id']],
                               key=lambda d: d['size'], default=None)
        else:
            longhorn_disk = None

        # Don't use same disk for both
        if longhorn_disk and longhorn_disk['id'] == install_disk['id']:
            longhorn_disk = None

        result = {
            'install_disk': f"/dev/{install_disk['id']}",
            'install_disk_info': f"{install_disk['model']} ({install_disk['size_gb']}GB)",
        }

        if longhorn_disk:
            result['longhorn_disk'] = f"/dev/{longhorn_disk['id']}"
            result['longhorn_disk_info'] = f"{longhorn_disk['model']} ({longhorn_disk['size_gb']}GB)"

        return result

    except subprocess.TimeoutExpired:
        print(f"   ⚠ Timeout querying disks on {ip}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"   ⚠ Error querying disks on {ip}: {e}", file=sys.stderr)
        return None


def get_ip_from_dns(hostname):
    """Get IP from DNS lookup (assumes DHCP reservation is configured)."""
    try:
        result = subprocess.run(
            ['dig', '+short', f'{hostname}.lab.jamilshaikh.in'],
            capture_output=True,
            text=True,
            timeout=5
        )
        ip = result.stdout.strip()
        if ip and not ip.startswith(';'):
            return ip
    except Exception as e:
        print(f"Warning: Could not resolve {hostname}.lab.jamilshaikh.in: {e}", file=sys.stderr)

    # Fallback to hardcoded IPs based on naming convention
    if 'cp-01' in hostname:
        return '10.20.0.40'
    elif 'wk-01' in hostname:
        return '10.20.0.41'
    elif 'wk-02' in hostname:
        return '10.20.0.42'
    elif 'wk-03' in hostname:
        return '10.20.0.43'
    return 'unknown'

def extract_baremetal_section(file_path):
    """Extract the baremetal_workers section from existing vars file if it exists."""
    if not file_path.exists():
        return None

    with open(file_path) as f:
        content = f.read()

    # Look for baremetal_workers section - stop at next top-level key (no indentation)
    # Match from "baremetal_workers:" until we hit a line starting with a lowercase letter followed by colon
    match = re.search(
        r'(# Bare metal workers[^\n]*\n(?:#[^\n]*\n)*baremetal_workers:\n(?:[ \t]+[^\n]*\n)*)',
        content,
        re.MULTILINE
    )
    if match:
        return match.group(1).rstrip()
    return None

def main():
    # Parse arguments
    parser = argparse.ArgumentParser(
        description='Generate Ansible inventory from Terraform outputs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                           # Generate inventory, preserve baremetal section
  %(prog)s --detect-baremetal-disks  # Auto-detect disks on bare metal nodes
  %(prog)s --baremetal-ip 10.20.0.45 # Add/update a bare metal node with auto disk detection
        """
    )
    parser.add_argument(
        '--detect-baremetal-disks',
        action='store_true',
        help='Auto-detect disks on existing bare metal nodes via talosctl'
    )
    parser.add_argument(
        '--baremetal-ip',
        type=str,
        help='IP of a bare metal node to add/update with auto disk detection'
    )
    parser.add_argument(
        '--baremetal-hostname',
        type=str,
        default='talos-wk-04',
        help='Hostname for the bare metal node (default: talos-wk-04)'
    )
    args = parser.parse_args()

    # Read Terraform output
    terraform_json = Path(__file__).parent.parent / 'ansible' / 'terraform-inventory.json'

    if not terraform_json.exists():
        print(f"Error: {terraform_json} not found", file=sys.stderr)
        print("Run 'make terraform-apply' first", file=sys.stderr)
        sys.exit(1)

    with open(terraform_json) as f:
        terraform_data = json.load(f)

    # Extract control plane
    controlplane_vms = terraform_data.get('controlplane_vms', {}).get('value', {})
    if not controlplane_vms:
        print("Error: No control plane VMs found in Terraform output", file=sys.stderr)
        sys.exit(1)

    cp_name = list(controlplane_vms.keys())[0]
    cp_data = controlplane_vms[cp_name]
    cp_vmid = int(cp_data['id'].split('/')[-1])
    cp_ip = get_ip_from_dns(cp_name)

    # Extract workers (VMs only)
    worker_vms = terraform_data.get('worker_vms', {}).get('value', {})
    workers = []

    for worker_name in sorted(worker_vms.keys()):  # Sort for consistent order
        worker_data = worker_vms[worker_name]
        worker_vmid = int(worker_data['id'].split('/')[-1])
        worker_ip = get_ip_from_dns(worker_name)

        workers.append({
            'hostname': worker_name,
            'ip': worker_ip,
            'vmid': worker_vmid
        })

    # Check for existing baremetal_workers section to preserve
    output_file = Path(__file__).parent.parent / 'ansible' / 'roles' / 'talos-cluster' / 'vars' / 'main.yml'
    baremetal_section = extract_baremetal_section(output_file)

    # Generate Ansible vars YAML
    ansible_vars = f"""---
# Talos Cluster Configuration Variables
# VM workers are AUTO-GENERATED from Terraform outputs
# Bare metal workers (baremetal_workers) are manually maintained - DO NOT DELETE
# Generated by: scripts/generate-ansible-inventory.py

# Cluster configuration
cluster_name: "homelab-cluster"
cluster_endpoint: "https://{cp_ip}:6443"  # Control plane IP

# Default install disk (used if not specified per node)
default_install_disk: "/dev/sda"

# Default Longhorn disk (used for storage on all nodes)
default_longhorn_disk: "/dev/sdb"

# Talos node configuration
# - install_disk: optional, defaults to default_install_disk
# - longhorn_disk: optional, dedicated disk for Longhorn storage (defaults to default_longhorn_disk)
talos_nodes:
  control_plane:
    hostname: "{cp_name}"
    ip: "{cp_ip}"
    vmid: {cp_vmid}
    longhorn_disk: "/dev/sdb"  # 500GB for Longhorn
  # VM workers (from Terraform)
  workers:
"""

    for worker in workers:
        ansible_vars += f"""    - hostname: "{worker['hostname']}"
      ip: "{worker['ip']}"
      vmid: {worker['vmid']}
      longhorn_disk: "/dev/sdb"  # 500GB for Longhorn
"""

    # Handle bare metal nodes
    baremetal_generated = False

    # If --baremetal-ip is provided, auto-detect disks and generate config
    if args.baremetal_ip:
        print(f"   🔍 Detecting disks on bare metal node {args.baremetal_ip}...")
        disk_info = get_baremetal_disks(args.baremetal_ip)
        if disk_info:
            install_disk = disk_info['install_disk']
            longhorn_disk = disk_info.get('longhorn_disk', '/dev/sda')
            ansible_vars += f"""
# Bare metal workers (manually maintained - not managed by Terraform)
# Disks auto-detected via: scripts/generate-ansible-inventory.py --baremetal-ip {args.baremetal_ip}
baremetal_workers:
  - hostname: "{args.baremetal_hostname}"
    ip: "{args.baremetal_ip}"
    install_disk: "{install_disk}"   # {disk_info.get('install_disk_info', 'Auto-detected')}
    longhorn_disk: "{longhorn_disk}"       # {disk_info.get('longhorn_disk_info', 'Auto-detected')}
"""
            baremetal_generated = True
            print(f"   ✓ Auto-detected disks for {args.baremetal_hostname}:")
            print(f"     - Install: {install_disk} ({disk_info.get('install_disk_info', '')})")
            print(f"     - Longhorn: {longhorn_disk} ({disk_info.get('longhorn_disk_info', '')})")
        else:
            print(f"   ⚠ Could not detect disks, preserving existing config")

    # If --detect-baremetal-disks and we have existing baremetal section, try to update it
    if args.detect_baremetal_disks and baremetal_section and not baremetal_generated:
        # Extract IPs from existing baremetal section
        ip_match = re.search(r'ip:\s*["\']?(\d+\.\d+\.\d+\.\d+)["\']?', baremetal_section)
        hostname_match = re.search(r'hostname:\s*["\']?([^"\']+)["\']?', baremetal_section)
        if ip_match:
            bm_ip = ip_match.group(1)
            bm_hostname = hostname_match.group(1) if hostname_match else 'talos-wk-04'
            print(f"   🔍 Detecting disks on existing bare metal node {bm_ip}...")
            disk_info = get_baremetal_disks(bm_ip)
            if disk_info:
                install_disk = disk_info['install_disk']
                longhorn_disk = disk_info.get('longhorn_disk', '/dev/sda')
                ansible_vars += f"""
# Bare metal workers (manually maintained - not managed by Terraform)
# Disks auto-detected via: scripts/generate-ansible-inventory.py --detect-baremetal-disks
baremetal_workers:
  - hostname: "{bm_hostname}"
    ip: "{bm_ip}"
    install_disk: "{install_disk}"   # {disk_info.get('install_disk_info', 'Auto-detected')}
    longhorn_disk: "{longhorn_disk}"       # {disk_info.get('longhorn_disk_info', 'Auto-detected')}
"""
                baremetal_generated = True
                print(f"   ✓ Updated disks for {bm_hostname}:")
                print(f"     - Install: {install_disk} ({disk_info.get('install_disk_info', '')})")
                print(f"     - Longhorn: {longhorn_disk} ({disk_info.get('longhorn_disk_info', '')})")

    # Add baremetal_workers section (preserved or template)
    if not baremetal_generated:
        if baremetal_section:
            ansible_vars += f"""
{baremetal_section}
"""
            print("   ✓ Preserved existing baremetal_workers section")
        else:
            ansible_vars += """
# Bare metal workers (manually maintained - not managed by Terraform)
# Add your bare metal nodes here with custom disk configurations
# Or use: scripts/generate-ansible-inventory.py --baremetal-ip <IP> to auto-detect disks
# baremetal_workers:
#   - hostname: "talos-wk-04"
#     ip: "10.20.0.45"
#     install_disk: "/dev/nvme0n1"   # NVMe for Talos OS
#     longhorn_disk: "/dev/sda"       # SSD for Longhorn storage
"""

    ansible_vars += """
# Proxmox configuration (for cleanup)
proxmox_node: "alif"  # Proxmox node name

# Talos configuration directory (relative to repo root)
talos_config_dir: "{{ playbook_dir }}/../../talos-{{ cluster_name }}"

# CNI to use (none = we'll install Cilium manually)
cni_name: "none"

# Allow scheduling on control plane
allow_scheduling_on_control_planes: true

# Talos version
talos_version: "1.11.5"

# Kubernetes version (must be compatible with Talos version)
kubernetes_version: "1.34.1"

# Cilium version
cilium_version: "1.16.5"

# Wait timeouts (in seconds)
wait_timeout_nodes: 600
wait_timeout_cilium: 300
"""

    # Write to Ansible vars file
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w') as f:
        f.write(ansible_vars)

    print(f"✅ Generated Ansible inventory: {output_file}")
    print(f"   Control Plane: {cp_name} ({cp_ip})")
    print(f"   VM Workers: {len(workers)}")
    for worker in workers:
        print(f"     - {worker['hostname']} ({worker['ip']})")

if __name__ == '__main__':
    main()
