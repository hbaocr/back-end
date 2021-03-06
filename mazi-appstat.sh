#!/bin/bash

#The mazi-appstat.sh script enables the collection of statistical data from the application installed on the Raspberry Pi 
#and the storage of these data in a local or remote database. In addition , you have the ability to flush these data from 
#tha database in case you do not need them. At the moment, you can collect data from the following applications, Guestbook,Etherpad
#and Framadate. 
#set -x
usage() { 
   echo "Usage: sudo sh mazi-appstat.sh [Application name] [options]" 
   echo " " 
   echo "[Application name]"
   echo "-n,--name         The name of the application"
   echo ""
   echo "--store [enable,disable,flush]       Controls the status of the storage process"
   echo "--status                             Shows the status of storage process " 
   echo "-d,--domain                          Sets the server domain to be used for storage (default is localhost)" 1>&2; exit 1;
}

data_nextcloud(){
  datasize=0
  files=0
  users=$(curl -s --http1.1 -u admin:mazizone -X GET http://local.mazizone.eu/nextcloud/ocs/v1.php/cloud/users?format=json -H "OCS-APIRequest: true" | jq '.ocs.data.users'|jq -c '.[]'| sed 's/\"//g')
  for row in $users;do
    files=$(($files + $(sudo -u www-data php /var/www/html/nextcloud/occ files:scan --path=/$row/files -n|tail -2 | head -n 1 | awk '{print $4}')))
    datasize=$(($datasize + $(curl -s --http1.1 -u admin:mazizone -X GET http://local.mazizone.eu/nextcloud/ocs/v1.php/cloud/users/$row\?format=json -H "OCS-APIRequest: true"| jq '.ocs.data.quota.used') ))
  done

  downloads=$(echo "SELECT COUNT(*) FROM oc_activity WHERE subject LIKE 'public_shared_file_downloaded' OR subject='public_shared_folder_downloaded' ;" | mysql -u$username -p$password nextcloud)
  downloads=$(echo $downloads | awk '{print $NF}')

  application_id=$(sqlite3 /root/portal/database/inventory.db "SELECT id FROM applications WHERE name='NextCloud';")
  click_counter=$( sqlite3 /root/portal/database/inventory.db "SELECT SUM(click_counter) FROM application_instances WHERE application_id='$application_id';")
  
  users_num=$(curl -s --http1.1 -u admin:mazizone -X GET http://local.mazizone.eu/nextcloud/ocs/v1.php/cloud/users?format=json -H "OCS-APIRequest: true" |  jq '.ocs.data.users'| jq length)

  TIME=$(date  "+%H%M%S%d%m%y")
  data='{"deployment":'$(jq ".deployment" $conf)',
          "device_id":"'$id'",
          "date":'$TIME',
          "users":"'$users_num'",
          "datasize":"'$datasize'",
          "files":"'$files'",
          "downloads":"'$downloads'",
          "click_counter":"'$click_counter'"}'
  echo $data
}

data_etherpad() {
   sqlerr=$(mysql -u$username -p$password -e 'exit' 2>&1)
   [ -n "$sqlerr" ] && sed -i "/etherpad/c\\etherpad: Database Access Denied localhost http_code: 200" /etc/mazi/rest.log && exit 0;  

   users=$(mysql -u$username -p$password etherpad -e 'select store.value from store' |grep -o '"padIDs":{".*":.*}}' | wc -l)

   pads=$(mysql -u$username -p$password etherpad -e 'select store.key from store' |grep -Eo '^pad:[^:]+' |sed -e 's/pad://' |sort |uniq -c |sort -rn |awk '(count+=1) {if ($1!="2") { print count}}' |tail -1)

   datasize=$(echo "SELECT ROUND(SUM(data_length + index_length), 2)  as Size_in_B FROM information_schema.TABLES 
          WHERE table_schema = 'etherpad';" | mysql -u$username -p$password)
   datasize=$(echo $datasize | awk '{print $NF}')

   application_id=$(sqlite3 /root/portal/database/inventory.db "SELECT id FROM applications WHERE name='Etherpad';")
   click_counter=$( sqlite3 /root/portal/database/inventory.db "SELECT SUM(click_counter) FROM application_instances WHERE application_id='$application_id';")

   TIME=$(date  "+%H%M%S%d%m%y")
   data='{"deployment":'$(jq ".deployment" $conf)',
          "device_id":"'$id'",
          "date":'$TIME',
          "pads":"'$pads'",
          "users":"'$users'",
          "datasize":"'$datasize'",
          "click_counter":"'$click_counter'"}'
  echo $data
}

data_framadate() {
   sqlerr=$(mysql -u$username -p$password -e 'exit' 2>&1)
   [ -n "$sqlerr" ] && sed -i "/etherpad/c\\etherpad: Database Access Denied localhost http_code: 200" /etc/mazi/rest.log && exit 0;

   polls=$(echo "SELECT COUNT(*) FROM fd_poll WHERE active = '1';" | mysql -u$username -p$password framadate)
   polls=$(echo $polls | awk '{print $NF}')   

   votes=$(echo "SELECT COUNT(*) FROM fd_vote;" | mysql -u$username -p$password framadate)
   votes=$(echo $votes | awk '{print $NF}') 

   comments=$(echo "SELECT COUNT(*) FROM fd_comment;" | mysql -u$username -p$password framadate)
   comments=$(echo $comments | awk '{print $NF}')

   application_id=$(sqlite3 /root/portal/database/inventory.db "SELECT id FROM applications WHERE name='FramaDate';")
   click_counter=$( sqlite3 /root/portal/database/inventory.db "SELECT SUM(click_counter) FROM application_instances WHERE application_id='$application_id';")


   TIME=$(date  "+%H%M%S%d%m%y")
   data='{"deployment":'$(jq ".deployment" $conf)',
          "device_id":"'$id'",
          "date":'$TIME',
          "polls":"'$polls'",
          "comments":"'$comments'",
          "votes":"'$votes'",
          "click_counter":"'$click_counter'"}'
   echo $data
}

data_guestbook() {
   submissions=$(mongo letterbox  --eval "printjson(db.submissions.find().count())")
   submissions=$(echo $submissions | awk '{print $NF}')

   images=$(mongo letterbox  --eval "printjson(db.submissions.find({files:[]}).count())")
   images=$(( $submissions - $(echo $images | awk '{print $NF}') )) 

   comments=$(mongo letterbox  --eval "printjson(db.comments.find().count())")
   comments=$(echo $comments | awk '{print $NF}')

   datasize=$(mongo letterbox --eval "printjson(db.stats().dataSize)")
   datasize=$(echo $datasize | awk '{print $NF}')

   application_id=$(sqlite3 /root/portal/database/inventory.db "SELECT id FROM applications WHERE name='GuestBook';")
   click_counter=$( sqlite3 /root/portal/database/inventory.db "SELECT SUM(click_counter) FROM application_instances WHERE application_id='$application_id';")


   TIME=$(date  "+%H%M%S%d%m%y")
   data='{"deployment":'$(jq ".deployment" $conf)',
          "device_id":"'$id'",
          "date":'$TIME',
          "submissions":"'$submissions'",
          "comments":"'$comments'",
          "images":"'$images'",
          "datasize":"'$datasize'",
          "click_counter":"'$click_counter'"}'
  echo $data
}

store(){
   NAME=$1
   while [ true ]; do
     target_time=$(( $(date +%s)  + $interval ))
     data_$NAME
     response=$(curl -s -w %{http_code} -X POST --data "$data" http://$domain:$port/update/$NAME)
     http_code=$(echo $response | tail -c 4)
     body=$(echo $response| rev | cut -c 4- | rev )
     sed -i "/$NAME/c\\$NAME: $body $domain http_code: $http_code" /etc/mazi/rest.log
     current_time=$(date +%s)
     sleep_time=$(( $target_time - $current_time ))
     [ $sleep_time -gt 0 ] && sleep $sleep_time
   done
}

disable(){

   Pid=$(ps aux| grep -F "store enable" | grep "mazi-appstat" |grep -v 'grep' |awk '{print $2}')
   for i in $Pid
   do
     kill $i 
     echo "disable"
   done
   exit 0;
}

status_call() {
  error=""
  call_st=""
  if [ -f /etc/mazi/rest.log ];then
    response=$(tac /etc/mazi/rest.log| grep "$1" | awk -v FS="($1:|http_code:)" '{print $2}')
    http_code=$(tac /etc/mazi/rest.log| grep "$1" | head -1 | awk '{print $NF}')
  fi
  [ "$http_code" = "200" -a "$(echo $response | grep "OK")"  ] && call_st="OK" && error=""
  [ "$http_code" = "000" ] && call_st="ERROR:" && error="Connection refused"
  [ "$http_code" = "200" -a ! "$(echo $response | grep "OK")" ] && call_st="ERROR:" && error="$response"
  [ "$http_code" = "500" ] && call_st="ERROR:" && error="The server encountered an unexpected condition which prevented it from fulfilling the request."

}


##### Initialization ######
conf="/etc/mazi/mazi.conf"
interval="60"
domain="localhost"
 #Database
username=$(jq -r ".username" /etc/mazi/sql.conf)
password=$(jq -r ".password" /etc/mazi/sql.conf)
port="7654"
while [ $# -gt 0 ]
do

  key="$1"
  case $key in
      -n|--name)
      apps="$2"
      shift
      ;;
      --store)
      store="$2"
      shift
      ;;
      -s|--status)
      status="TRUE"
      ;;
      -d|--domain)
      domain="$2"
      shift
      ;;
      *)
      # unknown option
      usage   
      ;;
  esac
  shift     #past argument or value
