#!/bin/bash

if [[ "$(id -u)" -ne "0" ]]; then
  echo -e "\nТребуются root права"
  exit 1
fi

if [[ -n "$(which chromium 2>/dev/null)" ]]; then
  echo -e "\nУстановлен оригинальный chromium. Проверка пропущена."
  exit 0
fi

echo -e "\n----- Проверка обновлений chromium-gost -----"

function install_chromium {
  link_download_file="$(curl -L -s 'https://api.github.com/repos/deemru/chromium-gost/releases/latest' | grep "browser_download_url" | grep "linux-amd64.deb" | awk '{ print $2}' | awk -F'"' '$0=$2')"

  if [[ -z "$link_download_file" ]]; then
    echo -e "\nНе удалось получить ссылку на загрузку файла"
    exit 0
  fi

  cd /tmp

  echo -e '\nЗагрузка и установка файла\n'

  wget --no-http-keep-alive --unlink --timeout=15 "$link_download_file" --output-document="chromium-gost.deb" && apt -y install /tmp/chromium-gost.deb

  if [[ "$?" -ne "0" ]]; then
    echo -e "\nНе удалось скачать или установить пакет."
  fi
  exit 0
}

version_current="$(dpkg -s chromium-gost-stable 2>/dev/null | grep '^Version:' | awk '{ print $2}')"

if [[ -z "$version_current" ]]; then
  echo -e "\nchromium-gost-stable не установлен"
  install_chromium
fi

version_last="$(curl -L 'https://update.cryptopro.ru/get/chromium-gost/version' 2>/dev/null)"

if [[ -z "$version_last" ]]; then
  echo -e "\nНе удалось получить значение последней версии"
  exit 0
fi

if [[ "$(echo "$version_current" | grep "$version_last" | wc -l)" -eq "1" ]]; then
  echo -e "\nОбновление не требуется"
  exit 0
else
  install_chromium
fi
