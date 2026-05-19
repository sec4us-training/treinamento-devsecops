#!/usr/bin/env bash
#
# Patches the Jenkins nginx vhost for WebSocket and (re)installs the
# Jenkins runner across a fleet of hosts. Run from your workstation:
#
#   scripts/fleet_install_jenkins_runner.sh ips.txt [ssh_key]
#
# ips.txt: one IP/hostname per line. Lines starting with '#' or empty
# lines are ignored. SSH user defaults to 'root' (override with
# ANSIBLE_USER=...). SSH key defaults to ~/.ssh/id_rsa.
#
# Each target host must already have install_jenkins.yml applied
# (nginx + Jenkins + Vault), since this script only adds the
# WebSocket upgrade headers and provisions the runner.

set -euo pipefail

W='\033[0m'
R='\033[31m'
G='\033[32m'
O='\033[33m'
C='\033[36m'

err()  { echo -e "${R}[!]${W} $*" >&2; }
info() { echo -e "${G}[+]${W} $*"; }
warn() { echo -e "${O}[?]${W} $*"; }

if [[ $# -lt 1 ]]; then
    err "Usage: $0 <ips_file> [ssh_key]"
    exit 1
fi

IPS_FILE="$1"
SSH_KEY="${2:-${HOME}/.ssh/id_rsa}"
ANSIBLE_USER="${ANSIBLE_USER:-root}"

if [[ ! -f "$IPS_FILE" ]]; then
    err "IP list file not found: $IPS_FILE"
    exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
    err "SSH private key not found: $SSH_KEY"
    exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
    err "ansible-playbook not found in PATH. Install with: pip install ansible"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$REPO_ROOT"

for f in fix_jenkins_nginx_websocket.yml install_jenkins_runner.yml vars.yml; do
    if [[ ! -f "$f" ]]; then
        err "Required file missing in repo root ($REPO_ROOT): $f"
        exit 1
    fi
done

INVENTORY="$(mktemp -t jenkins_runner_inv.XXXXXX)"
trap 'rm -f "$INVENTORY"' EXIT

{
    echo "[jenkins_servers]"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(echo "$line" | xargs)"
        [[ -z "$line" ]] && continue
        echo "$line"
    done < "$IPS_FILE"
} > "$INVENTORY"

HOST_COUNT="$(grep -cve '^\[' -e '^$' "$INVENTORY" || true)"
if [[ "$HOST_COUNT" -eq 0 ]]; then
    err "No usable hosts parsed from $IPS_FILE"
    exit 1
fi

info "Targets ($HOST_COUNT):"
grep -v '^\[' "$INVENTORY" | sed 's/^/    - /'

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_DEPRECATION_WARNINGS=False
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

run_play() {
    local playbook="$1"
    local label="$2"

    echo
    info "Running ${C}${label}${W} (${playbook})"
    ansible-playbook \
        -i "$INVENTORY" \
        --user "$ANSIBLE_USER" \
        --private-key "$SSH_KEY" \
        --ssh-extra-args "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15" \
        "$playbook"
}

run_play "fix_jenkins_nginx_websocket.yml" "Nginx WebSocket patch"
run_play "install_jenkins_runner.yml"      "Jenkins runner install"

echo
info "All hosts processed successfully."
