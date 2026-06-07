#!/bin/bash

#Завершить, если запущено не из systemd
[[ "$SCRIPT_RUN_FROM_SYSTEMD" = "yes" ]] || exit 0

function exit_err {
  systemctl --user stop check-expire-userpas-AD.timer
  sleep 5
  exit 0
}

#Остановить таймер, если хоть одно из условий выполнено
[[ "$(grep "^$USER:" /etc/passwd | grep ":$(id -u):" | wc -l)" -gt "0" || -z "$USER_DOMAIN_LOGIN" ]] && exit_err

#Функция завершения при ошибке. Остановить основной таймер, включить альтернативный с уменьшенным временем таймера и завершить скрипт
function exit_err {
  systemctl --user is-active check-expire-userpas-AD.timer && systemctl --user stop check-expire-userpas-AD.timer

  systemctl --user is-active check-expire-userpas-AD-2h.timer || systemctl --user start check-expire-userpas-AD-2h.timer
  sleep 5
  exit 0
}

#Проверка доступности домена
nslookup "$USER_DOMAIN_LOGIN" >/dev/null || exit_err

#Вывод уведомления
function send_notify_pas {

  response=""

  #Если fly-passwd найден, то вывести уведомление с кнопкой вызова смены пароля. Если нет, то просто уведомление.
  if [[ -n "$(which fly-passwd 2>/dev/null)" ]]; then

    response="$(timeout --preserve-status 10h notify-send 'Срок действия пароля' "$msg_text" -t 36000000 --action 'change-pas=Изменить пароль' 2>/dev/null)"
  else
    notify-send 'Срок действия пароля' "$msg_text" -t 28800000
  fi

  systemctl --user is-active check-expire-userpas-AD-2h.timer && systemctl --user stop check-expire-userpas-AD-2h.timer

  systemctl --user is-active check-expire-userpas-AD.timer || systemctl --user start check-expire-userpas-AD.timer

  #Если в уведомлении была нажата кнопка "Изменить пароль", то вызов fly-passwd
  case "$response" in
  "change-pas")
    fly-passwd
    ;;
  *)
    echo "Уведомление закрыто без выбора"
    ;;
  esac

  sleep 5
  exit 0
}

#Выполнить, если сессия разблокирована и есть актуальный kerberos билет
if [[ "$(loginctl show-session -p LockedHint $XDG_SESSION_ID | cut -d '=' -f2)" = "no" ]] && [[ "$(klist -A -s && echo "1" || echo "0")" -eq "1" ]]; then

  #Проверка по фильтру, что строка является числом
  check_num='^[0-9]+$'

  #Получаем имя основного контроллера
  primary_DC="$(dig +short -t SRV _ldap._tcp.pdc._msdcs.$USER_DOMAIN_LOGIN | awk '{print $4}' | sed 's/\.$//' | head -n 1 | grep -Ev "^$")"

  list_DC=()

  #Если не пусто, то добавляем в нулевой элемент массива
  if [[ -n "$primary_DC" ]]; then
    list_DC[0]="$primary_DC"
  fi

  unset temp_value

  #Ищем и добавляем к массиву остальные контроллеры
  for temp_value in $(dig +short -t SRV _ldap._tcp.dc._msdcs.$USER_DOMAIN_LOGIN | awk '{print $4}' | sed 's/\.$//' | grep -Eiv "^$primary_DC$"); do

    list_DC[${#list_DC[@]}]="$temp_value"
  done

  #Перебор элементов массива
  for ((nm = 0; nm < ${#list_DC[@]}; nm++)); do

    if [[ "$(ping -c 2 -i 1 "${list_DC[$nm]}" &>/dev/null && echo "1" || echo "0")" -eq "1" ]]; then

      #Записываем ответ от сервера в переменную
      server_response="$(ldapsearch -Y GSSAPI -H "ldap://${list_DC[$nm]}" -b "dc=$(echo "$USER_DOMAIN_LOGIN" | cut -d '.' -f 1),dc=$(echo "$USER_DOMAIN_LOGIN" | cut -d '.' -f 2)" "(sAMAccountName=$(echo $USER | cut -d '@' -f1))" msDS-UserPasswordExpiryTimeComputed pwdLastSet 2>/dev/null | grep -Ei "^msDS-UserPasswordExpiryTimeComputed|^pwdLastSet" | grep -v "^$")"

      #Получаем значение окончания действия пароля из домена в формате windows time
      expire_date="$(echo "$server_response" | grep -Ei "^msDS-UserPasswordExpiryTimeComputed" | cut -d " " -f2 | grep -v "^$")"

      #Если получено не числовое значение, то переход к следующему контроллеру
      if [[ "$expire_date" =~ $check_num ]]; then

        #Если значение 0, то сразу вызываем показ уведомления
        if [[ "$expire_date" -eq "0" ]]; then

          msg_text="$(echo -e "Требуется изменить пароль для входа в систему по требованию администратора.")"

          send_notify_pas
        fi

        #Преобразуем значение в формат unix time
        expire_date="$(expr $(expr $expire_date / 10000000) - 11644473600)"

        #Если дата окончания меньше текущей даты, то вывести уведомление
        if [[ "$expire_date" -le "$(date -u +%s)" ]]; then

          msg_text="$(echo -e "Срок действия вашего пароля для входа в систему истёк: $(date -d @"$expire_date").\nТребуется изменить пароль.")"

          send_notify_pas
        fi

        #Если пароль истекает меньше, чем через 10 дней, то вывести уведомление
        if [[ "$(expr $(expr $expire_date - $(date -u +%s)) / 3600)" -le "240" ]]; then

          msg_text="$(echo -e "Ваш пароль для входа в систему истекает: $(date -d @"$expire_date").\nОставшееся время (в часах): $(expr $(expr $expire_date - $(date -u +%s)) / 3600)")"

          send_notify_pas
        fi

        #Если в системе присутствует gnome-keyring
        if [[ -n "$(which gnome-keyring 2>/dev/null)" ]]; then

          #Получаем значение окончания действия пароля из домена в формате windows time
          setpas_date="$(echo "$server_response" | grep -Ei "^pwdLastSet" | cut -d " " -f2 | grep -v "^$")"

          #Если значение является числом
          if [[ "$setpas_date" =~ $check_num ]]; then

            if [[ "$setpas_date" -gt "0" && "$(expr $(expr $setpas_date / 10000000) - 11644473600)" -lt "$(date -u +%s)" ]]; then

              #Если смена пароля произведена менее 5 минут назад, т.е. с экрана авторизации, то вывести уведомление о связке ключей
              if [[ "$(expr $(date -u +%s) - $(expr $(expr $setpas_date / 10000000) - 11644473600))" -le "300" ]]; then

                notify-send 'Обновление связки ключей' "Для обновления пароля на связке ключей вам необходимо ввести однократно предыдущий пароль входа в систему и нажать кнопку 'Разблокирование'" -t 0
              fi
            fi
          fi
        fi

        #Если предыдущие условия не подошли, т.е. пароль не нужно менять, то проверяем таймеры и завершаем скрипт
        systemctl --user is-active check-expire-userpas-AD-2h.timer && systemctl --user stop check-expire-userpas-AD-2h.timer

        systemctl --user is-active check-expire-userpas-AD.timer || systemctl --user start check-expire-userpas-AD.timer

        sleep 5
        exit 0
      else
        continue
      fi
    fi
  done

  #Если перебраны все элементы массива, то вызываем функцию
  exit_err
else
  exit_err
fi
