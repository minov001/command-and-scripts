#!/bin/bash

# 1.Формируем список соответствий "имя.local IP"
# ippfind находит .local имена, а getent hosts резолвит их в IP
ipp_map="$(ippfind --exec echo '{service_hostname}' \; 2>/dev/null | while read -r host; do
    # Убираем точку на конце (например, "printer.local." -> "printer.local")
    host_clean="${host%.}"

    # Узнаем IP-адрес для этого хоста
    ip=$(getent hosts "$host_clean" | awk '{print $1}')

    # Если IP успешно найден, сохраняем пару "хост IP"
    if [[ -n "$ip" ]]; then
        echo "$host_clean $ip"
    fi
done)"

# 2. Обрабатываем вывод airscan-discover
airscan-discover | sed '/^\[devices\]$/d; s/^[[:space:]]*//' | while read -r line; do
    # Если строка пустая или без знака "=", выводим без изменений
    if [[ ! "$line" =~ "=" ]]; then
        echo "$line"
        continue
    fi

    # Извлекаем IP-адрес из текущей строки airscan-discover
    ip=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

    # Ищем .local имя в списке по совпадению IP
    domain=$(echo "$ipp_map" | grep -E "[[:space:]]${ip}$" | awk '{print $1}')
    target="${domain:-$ip}"

    # Оборачиваем левую часть в кавычки и заменяем IP на .local домен
    #echo "$line" | sed -E "s/^([^=]*[^= ]+)([ ]*)=(.*)$/\"\1\"\2=\3/; s/$ip/$target/"
    echo "$line" | sed -E "s/^[^=]*[^= ]+/\"$target\"/; s/$ip/$target/"
done
