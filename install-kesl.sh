#!/bin/bash

check_path='^[A-Za-zА-Яа-я0-9(),./@_[:space:]-]+$'

let reinstall_agent=0

while [[ -n "$1" ]]; do
  case "$1" in
  -ra)
    let reinstall_agent=1
    ;;
  *)
    echo -e "
#----- Допустимые параметры запуска -----#

-ra) - Переустановить агент администрирования. Необходимо при изменении файла ответов (например, при смене сервера администрирования)"
    exit 1
    ;;
  esac
  shift
done

#Проверка полного пути запускаемого скрипта на допустимые символы
if ! [[ "$(realpath "$0")" =~ $check_path ]]; then
  echo -e "\nПуть к запускаемому скрипту содержит запрещенные символы." >&2
  exit 1
else
  #Запись пути к каталогу в переменную (каталог с файлом скрипта)
  dir_runscript="$(dirname "$(realpath "$0")")"
fi

cd "$dir_runscript"

if [[ "$(id -u)" -ne "0" ]]; then
  echo -e "\nТребуются root права"
  exit 1
fi

#Может быть установлен только внутри рабочей системы
echo -e "\n-----Установка Kaspersky-----"

list_files[0]='./klnagent.deb'
list_files[1]='./kesl.deb'
list_files[2]='./kesl-gui.deb'

if ! [[ -f "${list_files[0]}" ]] || ! [[ -f "${list_files[1]}" ]] || ! [[ -f "${list_files[2]}" ]]; then
  echo ""

  [[ -f "${list_files[0]}" ]] || echo "${list_files[0]} - не найден"
  [[ -f "${list_files[1]}" ]] || echo "${list_files[1]} - не найден"
  [[ -f "${list_files[2]}" ]] || echo "${list_files[2]} - не найден"

  echo ""
  exit 0
fi

#Подробно про установку агента в тихом режиме и список параметров тут: https://support.kaspersky.com/KSCLinux/15/ru-RU/199693.htm

export KLAUTOANSWERS="/tmp/answers-kaspersky-agent.txt"

export KESL_ANSWERS="/tmp/answers-kesl.txt"

echo -e 'KLNAGENT_AUTOINSTALL=1
EULA_ACCEPTED=1
KLNAGENT_SERVER=server.test.local
KLNAGENT_PORT=14000
KLNAGENT_SSLPORT=13000
KLNAGENT_USESSL=1
KLNAGENT_GW_MODE=1' >"$KLAUTOANSWERS"

#В Astra linux отсутствует SElinux, поэтому параметр CONFIGURE_SELINUX ниже равен no.

#Список всех параметров тут: https://support.kaspersky.ru/kes-for-linux/12.0/236945?ysclid=mhx91uqsbv98644423

echo -e "EULA_AGREED=yes
PRIVACY_POLICY_AGREED=yes
KSVLA_MODE=no
SERVER_MODE=no
VDI_MODE=no
USE_KSN=no
GROUP_CLEAN=no
UPDATER_SOURCE=SCServer
UPDATE_EXECUTE=no
KERNEL_SRCS_INSTALL=yes
ADMIN_USER=$(id -u -n 1000)
CONFIGURE_SELINUX=no
DISABLE_PROTECTION=no" >"$KESL_ANSWERS"

if [[ "$reinstall_agent" -eq "1" ]]; then
  apt -y purge klnagent64
fi

#Установка из deb файлов
apt update && apt -y install ${list_files[0]} && apt -y install ${list_files[1]} && /opt/kaspersky/kesl/bin/kesl-setup.pl --autoinstall="$KESL_ANSWERS" && apt -y install ${list_files[2]}

#Установка по имени пакета из репозитория
#apt update && apt -y install klnagent64 && apt -y install kesl && /opt/kaspersky/kesl/bin/kesl-setup.pl --autoinstall="$KESL_ANSWERS" && apt -y install kesl-gui

if [[ "$?" -ne "0" ]]; then
  echo -e "\nНе удалось скачать или установить пакет."
  exit 1
fi

function kesl_ptrace {
  echo "#!/bin/bash

IFS=$'\n'

if [[ -d /opt/kaspersky ]]; then
find /opt/kaspersky/ -type f -executable -exec setcap cap_sys_ptrace=eip \"{}\" \;

#find /opt/kaspersky/ -type f -exec getfattr -d -m - \"{}\" \;
else
echo -e '\nКаталог /opt/kaspersky не найден'
fi

if [[ -d /var/opt/kaspersky ]]; then
find /var/opt/kaspersky/ -type f -executable -exec setcap cap_sys_ptrace=eip \"{}\" \;

#find /var/opt/kaspersky/ -type f -exec getfattr -d -m - \"{}\" \;
else
echo -e '\nКаталог /var/opt/kaspersky не найден'
fi
" >/usr/local/sbin/kesl-ptrace && chmod 700 /usr/local/sbin/kesl-ptrace

  echo 'SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
@reboot    root    /usr/local/sbin/kesl-ptrace' >'/etc/cron.d/kesl-ptrace' && chmod 600 "/etc/cron.d/kesl-ptrace" && echo -e "\nЗадача cron создана"
}

#Если в системе ptrace не разрешен, то для корректной работы дать права ptrace для kaspersky (необходимо дать права на исполняемые файлы, но для простоты в команде ищутся все файлы в каталогах kaspersky).
kesl_ptrace
