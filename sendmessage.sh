#!/bin/bash

#Проверка root прав
if [[ "$(id -u)" -ne "0" ]]; then
  echo -e "\nТребуются права root для выполнения скрипта\n"
  exit 1
fi

#Отчистка переменных
function unset_param {
  unset send_notifysend
  unset notifysend_expiretime
  unset send_first_found_dialog
  unset send_yad
  unset send_flydialog
  unset send_zenity
  unset send_msg_use_root
  unset activeusername
  unset rdpuser
  unset headertext
  unset sesman_pid
  unset sesman_children
  unset pidsession
  unset templistpid
  unset msgfile
  unset file_msg
  unset cur_date
  unset end_date
}

#Вывод сообщения с параметрами запуска
function help_run {
  echo -e "
#----- Допустимые параметры запуска -----#

Скрипт должен быть запущен как минимум с одним из параметров метода вывода сообщения (-sn, -sffd, -sy, -sfd, -sz) и текстом сообщения (методы ввод смотрите ниже).
Неуказанные параметры будут использовать значения по умолчанию.

#-----Методы вывода сообщения-----#

-sn) (send notify-send) - Вывести сообщение через notify-send.

-sffd) (send first found dialog) - Вывести сообщение через первое найденное диалоговое окно. Порядок проверки соответствует порядку в массиве list_dialog_sendmsg. При указании этого параметра, параметры -sy, -sfd, -sz не учитываются.

-sy) (send yad) - Вывести сообщение через yad.

-sfd) (send fly-dialog) - Вывести сообщение через fly-dialog

-sz) (send zenity) - Вывести сообщение через zenity

#--Методы ввода текста сообщения--#

Файлы сообщений с расширением .smsg ищутся в каталоге /tmp/.msg. В качестве альтернативы или дополнительно к файлам сообщений вы можете использовать параметры -mt или -simt.

-mt 'Текст сообщения') (msg text) - Текст сообщения для показа. Параметр может быть указан более одного раза. Подходит для вывода небольших сообщений. При выводе больших сообщений вы можете упереться в ограничения командной строки.

-simt \"Число\") (stdin msg text) - Перенаправьте текст или результат выполнения другой команды в скрипт через pipe для вывода сообщения, например 'echo тест1 | sendmessage.sh -sn -simt'. Данный параметр обрабатывается один раз. Число указывает на то, сколько секунд необходимо ждать данные ввода в stdin (0 - не ограничено).

#-----Дополнительные параметры----#

-et \"Число\") (expire time) - Время существования сообщения в секундах. По умолчанию 0 - уведомление автоматически не исчезает.

-h 'Значение') (header) - Заголовок сообщения. Если сообщений несколько, то указанный заголовоу применяется ко всем выводимым сообщениям. Если не задавать параметр, то используется генерируемое по умолчанию значение (Уведомление %d.%m.%Y-%H:%M)

-u \"Значение\") (username) - Имя пользователя, которому вывести сообщение. Параметр может быть указан более одного раза. Если используется, то значение должно начинаться с буквы, может содержать допустимые символы @._- и должно заканчиваться буквой или цифрой.

-ur) (systemd-run use root) - По умолчанию команда systemd-run запускает команду вывода сообщения от имени пользователя, которому выводится сообщение (рекомендуемый вариант). Данный параметр указывает, чтобы процесс создавался от имени root. Этот параметр влияет только на то, кому принадлежит процесс. Не влияет на вывод через notify-send.

Пример команды запуска: sendmessage.sh -sn -et '3600' -mt 'Тестовое сообщение 1!!!' -mt 'Тестовое сообщение 2!!!' -h 'Тестовое сообщение!!!'"

  unset_param
  exit 1
}

unset_param

#Проверка числовой строки
check_num='^[0-9]+$'

#Проверка имени пользователя и группы, что оно начинается с буквы, содержит допустимый набор символов и заканчиваетсся буквой или цифрой
check_login_or_group='^[A-Za-zА-Яа-я][A-Za-zА-Яа-я0-9@._-]+[A-Za-zА-Яа-я0-9]$'

check_path='^[A-Za-zА-Яа-я0-9(),./@_[:space:]-]+$'
check_empty='^$'

#Создаем каталог для файлов сообщений и выставляем права
msgdir="/tmp/.sendmsg"
dirfiles="/tmp/.msg"
mkdir -p "$msgdir"
chmod 755 "$msgdir"
mkdir -p "$dirfiles"

