#!bin/bash
install_nodogsplash(){
echo "Install nodogsplash"
if [ ! -d /root/nodogsplash ];then
  cd /root/
  git clone https://github.com/nodogsplash/nodogsplash.git
  cd nodogsplash
  git checkout v1
  make
  make install
fi
}
nodogsplash_template(){
 echo "New templates for nodogspalsh "
 c_domain=$(grep -o -P '(?<=url=http://).*(?=">)' /var/www/html/index.html)
 cp /root/back-end/templates/online.txt /etc/nodogsplash/
 cp /root/back-end/templates/offline.txt /etc/nodogsplash/
 cp /root/back-end/templates/splash.html /etc/nodogsplash/htdocs/
 sed -i "s/portal.mazizone.eu/$c_domain/g" /etc/nodogsplash/htdocs/splash.html 

}
nodogsplash_service(){
 echo "Create nodogsplash service"
## create nodogsplash service
 cp /root/back-end/templates/nodogsplash /etc/init.d/
 chmod +x /etc/init.d/nodogsplash
 update-rc.d nodogsplash defaults
 systemctl daemon-reload
}

hostapd_templates(){
## hostapd tempates
 echo "New templates for hostapd"
 cp /root/back-end/templates/template_80211n.txt /etc/hostapd/
 cp /root/back-end/templates/replace.sed /etc/hostapd/
}

install_batman(){
 echo "Install batman"
if [ -z "$(cat /proc/modules | grep batman)" ];then
  ## install batctl (mesh) ##
  cd /root/
  apt-get install batctl
  echo "batman-adv" >> /etc/modules
  modprobe batman-adv
fi
}

remove_iptables(){
echo "Remove old iptables"
## remove old iptables ##
iptables -F
iptables -F -t nat
iptables -F -t mangle
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables-save | sudo tee /etc/iptables/rules.v4
}

rc_local(){
 echo "Make changes in rc.local file"
 ## update rc.local ###
 sed -i '/service nodogsplash start/d' /etc/rc.local
 if [ -z "$(cat /etc/rc.local | grep "bash /root/back-end/mazi-internet.sh")" ];then
   sudo sed -i '/#END RASPIMJPEG SECTION/ a \bash /root/back-end/mazi-internet.sh -m $(jq -r .mode /etc/mazi/mazi.conf)' /etc/rc.local
 fi
}

interface_file(){
echo "Make changes in /etc/network/interfaces"
## update /etc/network/interfaces
sed -i '/allow-hotplug wlan0/d' /etc/network/interfaces
sed -i '/iface wlan0 inet manual/d' /etc/network/interfaces
sed -i '/#    wpa-conf \/etc\/wpa_supplicant\/wpa_supplicant.conf/d' /etc/network/interfaces
sed -i '/    wpa-conf \/etc\/wpa_supplicant\/wpa_supplicant.conf/d' /etc/network/interfaces
sed -i '/allow-hotplug wlan1/d' /etc/network/interfaces
sed -i '/iface wlan1 inet manual/d' /etc/network/interfaces
sed -i '/iface wlan0 inet static/d' /etc/network/interfaces
sed -i '/address 10.0.0.1/d' /etc/network/interfaces
sed -i '/netmask 255.255.255.0/d' /etc/network/interfaces
sed -i '/gateway 10.0.0.1/d' /etc/network/interfaces
}

#sh /root/back-end/mazi-internet.sh -m offline
synchronize_AP(){
  echo "synchronize Access Point"
  mode=$(jq -r .mode /etc/mazi/mazi.conf)
  if [ "$mode" = "offline" ];then
      echo $(cat /etc/mazi/mazi.conf | jq '.+ {"mode": "offline"}') | sudo tee /etc/mazi/mazi.conf
  else
      echo $(cat /etc/mazi/mazi.conf | jq '.+ {"mode": "online"}') | sudo tee /etc/mazi/mazi.conf
  fi

  intface=$(grep 'interface' /etc/hostapd/hostapd.conf| sed 's/interface=//g')
  ssid=$(grep 'ssid' /etc/hostapd/hostapd.conf| sed 's/ssid=//g')
  channel=$(grep 'channel' /etc/hostapd/hostapd.conf| sed 's/channel=//g')
  password=$(grep 'wpa_passphrase' /etc/hostapd/hostapd.conf| sed 's/wpa_passphrase=//g')
  [ -z $password ] && password="-"
  sed -i  "/password/c\s/\${password}/$password/" /etc/hostapd/replace.sed
  if [ "$password" = "-" ];then
    bash /root/back-end/mazi-wifi.sh -s $ssid -c $channel  -i $intface
  else
    bash /root/back-end/mazi-wifi.sh -s $ssid -c $channel -p $password -i $intface
  fi
  
  bash /root/back-end/mazi-internet.sh -m $(jq -r .mode /etc/mazi/mazi.conf)
}

rc_local_CHANGE(){
 echo "Removes unuseful commands from rc.local file"
 sed -i "/\/sbin\/ifconfig wlan0 10.0.0.1/d" /etc/rc.local
 sed -i "/#ifdown wlan0/d" /etc/rc.local
 sed -i "/#sleep 1/d" /etc/rc.local
 sed -i "/#hostapd -B \/etc\/hostapd\/hostapd.conf/d" /etc/rc.local
 sed -i "/#ifconfig wlan0 10.0.0.1/d" /etc/rc.local 

}
while [ $# -gt 0 ]
do
  key="$1"
  case $key in
    2.5.4)
    #update v2.5.4
    rc_local_CHANGE
    nodogsplash_template
    nodogsplash_service
    synchronize_AP
    exit 0
    ;;
    previous)
    #previous update 
    install_nodogsplash
    nodogsplash_template
    nodogsplash_service
    hostapd_templates 
    install_batman
    remove_iptables 
    rc_local
    interface_file
    synchronize_AP
    exit 0
    ;;
    *)
    echo "Invalid version"
    ;;
  esac
  shift
done

### Run update script without argument #####
install_nodogsplash
nodogsplash_template
nodogsplash_service
hostapd_templates
install_batman
remove_iptables
rc_local
interface_file
synchronize_AP
