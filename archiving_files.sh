#!/bin/bash
IFS=$'\n'

#Формирование списка исключая файл скрипта
dir_list_content=($(find -type f | grep -v "$(basename $0)" | grep -v 'archive-directory/' | sort -n))
dirname_out="archive-directory/$(date +"%Y%m%d-%H%M%S")"

mkdir -p "$dirname_out" || exit 1

#Размер архива в байтах
let size_arch=9900000

let num_arch=1
let num_big_arch=0

let summa=0

#Перебор массива
for ((i = 0; i < ${#dir_list_content[@]}; i++)); do

  #Размер файла/директории
  size_fd="$(du -s --bytes "${dir_list_content[$i]}" | awk '{print $1}')"

  #Если сумма с учетом файла будет меньше установленного размера архива, то добавить файл к архиву
  if [[ "$(expr $summa + $size_fd)" -le "$size_arch" ]]; then
    let summa+=$size_fd

    zip "$dirname_out/$num_arch.zip" "${dir_list_content[$i]}"
  else
    #Если сумма будет превышена, то проверка, что размер файла меньше установленного размера архива и добавление файла к новому архиву
    if [[ "$size_fd" -le "$size_arch" ]]; then

      #Присвоить сумме размер элемента
      let summa=$size_fd
      #Увеличить номер архива на 1
      let num_arch+=1

      zip "$dirname_out/$num_arch.zip" "${dir_list_content[$i]}"
    else
      let num_big_arch+=1

      #Если размер файла больше установленного размера архива, то создать архив с припиской big
      zip "$dirname_out/big$num_big_arch.zip" "${dir_list_content[$i]}"
    fi
  fi
done

echo -e "\nЗавершено. Файлы находятся в каталоге $dirname_out"
echo -e "\nСоздано архивов: $num_arch"
echo -e "\nСоздано больших архивов (файл/каталог без сжатия больше установленного размера архива): $num_big_arch"