let std_msg=0

#Инициализируем пустой массив
msgfile=()
activeusername=()

IFS=$'\n'

#Обработка переданных параметров
while [[ -n "$1" ]]; do
  case "$1" in
  -sn)
    let send_notifysend=1
    ;;
  -sffd)
    let send_first_found_dialog=1
    ;;
  -sy)
    let send_yad=1
    ;;
  -sfd)
    let send_flydialog=1
    ;;
  -sz)
    let send_zenity=1
    ;;
  -et)
    if ! [[ "$2" =~ $check_num ]]; then
      echo -e "\nЗначение параметра '-et' не является числом." >&2
      unset_param
      exit 1
    else
      let notifysend_expiretime=$2
    fi
    shift
    ;;
  -ur)
    let send_msg_use_root=1
    ;;
  -mt)
    if ! [[ "$2" =~ $check_empty ]]; then
      #Формуруем путь к файлу в котором будет сообщение
      msgfile[${#msgfile[@]}]="$msgdir/.msg-$(date +"%Y%m%d%H%M%S")-$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 3)"

      #Перенаправляем вывод в файл
      printf %b "$2" >"${msgfile[${#msgfile[@]} - 1]}"

      #Выставляем права на файл
      chmod 644 "${msgfile[${#msgfile[@]} - 1]}"
    else
      echo -e "\nЗначение параметра '-mt' пустое." >&2
      unset_param
      exit 1
    fi
    shift
    ;;
  -simt)
    if ! [[ "$2" =~ $check_num ]]; then
      echo -e "\nЗначение параметра '-simt' не является числом." >&2
      unset_param
      exit 1
    fi

    if [[ "std_msg" -eq "0" ]]; then
      if [[ -p /dev/stdin ]]; then
        sleep 1
        end_date="$(expr "$(date +%s)" + $2)"
        while true; do
          if read -t 0; then
            msgfile[${#msgfile[@]}]="$msgdir/.msg-$(date +"%Y%m%d%H%M%S")-$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 3)"

            cat >"${msgfile[${#msgfile[@]} - 1]}"

            chmod 644 "${msgfile[${#msgfile[@]} - 1]}"

            if [[ "$(grep -Ev "^$" <"${msgfile[${#msgfile[@]} - 1]}" | wc -l)" -eq "0" ]]; then
              echo -e "\nУказан параметр '-simt'. Стандартный ввод пуст" >&2
              unset_param
              exit 1
            fi

            let std_msg=1

            break
          fi

          if [[ "$2" -gt "0" ]]; then
            if [[ "$(date +%s)" -ge "$end_date" ]]; then
              echo -e "\nЗакончился таймаут ожидания стандартного ввода." >&2
              unset_param
              exit 1
            fi
          fi
          sleep 1
        done
      else
        echo -e "\nstdin не является pipe. Перенаправьте текст или результат выполнения другой команды в скрипт через pipe для вывода сообщения, например 'echo тест1 | sendmessage.sh -sn -simt'"
        unset_param
        exit 1
      fi
    fi
    shift
    ;;
  -u)
    if ! [[ "$2" =~ $check_login_or_group ]]; then
      echo -e "\nЗначение параметра '-u' не соответствует условию. Значение должно начинаться с буквы, может содержать допустимые символы @._- и должно заканчиваться буквой или цифрой." >&2
      unset_param
      exit 1
    else
      activeusername[${#activeusername[@]}]="$2"
    fi
    shift
    ;;
  -h)
    if ! [[ "$2" =~ $check_empty ]]; then
      headertext="$(cat <<<"$2")"
    else
      echo -e "\nЗначение параметра '-h' пустое" >&2
      unset_param
      exit 1
    fi
    shift
    ;;
  *)
    help_run
    ;;
  esac
  shift
done

#Поиск всех активных пользователей
function search_active_users {
  echo -e "\nПоиск активных пользователей\n"
  unset activeusername
  unset rdpuser

  #Формирование списка активных пользователей из вывода who -u (уникальные записи)
  if [[ "$(who -u | grep -v pts | awk '{print $1}' | sort -u | grep -Ev '^$' | wc -l)" -gt "0" ]]; then
    readarray -d ';' -t activeusername < <(who -u | grep -v pts | awk '{print $1}' | sort -u | grep -Ev '^$' | tr '\n' ';' 2>/dev/null)
  fi

  #Определение номера процесса xrdp-sesman
  sesman_pid=$(ps --no-header -o ppid,pid -C xrdp-sesman | awk '$1==1 {print $2}')

  #Если номер найден, то ищем номера подчиненных процессов
  if [[ "$sesman_pid" =~ $check_num ]]; then
    sesman_children=($(ps --no-header -o pid --ppid "$sesman_pid" | sed 's/[[:space:]]//g'))

    #Продолжаем, если найдены номера подчиненных процессов
    if [[ "${#sesman_children[@]}" -gt "0" ]]; then

      #Определяем пользователя подключившегося по rdp
      for ((num_sc = 0; num_sc < ${#sesman_children[@]}; num_sc++)); do
        rdpuser="$(ps --no-header -o user --ppid "${sesman_children[$num_sc]}" | sed -n '2p')"

        if [[ -n "$rdpuser" ]]; then
          #Если массив активных пользователей пуст, то добавляем пользователя в массив, если же массив не пуст, то выполняем проверку на наличие данного пользователя в массиве
          if [[ ${#activeusername[@]} -eq "0" ]]; then
            activeusername=("$rdpuser")
          elif [[ ${#activeusername[@]} -gt "0" ]]; then
            if [[ "$(sed 's/^ //' <<<"${activeusername[@]/%/$'\n'}" | grep "^$rdpuser$" | wc -l)" -eq "0" ]]; then
              activeusername=("${activeusername[@]}" "$rdpuser")
            fi
          fi
        fi
      done
    fi
  fi

  unset rdpuser

  echo -e "Найдено активных пользователей: ${#activeusername[@]}\n"
}

#Поиск значений переменных окружения пользователя
function search_env_value {

  #Поиск всех активных пользователей, если массив пуст
  if [[ "${#activeusername[@]}" -eq "0" ]]; then
    search_active_users
  fi

  #Продолжаем, если список не пуст
  if [[ "${#activeusername[@]}" -gt "0" ]]; then

    #Если список процессов пуст, то задать фиксированный список
    if [[ ${#processname[@]} -eq "0" ]]; then
      #Имя процессов, по которым можно определить DISPLAY, DBUS_SESSION_BUS_ADDRESS и XAUTHORITY. Необходимо в случаях, если команда who -u не выдаст нужные pid (например pid может быть неверным или пользователь подключен через xrdp, тогда его не будет в выводе команды who -u)
      processname=("astra-event-watcher" "fly-wm" "startplasma-wayland" "startplasma-x11" "xfce4-session" "openbox" "mate-session" "lxqt-session" "lxsession" "x-session-manager" "gnome-software" "cinnamon-session")
    fi

    unset pidsession
    unset templistpid

    #Определение PID процессов принадлежащих пользователю через who -u
    if [[ "$(who -u | grep -w "${activeusername[$num_au]}" | awk '{print $6}' | sort -u | grep -E '^[0-9]+$' | wc -l)" -gt "0" ]]; then
      readarray -d ';' -t pidsession < <(who -u | grep -w "${activeusername[$num_au]}" | awk '{print $6}' | sort -u | grep -E '^[0-9]+$' | tr '\n' ';' 2>/dev/null)
    fi

    #Перебор массива с именами процессов
    for ((num_proc_name = 0; num_proc_name < ${#processname[@]}; num_proc_name++)); do
      #Определение PID указанных процессов принадлежащих пользователю
      templistpid=($(pgrep -f "${processname[$num_proc_name]}" -u "${activeusername[$num_au]}"))

      #Если PID найдены, то перебор массива
      for ((num_pid_proc = 0; num_pid_proc < ${#templistpid[@]}; num_pid_proc++)); do

        #Продолжаем, если значение является числом
        if [[ "${templistpid[$num_pid_proc]}" =~ $check_num ]]; then

          #Cверка уникальности PID и добавление значения к основному массиву
          if [[ "$(sed 's/^ //' <<<"${pidsession[@]/%/$'\n'}" | grep "^${templistpid[$num_pid_proc]}$" | wc -l)" -eq "0" ]]; then
            pidsession=("${pidsession[@]}" "${templistpid[$num_pid_proc]}")
          fi
        fi
      done
    done

    #Присвоить, если список переменных окружения не определен
    if [[ ${#list_search_env[@]} -eq "0" ]]; then
      list_search_env=('DBUS_SESSION_BUS_ADDRESS' 'XAUTHORITY')
    fi

    #Инициализация пустых массивов
    for ((numenv = 0; numenv < ${#list_search_env[@]}; numenv++)); do
      eval "env_${list_search_env[$numenv]}=()"
    done

    env_DISPLAY=()

    #Перебор массива значений PID.
    for ((numcicle = 0; numcicle < ${#pidsession[@]}; numcicle++)); do
      unset temp_num_disp

      #Получаем значение дисплея
      temp_num_disp="$(cat "/proc/${pidsession[$numcicle]}/environ" | tr '\0' '\n' 2>/dev/null | sed -nr "{ :l /^DISPLAY[ ]*=/ { s/[^=]*=[ ]*//; p; q;}; n; b l;}")"

      #Продолжаем, если значение не пусто
      if [[ -n "$temp_num_disp" ]]; then

        if [[ "$(sed 's/^ //' <<<"${env_DISPLAY[@]/%/$'\n'}" | grep "^$temp_num_disp$" | wc -l)" -eq "0" ]]; then
          #Добавляем значение к массиву
          env_DISPLAY[${#env_DISPLAY[@]}]="$temp_num_disp"

          #Перебор указанного списка переменных окружения
          for ((numenv = 0; numenv < ${#list_search_env[@]}; numenv++)); do

            #Запись значения в массив
            eval "env_${list_search_env[$numenv]}[\${#env_${list_search_env[$numenv]}[@]}]=\"$(cat "/proc/${pidsession[$numcicle]}/environ" | tr '\0' '\n' 2>/dev/null | sed -nr "{ :l /^${list_search_env[$numenv]}[ ]*=/ { s/[^=]*=[ ]*//; p; q;}; n; b l;}")\""
          done
        fi
      fi
    done

    unset pidsession
    unset templistpid

  #         echo -e "\nПользователь: ${activeusername[$num_au]}"
  #         echo -e "\nЗначений DISPLAY: ${#env_DISPLAY[@]}"
  #         echo "Значения DISPLAY:
  # $(echo "${env_DISPLAY[@]/%/$'\n'}" | sed 's/^ //')"
  #         echo -e "\nЗначений DBUS_SESSION_BUS_ADDRESS: ${#env_DBUS_SESSION_BUS_ADDRESS[@]}"
  #         echo "Значения DBUS_SESSION_BUS_ADDRESS:
  # $(echo "${env_DBUS_SESSION_BUS_ADDRESS[@]/%/$'\n'}" | sed 's/^ //')"
  #         echo -e "\nЗначений XAUTHORITY: ${#env_XAUTHORITY[@]}"
  #         echo "Значения XAUTHORITY:
  # $(echo "${env_XAUTHORITY[@]/%/$'\n'}" | sed 's/^ //')"
  fi
}

#Показать сообщение активным пользователям
function send_message_active_users {
  #---Проверка значений и назначение 0, если не число---#
  if ! [[ "$send_notifysend" =~ $check_num ]]; then
    let send_notifysend=0
  fi

  if ! [[ "$notifysend_expiretime" =~ $check_num ]]; then
    let notifysend_expiretime=0
  fi

  if ! [[ "$send_yad" =~ $check_num ]]; then
    let send_yad=0
  fi

  if ! [[ "$send_flydialog" =~ $check_num ]]; then
    let send_flydialog=0
  fi

  if ! [[ "$send_zenity" =~ $check_num ]]; then
    let send_zenity=0
  fi

  if ! [[ "$send_msg_use_root" =~ $check_num ]]; then
    let send_msg_use_root=0
  fi
  #-----------------------------------------------------#

  #Если send_first_found_dialog равен 1, то присваиваем значение 0 переменным send_yad, send_flydialog, send_zenity и ищем первое доступное диалоговое окно для использования
  if [[ "$send_first_found_dialog" -eq "1" ]]; then
    let send_yad=0
    let send_flydialog=0
    let send_zenity=0

    #Список значений для проверки в формате (имя-исполняемого-файла;имя-переменной)
    list_dialog_sendmsg=('yad;send_yad' 'zenity;send_zenity' 'fly-dialog;send_flydialog')

    for ((num_lds = 0; num_lds < ${#list_dialog_sendmsg[@]}; num_lds++)); do

      #Если исполняемый файл найден в системе, то присваиваем значение 1 соответствующей переменной и выходим из цикла
      if [[ -n "$(which "$(echo "${list_dialog_sendmsg[$num_lds]}" | cut -d ';' -f 1)" 2>/dev/null)" ]]; then
        eval "let $(echo "${list_dialog_sendmsg[$num_lds]}" | cut -d ';' -f 2)=1"
        break
      fi
    done
  fi

  #Для продолжения должен быть включен как минимум один вариант вывода сообщения
  if [[ "$send_notifysend" -eq "1" ]] || [[ "$send_yad" -eq "1" ]] || [[ "$send_flydialog" -eq "1" ]] || [[ "$send_zenity" -eq "1" ]]; then

    #Поиск всех активных пользователей, если массив пуст
    if [[ "${#activeusername[@]}" -eq "0" ]]; then
      search_active_users
    else
      echo -e "\nИспользуется подготовленный список пользователей"
    fi

    #Продолжаем, если список не пуст
    if [[ "${#activeusername[@]}" -gt "0" ]]; then

      #Выполнить условие, если каталог существует
      if [[ -d "$dirfiles" ]]; then

        cd "$dirfiles"
        #Переходим в каталог и ищем файлы .smsg. Если файлы найдены, то продолжаем
        if [[ "$(ls -1 | grep '.smsg' | wc -l)" -gt "0" ]]; then

          #Перебор файлов .smsg
          for file_msg in $(ls -1 | grep '.smsg'); do

            #Формуруем путь к файлу в котором будет сообщение
            msgfile[${#msgfile[@]}]="$msgdir/.msg-$(date +"%Y%m%d%H%M%S")-$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 3)"

            #Копируем файл
            cp -f -v "$dirfiles/$file_msg" "${msgfile[${#msgfile[@]} - 1]}"

            #Назначаем права
            chmod 644 "${msgfile[${#msgfile[@]} - 1]}"
          done
          unset file_msg
        fi
        cd "/tmp"
        rm -fR "$dirfiles"
      fi

      #Продолжаем, если список файлов с текстом сообщения не пуст
      if [[ "${#msgfile[@]}" -gt "0" ]]; then

        headertext_generate="0"

        #Перебор списка пользователей
        for ((num_au = 0; num_au < ${#activeusername[@]}; num_au++)); do

          #Запуск поиска необходимых переменных окружения
          search_env_value

          #Продолжаем, если список номеров дисплея не пуст
          if [[ "${#env_DISPLAY[@]}" -gt "0" ]]; then

            #Перебор массива номеров дисплея
            for ((numenv = 0; numenv < ${#env_DISPLAY[@]}; numenv++)); do

              #Если headertext пуст или включена генерация, то задать значение
              if [[ -z "$headertext" ]] || [[ "$headertext_generate" -eq "1" ]]; then
                headertext="Уведомление $(date +"%d.%m.%Y-%H:%M")"
                headertext_generate="1"
              fi

              echo ""
              echo "Найден пользователь ${activeusername[$num_au]} - ${env_DISPLAY[$numenv]}"

              #Если отправка через notify-send
              if [[ "$send_notifysend" -eq "1" ]]; then

                if [[ -n "$(which notify-send 2>/dev/null)" ]]; then

                  if [[ -n "${env_DISPLAY[$numenv]}" && -n "${env_DBUS_SESSION_BUS_ADDRESS[$numenv]}" && -n "${env_XAUTHORITY[$numenv]}" ]]; then

                    for ((num_msg = 0; num_msg < ${#msgfile[@]}; num_msg++)); do
                      cmd_run_send_msg="systemd-run --uid=\"${activeusername[$num_au]}\" /bin/bash -c \"XAUTHORITY='${env_XAUTHORITY[$numenv]}' DBUS_SESSION_BUS_ADDRESS='${env_DBUS_SESSION_BUS_ADDRESS[$numenv]}' DISPLAY='${env_DISPLAY[$numenv]}' notify-send -t $(expr $notifysend_expiretime \* 1000) '$(sed 's/\\/\\\\/g;s/"/\\"/g;s/`/\\`/g' <<<"$headertext" | sed "s/'/\'\\\\\\\'\'/g")' '$(cat ${msgfile[$num_msg]} | sed 's/\\/\\\\\\/g;s/&/\\\&/g;s/%/\\%/g;s/"/\\"/g;s/`/\\`/g;s/<//g' | sed "s/'/\'\\\\\\\'\'/g")'\""

                      eval "$cmd_run_send_msg"
                    done
                  fi
                else
                  echo -e "\nnotify-send не найден" >&2
                fi
              fi

              #Если отправка через yad
              if [[ "$send_yad" -eq "1" ]]; then

                if [[ -n "$(which yad 2>/dev/null)" ]]; then

                  if [[ -n "${env_DISPLAY[$numenv]}" && -n "${env_XAUTHORITY[$numenv]}" ]]; then

                    for ((num_msg = 0; num_msg < ${#msgfile[@]}; num_msg++)); do
                      cmd_run_send_msg="systemd-run $([[ "$send_msg_use_root" -eq "0" ]] && echo "--uid=\"${activeusername[$num_au]}\" ")/bin/bash -c \"XAUTHORITY='${env_XAUTHORITY[$numenv]}' DISPLAY='${env_DISPLAY[$numenv]}' yad --timeout=$notifysend_expiretime --no-escape --on-top --center --text-info --button=OK:0 --filename='${msgfile[$num_msg]}' --title='$(sed 's/\\/\\\\/g;s/"/\\"/g;s/`/\\`/g' <<<"$headertext" | sed "s/'/\'\\\\\\\'\'/g")' --wrap --width 350 --height 300 --show-uri --window-icon=''\""

                      eval "$cmd_run_send_msg"
                    done
                  fi
                else
                  echo -e "\nyad не найден" >&2
                fi
              fi

              #Если отправка через fly-dialog
              if [[ "$send_flydialog" -eq "1" ]]; then

                if [[ -n "$(which fly-dialog 2>/dev/null)" ]]; then

                  if [[ -n "${env_DISPLAY[$numenv]}" && -n "${env_XAUTHORITY[$numenv]}" ]]; then

                    for ((num_msg = 0; num_msg < ${#msgfile[@]}; num_msg++)); do
                      cmd_run_send_msg="systemd-run $([[ "$send_msg_use_root" -eq "0" ]] && echo "--uid=\"${activeusername[$num_au]}\" ")/bin/bash -c \"XAUTHORITY='${env_XAUTHORITY[$numenv]}' DISPLAY='${env_DISPLAY[$numenv]}' timeout -k 5 ${notifysend_expiretime}s fly-dialog --caption '$(sed 's/\\/\\\\/g;s/"/\\"/g;s/`/\\`/g' <<<"$headertext" | sed "s/'/\'\\\\\\\'\'/g")' --textbox '${msgfile[$num_msg]}'\""

                      eval "$cmd_run_send_msg"
                    done
                  fi
                else
                  echo -e "\nfly-dialog не найден" >&2
                fi
              fi

              #Если отправка через zenity
              if [[ "$send_zenity" -eq "1" ]]; then

                if [[ -n "$(which zenity 2>/dev/null)" ]]; then

                  if [[ -n "${env_DISPLAY[$numenv]}" && -n "${env_XAUTHORITY[$numenv]}" ]]; then

                    for ((num_msg = 0; num_msg < ${#msgfile[@]}; num_msg++)); do
                      cmd_run_send_msg="systemd-run $([[ "$send_msg_use_root" -eq "0" ]] && echo "--uid=\"${activeusername[$num_au]}\" ")/bin/bash -c \"XAUTHORITY='${env_XAUTHORITY[$numenv]}' DISPLAY='${env_DISPLAY[$numenv]}' zenity --modal --timeout $notifysend_expiretime --text-info --filename='${msgfile[$num_msg]}' --title='$(sed 's/\\/\\\\/g;s/"/\\"/g;s/`/\\`/g' <<<"$headertext" | sed "s/'/\'\\\\\\\'\'/g")'\""

                      eval "$cmd_run_send_msg"
                    done
                  fi
                else
                  echo -e "\nzenity не найден" >&2
                fi
              fi
            done
          else
            echo -e "\nНе обнаружено пользовательских дисплеев у пользователя ${activeusername[$num_au]}"
          fi
        done
      else
        echo -e "\nНет сообщений для вывода. Создайте файлы с расширением .smsg в каталоге /tmp/.msg или передайте текст сообщения через параметр -mt" >&2
      fi
    else
      echo -e "\nСписок пользователей пуст. Нет активных пользователей или не заполнен массив пользователей (в случае показа сообщения определенным пользователям)" >&2
    fi
  else
    echo -e "\nВсе методы вывода сообщения отключены" >&2
    return 1
  fi
}

send_message_active_users