done


if [ $status ];then
  status_call guestbook
  [ "$(ps aux | grep "mazi-appstat"| grep "store enable" | grep "guestbook" | grep -v 'grep' | awk '{print $2}')" ] && echo "guestbook active $call_st $error" || echo "guestbook inactive $call_st $error"
  status_call etherpad 
  [ "$(ps aux | grep "mazi-appstat"| grep "store enable" | grep "etherpad" | grep -v 'grep' | awk '{print $2}')" ] && echo "etherpad active $call_st $error" || echo "etherpad inactive $call_st $error"
  status_call framadate
  [ "$(ps aux | grep "mazi-appstat"| grep "store enable" | grep "framadate" | grep -v 'grep' | awk '{print $2}')" ] && echo "framadate active $call_st $error" || echo "framadate inactive $call_st $error" 
  status_call nextcloud
  [ "$(ps aux | grep "mazi-appstat"| grep "store enable" | grep "nextcloud" | grep -v 'grep' | awk '{print $2}')" ] && echo "nextcloud active $call_st $error" || echo "nextcloud inactive $call_st $error"


fi

if [ $store ];then
  id=$(curl -s -X GET -d @$conf http://$domain:$port/device/id)
  [ ! $id ] && id=$(curl -s -X POST -d @$conf http://$domain:$port/monitoring/register)


  if [ $store = "enable" ];then
   
    for i in $apps; do 
       [ ! -f /etc/mazi/rest.log -o ! "$(grep -R "$i:" /etc/mazi/rest.log)" ] && echo "$i:" >> /etc/mazi/rest.log
       curl -s -X POST http://$domain:$port/create/$i
    done
    for i in $apps; do
       store $i &  
    done
  elif [ $store = "disable" ];then
    disable
  elif [ $store = "flush" ];then
    for i in $apps; do
       curl -s -X POST --data '{"device_id":'$id'}' http://$domain:$port/flush/$i 
    done  
  else
   echo "WRONG ARGUMENT"
   usage

  fi
fi

#set +x
