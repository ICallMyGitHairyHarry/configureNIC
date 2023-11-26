#!/bin/bash

trap 'rm -f .selected_nic .menuchoice .nic_form' EXIT

nic_number=$(ip -br link show | wc -l)
nic_array=()

for (( i = 1; i<=$nic_number; i++))
do
	nic_array[i*2 - 2]=$i
	nic_array[i*2 - 1]=$(ip -br link show | awk -v column=$i 'NR==column {print $1}')
done
# nic_array содержит массив сетевых интерфейсов: (1 lo 2 enp0s3)

while :
do
    whiptail --title "Просмотр и настройка сетевой карты" --menu "Выберите сетевую карту. Для выхода нажмите \"Отмена\" или \"Esc\"." 14 50 5 ${nic_array[@]} 2>.selected_nic

    if [ $? -ne 0 ]
    then
    	clear
    	echo "Ждем вас снова!"
    	break
    fi
    while :
    do
    nic=${nic_array[$(cat .selected_nic)*2 - 1]}
    	whiptail --title "Сетевая карта $nic" --menu "Выберите действие:" 15 60 4 \
       	1 "Посмотреть данные карты"\
       	2 "Посмотреть конфигурацию IPv4"\
       	3 "Настроить карту"\
       	4 "Выюрать другую карту"\
       	2>.menuchoice
       	
       	if [ $? -ne 0 ]; then break; fi
       	
       	systemctl start systemd-resolved.service
       	
        choice=$(cat .menuchoice)
        case $choice in
          1)
            whiptail --title "Данные карты $nic" --msgbox "\
            Модель: $(lspci | grep -i 'net' | \
            # так как первый nic = lo, то вычитаем 1
            awk -v nic_spot=$(($(cat .selected_nic) - 1)) \
            'NR==nic_spot {$1=$2=$3=""; print $0}') \n\
            Канальная скорость: $(sudo ethtool $nic | grep Speed \
            | awk ' {print $2}') \n\
            Режим работы: $(sudo ethtool $nic | grep Duplex \
            | awk ' {print $2}') Duplex \n\
            Физическое подключение: $(sudo ethtool $nic | grep "Link detected"\
            | awk ' {print $3}') \n\
            MAC-адрес: $(sudo ethtool -P $nic | awk ' {print $3}')" 15 60;;
          2)
            whiptail --title "Конфигурация IPv4 $nic" --msgbox "\
            IPv4/Маска:
            $(ip -o -f inet a show $nic | awk '{printf "%s\n            ",$4}') \n\
            Шлюз по умолчанию: $(ip route show dev $nic | grep default \
            | awk '{print $3}') \n\n\
            DNS (global;link): $(cat /etc/resolv.conf | awk 'NR==2 {print $2}'); $(resolvectl dns | grep $nic | awk '{print $4}' )" 15 60;;
          3)
           whiptail --title "Настройка карты $nic" --menu "Выберите способ настройки" 15 60 4 \
           1 "Статический"\
           2 "Динамический"\
           2>.menuchoice
           choice=$(cat .menuchoice)
           case $choice in
           1)
           	input_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
           	error_notifier=0
           	dialog --title "Настройка карты $nic" --form "Заполните нужные поля в формате \"?*.?*.?*.?*\". Если вы не хотите изменять определённые параметры, оставьте соответствующее поле пустым." 17 50 0 \
           	"IPv4:" 1 1 "" 1 10 30 0 \
           	"Маска:" 2 1 "" 2 10 30 0 \
           	"Шлюз:" 3 1 "" 3 10 30 0 \
           	"DNS:" 4 1 "" 4 10 30 0 2> .nic_form
           	while read line
           	do
           		if [ -z "$line" ]
           		then continue
           		fi
           		if ! [[ $line =~ $input_regex ]]
           		then
					whiptail --title "Неверный ввод!" --msgbox "Каждое поле в вода должно быть в формате \"?*.?*.?*.?*\"!" 10 30
					error_notifier=1
					break
				fi
           	done < .nic_form
           	if [ $error_notifier -ne 1 ]
           	then
           		success_string=""
           		ip addr add $(sed -n '1p' .nic_form)/$(sed -n '2p' .nic_form) dev $nic 2> /dev/null
           		if [ $? -eq 0 ] 
           		then success_string+="IPv4 и маска настроены успешно.\n"
           		fi
           		if ! [ -z "$(sed -n '3p' .nic_form)" ]
           		then
           			ip route del default dev $nic 2> /dev/null
					ip route add default via $(sed -n '3p' .nic_form) dev $nic 2> /dev/null
					if [ $? -eq 0 ]
					then success_string+="Шлюз по умолчанию настроен успешно.\n"
					fi
				fi
				resolvectl dns $nic $(sed -n '4p' .nic_form) > .nic_form 2> /dev/null
				# теперь в .nic_form хранится вывод команды resolvectl, при успешной настройке этот вывод является пустой строкой.
				if [ $? -eq 0 ] && [ -z "$(cat .nic_form)" ]
				then success_string+="DNS настроен успешно."
				fi
				if [ -z "$success_string" ]
				then success_string="Произошла ошибка при настройке карты: неверно заполнены поля формы или произошла системная ошибка."
				fi
				whiptail --title "Карта $nic" --msgbox "$(echo -e $success_string)" 10 40
           	fi;;
           2)
           	sudo dhclient -r &> /dev/null
            sudo dhclient -v $nic 2>&1 | awk -v i=0 '{i+=7} {print i}' | dialog --gauge "Настройка карты $nic" 10 50 0
            if [ $? -eq 0 ]
            then
           		whiptail --msgbox "Карта $nic успешно настроена в соответствии с новыми параметрами." 10 30
            else
            	whiptail --msgbox "Произшла ошибка при динамической настройке." 10 30
           fi;;
           esac;;
            4)
            break;;
        esac
	done
done
