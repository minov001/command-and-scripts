#!/bin/bash
IFS=$'\n'

which rename >/dev/null || exit 1

#Формирование списка исключая файл скрипта
dir_list_content=($(ls -1 | grep -v "$(basename $0)" | sort -n))

#Используется для числового значения нового имени (начальное число).
let coldir=0
let colfile=0
echo -e "\nЗначений в списке: ${#dir_list_content[@]}"

#Перебор массива
for (( f=0; f < ${#dir_list_content[@]}; f++)); do

#Если элемент является каталогом, то расширение пустое
if [[ -d "${dir_list_content[$f]}" ]]; then
extension=""

#Закомментировать 2 строки ниже, если раскомментировано случайное имя
let coldir+=1
let newname=$coldir
else
#Запись текущего расширения файла, если есть
extension="$([[ "$(awk -F\. '{print $NF}' <<<"${dir_list_content[$f]}")" == "${dir_list_content[$f]}" ]] && echo "" || echo ".$(awk -F\. '{print $NF}' <<<"${dir_list_content[$f]}")")"

#Закомментировать 2 строки ниже, если раскомментировано случайное имя
let colfile+=1
let newname=$colfile
fi

#Раскомментировать нужное, если необходимо случайное имя.
#newname="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 30)"
#newname="$(tr -dc '0-9' </dev/urandom | head -c 30)"

#Выполнение команды переименования
eval "rename -v 's/^(.+)${extension}$/${newname}${extension}/i' \"${dir_list_content[$f]}\""
done

echo -e "\nЗавершено"
