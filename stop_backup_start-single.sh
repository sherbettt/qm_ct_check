#!/bin/bash

VM_ID=$1  #Присваивает переменной VM_ID значение первого аргумента командной строки

# Проверка, что номер контейнера введен
if [ -z "$VM_ID" ]; then
    echo "Ошибка: Не указан номер контейнера"
    echo "Использование: $0 <ID_контейнера>"
    exit 1
fi

# Проверка, что введено число
if ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
    echo "Ошибка: Номер контейнера должен быть числом"
    echo "Использование: $0 <ID_контейнера>"
    exit 1
fi


if pct status $VM_ID >/dev/null 2>&1; then
    echo "Stopping container $VM_ID..."
    pct stop $VM_ID
    sleep 2
fi


find /stg/ -name "vzdump-lxc-${VM_ID}-*.tar.zst"
find_dump=$(find /stg/ -name "vzdump-lxc-${VM_ID}-*.tar.zst" | head -1)
echo "Последний доступный дамп:  $find_dump"

#pct restore $VM_ID /stg/1tb/dump/vzdump-lxc-${VM_ID}-*.tar.zst --storage ssd_1tb --force && pct start $VM_ID
pct restore $VM_ID $find_dump --storage ssd_1tb --force && pct start $VM_ID


# для групповго восстановления бекапа
# echo {210..213} | xargs -n 1 ./stop_backup_start.sh
