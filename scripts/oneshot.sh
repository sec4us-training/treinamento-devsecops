#!/usr/bin/env bash
#
# Run one or more Ansible playbooks across a fleet of hosts. Generic
# wrapper used for ad-hoc rollouts (e.g. installing the Jenkins runner,
# preparing the Azure DevOps runner, hot-patching nginx).
#
# Usage:
#   scripts/oneshot.sh [-k <ssh_key>] [-u <ssh_user>] <ips_file> <playbook> [playbook ...]
#
#   <ips_file>  one IP/hostname per line; '#' comments and blank lines
#               are ignored.
#   <playbook>  Ansible playbook to run. Multiple playbooks may be
#               passed; they run sequentially against the same inventory.
#
# Options:
#   -k, --key    Path to the SSH private key (default: ~/.ssh/id_rsa,
#                or $SSH_KEY).
#   -u, --user   SSH user (default: root, or $ANSIBLE_USER).
#   -h, --help   Show this help.
#
# Examples:
#   scripts/oneshot.sh /tmp/ips.txt prepare_azure_devops.yml
#   scripts/oneshot.sh -k ~/.ssh/lab /tmp/ips.txt fix_jenkins_nginx_websocket.yml install_jenkins_runner.yml

set -euo pipefail

W='\033[0m'
R='\033[31m'
G='\033[32m'
O='\033[33m'
C='\033[36m'

err()  { echo -e "${R}[!]${W} $*" >&2; }
info() { echo -e "${G}[+]${W} $*"; }
warn() { echo -e "${O}[?]${W} $*"; }

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
ANSIBLE_USER="${ANSIBLE_USER:-root}"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -k|--key)
            [[ $# -ge 2 ]] || { err "$1 requires a value"; exit 1; }
            SSH_KEY="$2"
            shift 2
            ;;
        -u|--user)
            [[ $# -ge 2 ]] || { err "$1 requires a value"; exit 1; }
            ANSIBLE_USER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            POSITIONAL+=("$@")
            break
            ;;
        -*)
            err "Unknown option: $1"
            usage >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
    err "Usage: $0 [-k ssh_key] [-u ssh_user] <ips_file> <playbook> [playbook ...]"
    exit 1
fi

IPS_FILE="${POSITIONAL[0]}"
PLAYBOOKS=("${POSITIONAL[@]:1}")

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

# Resolve each playbook relative to the repo root if it is not an
# absolute path; verify it exists before any host is touched.
RESOLVED_PLAYBOOKS=()
for pb in "${PLAYBOOKS[@]}"; do
    if [[ "$pb" = /* ]]; then
        candidate="$pb"
    elif [[ -f "$pb" ]]; then
        candidate="$pb"
    else
        candidate="$REPO_ROOT/$pb"
    fi
    if [[ ! -f "$candidate" ]]; then
        err "Playbook not found: $pb"
        exit 1
    fi
    RESOLVED_PLAYBOOKS+=("$candidate")
done

INVENTORY="$(mktemp -t oneshot_inv.XXXXXX)"
trap 'rm -f "$INVENTORY"' EXIT

{
    echo "[targets]"
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
info "Playbooks (${#RESOLVED_PLAYBOOKS[@]}):"
for pb in "${RESOLVED_PLAYBOOKS[@]}"; do
    echo "    - ${pb#"$REPO_ROOT/"}"
done
info "SSH user: ${ANSIBLE_USER}    SSH key: ${SSH_KEY}"

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_DEPRECATION_WARNINGS=False
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

run_play() {
    local playbook="$1"
    local label="${playbook#"$REPO_ROOT/"}"

    echo
    info "Running ${C}${label}${W}"
    ansible-playbook \
        -i "$INVENTORY" \
        --user "$ANSIBLE_USER" \
        --private-key "$SSH_KEY" \
        --ssh-extra-args "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15" \
        "$playbook"
}

for pb in "${RESOLVED_PLAYBOOKS[@]}"; do
    run_play "$pb"
done

echo
info "All hosts processed successfully."
