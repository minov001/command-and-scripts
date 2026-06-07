#!/bin/bash

[[ "$SCRIPT_RUN_FROM_SYSTEMD" = "yes" ]] || exit 0

function exit_err {
systemctl --user stop check-kerberos-active-user.timer
sleep 5
exit 0
}

[[ "$(id -u)" -le "15000" || -z "$USER_DOMAIN_LOGIN" ]] && exit_err

#Проверка доступности домена
nslookup "$USER_DOMAIN_LOGIN" >/dev/null || exit 0

#Проверка статуса блокировки текущей сессии. Выполнить, если сессия разблокирована.
if [[ "$(loginctl show-session -p LockedHint $XDG_SESSION_ID | cut -d '=' -f2)" = "no" ]]; then

#Проверка наличия активного kerberos билета. Если билета нет, то вывод сообщения
klist -A -s || notify-send -t 600000 -i dialog-warning 'Проверка данных авторизации' 'Данные авторизации устарели (сетевые папки недоступны). Выполните один из вариантов: 1.Выход из сессии и повторная авторизация; 2.Перезагрузка ПК'
fi
