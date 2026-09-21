#!/bin/bash


#
# pve-find-ip.sh — найти LXC/VM по IP во всём кластере Proxmox
#
# Использование:
#   ./pve-find-ip.sh 192.168.87.224
#   ./pve-find-ip.sh 192.168.87.224 --full     # показать весь конфиг
#   ./pve-find-ip.sh 192.168.87.0/24           # поиск по подсети
#   ./pve-find-ip.sh --count                   # только кол-во машин в кластере
#
set -euo pipefail

PVE_NODES="/etc/pve/nodes"

if [[ ! -d "$PVE_NODES" ]]; then
    echo "Ошибка: $PVE_NODES не найден. Запустите на ноде Proxmox." >&2
    exit 1
fi

# ---------- функция: посчитать машины в кластере ----------
count_cluster() {
    local total_lxc=0 total_vm=0
    for node_dir in "$PVE_NODES"/*/; do
        [[ -d "$node_dir" ]] || continue
        if [[ -d "${node_dir}lxc" ]]; then
            total_lxc=$(( total_lxc + $(find "${node_dir}lxc" -maxdepth 1 -name '*.conf' 2>/dev/null | wc -l) ))
        fi
        if [[ -d "${node_dir}qemu-server" ]]; then
            total_vm=$(( total_vm + $(find "${node_dir}qemu-server" -maxdepth 1 -name '*.conf' 2>/dev/null | wc -l) ))
        fi
    done
    echo "=== Кластер Proxmox ==="
    echo "Нод:        $(find "$PVE_NODES" -maxdepth 1 -mindepth 1 -type d | wc -l)"
    echo "LXC:        $total_lxc"
    echo "VM (QEMU):  $total_vm"
    echo "Всего:      $(( total_lxc + total_vm ))"
    echo
}

# ---------- режим --count ----------
if [[ "${1:-}" == "--count" ]]; then
    count_cluster
    exit 0
fi

# ---------- аргументы ----------
if [[ $# -lt 1 ]]; then
    echo "Использование: $0 <IP|CIDR> [--full]" >&2
    echo "               $0 --count" >&2
    exit 1
fi

QUERY="$1"
FULL=0
[[ "${2:-}" == "--full" ]] && FULL=1

# нормализация CIDR -> префикс для grep
if [[ "$QUERY" == */* ]]; then
    PREFIX="${QUERY%/*}"
    MATCH="${PREFIX%.}."
else
    MATCH="$QUERY"
fi

count_cluster   # всегда показываем сводку по кластеру

echo "=== Поиск: $QUERY ==="
echo

FOUND=0

# ---------- функция: разбор LXC ----------
search_lxc() {
    local node_dir="$1" conf="$2" node="$3"
    local vmid name ips
    vmid="$(basename "$conf" .conf)"
    name="$(grep -m1 '^hostname:' "$conf" | awk '{print $2}')"
    ips="$(grep -E '^net[0-9]+:' "$conf" | grep -oE 'ip=[0-9.]+' | cut -d= -f2 | paste -sd, -)"
    echo "[LXC] node=$node vmid=$vmid name=${name:-?} ips=${ips:-?}"
    echo "      config: $conf"
    [[ $FULL -eq 1 ]] && sed 's/^/      | /' "$conf"
    FOUND=$((FOUND+1))
}

# ---------- функция: разбор VM ----------
search_vm() {
    local node_dir="$1" conf="$2" node="$3"
    local vmid name ips
    vmid="$(basename "$conf" .conf)"
    name="$(grep -m1 '^name:' "$conf" | awk '{print $2}')"
    ips="$(grep -E '^ipconfig[0-9]+:' "$conf" | grep -oE 'ip=[0-9.]+' | cut -d= -f2 | paste -sd, -)"
    echo "[VM ] node=$node vmid=$vmid name=${name:-?} ips=${ips:-?}"
    echo "      config: $conf"
    [[ $FULL -eq 1 ]] && sed 's/^/      | /' "$conf"
    FOUND=$((FOUND+1))
}

# ---------- обход всех нод ----------
for node_dir in "$PVE_NODES"/*/; do
    [[ -d "$node_dir" ]] || continue
    node="$(basename "$node_dir")"

    # LXC
    if [[ -d "${node_dir}lxc" ]]; then
        for conf in "${node_dir}"lxc/*.conf; do
            [[ -e "$conf" ]] || continue
            grep -q "$MATCH" "$conf" 2>/dev/null && search_lxc "$node_dir" "$conf" "$node"
        done
    fi

    # QEMU/KVM
    if [[ -d "${node_dir}qemu-server" ]]; then
        for conf in "${node_dir}"qemu-server/*.conf; do
            [[ -e "$conf" ]] || continue
            grep -q "$MATCH" "$conf" 2>/dev/null && search_vm "$node_dir" "$conf" "$node"
        done
    fi
done

echo
if [[ $FOUND -eq 0 ]]; then
    echo "Ничего не найдено по '$QUERY'."
    exit 2
fi
echo "Найдено: $FOUND"
