#!/bin/bash

if [[ "$(id -u)" -ne "0" ]]; then
  echo -e "\nТребуются root права"
  exit 1
fi

#Может быть установлен только внутри рабочей системы
#https://saby.ru/help/plugin/sbis3plugin/install_notconnection
#https://saby.ru/help/start/teh_terms/sbisplugin/install/not_start?tb=tab2
function sbis_install_internet {
  echo -e "\n----- Проверка обновлений sbis -----"

  #-----
  function install_sbis {
    cd /tmp

    echo -e "\nЗагрузка и установка файла $name_debfile\n"

    wget --no-http-keep-alive --unlink --timeout=15 "$link_download_file" --output-document="$name_debfile.deb" && apt -y install /tmp/$name_debfile.deb

    if [[ "$?" -ne "0" ]]; then
      echo -e "\nНе удалось скачать или установить пакет."
      exit 1
    fi
  }

  #-----
  function check_version {
    if [[ -z "$version_current" ]]; then
      echo -e "\n$name_debfile не установлен"
      install_sbis
      return 0
    fi

    if [[ -z "$version_last" ]]; then
      echo -e "\nНе удалось получить значение последней версии"
      exit 1
    fi

    if [[ "$(echo "$version_current" | tr "-" "." | grep "$version_last" | wc -l)" -eq "1" ]]; then
      echo -e "\nОбновление не требуется"
      return 0
    else
      install_sbis
    fi
  }

  #-----
  name_debfile="sabycenter"

  unset version_current
  unset version_last

  version_current="$(dpkg -s $name_debfile 2>/dev/null | grep '^Version:' | awk '{ print $2}')"

  version_last="$(curl -L 'https://update.saby.ru/SabyCenter/master/linux/version.txt' 2>/dev/null)"

  link_download_file="https://update.saby.ru/SabyCenter/master/linux/sabycenter.deb"

  check_version

  #-----
  name_debfile="nmh-transport"

  unset version_current
  unset version_last

  version_current="$(dpkg -s $name_debfile 2>/dev/null | grep '^Version:' | awk '{ print $2}')"

  version_last="$(curl -L 'https://update.saby.ru/NmhTransport/master/linux/version.txt' 2>/dev/null)"

  link_download_file="https://update.saby.ru/NmhTransport/master/linux/nmh-transport.deb"

  check_version

  #-----
  name_debfile="saby"

  version_current="$(dpkg -s $name_debfile 2>/dev/null | grep '^Version:' | awk '{ print $2}')"

  version_last="$(curl -L 'https://update.saby.ru/SabyDesktop/master/linux/version.txt' 2>/dev/null)"

  link_download_file="https://update.saby.ru/SabyDesktop/master/linux/saby.deb"

  check_version
}

#Функция ответа Да/Нет
function yesorno {

  while true; do
    read -p "$infmsg" ynaction

    case $ynaction in
    [Yy])
      ynaction="yes"
      return 0
      ;;
    [Nn])
      echo "$errmsg"
      break
      ;;
    esac
  done

}

echo "Установить SABY из интернета? (Подключите репозитории для установки необходимых зависимостей)"
infmsg="Продолжить? [y/n]: "
errmsg="Пропуск"
yesorno

if [[ "$ynaction" = "yes" ]]; then
  sbis_install_internet
fi
