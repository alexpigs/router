#!/bin/sh


NWAN_DIR=$(pwd)
. $NWAN_DIR/_dy_def.sh
NWAN_DEV=$NWAN_DEV_PREFIX$INDEX
NWAN_IPTABLE_NAME=nwan$INDEX
NWAN_PPPOE_DEV=$NWAN_PPPOE_DEV_PREFIX$INDEX
PPPOE_FAILED_TIMES=0
PPPOE_OK_TIMES=0

logfile=$NWAN_TINYPROXY_DIR/tinyproxy_$INDEX.log
pidfile=$NWAN_TINYPROXY_DIR/tinyproxy_$INDEX.pid
cfgfile=$NWAN_TINYPROXY_DIR/tinyproxy_$INDEX.cfg

nvkey_ip=nwan_${NWAN_PPPOE_DEV}_ip
nvkey_gw=nwan_${NWAN_PPPOE_DEV}_gw
nvkey_pppd_pid=nwan_${NWAN_PPPOE_DEV}_pppd_pid
nvkey_tp_port=nwan_${NWAN_PPPOE_DEV}_tp_port
nvkey_status=nwan_${NWAN_PPPOE_DEV}_status
nvkey_up_time=nwan_${NWAN_PPPOE_DEV}_up_time


#nwan dir
NWAN_LOG_FILE=$NWAN_DIR/nwan_$INDEX.log
INSTANCE_LOCK_FILE=$NWAN_TMP_DIR/lock.$INDEX



# setup macvlan,ip route,iptables
nwan_init_rtable() {	
	route_prio=200
	ip route flush table $(($route_prio-$INDEX)) >/dev/null 2>&1
}

nwan_delete_ifn() {
	ip link del "$NWAN_DEV" >/dev/null 2>&1
}

nwan_create_ifn() {
	nwan_delete_ifn
	ifname=$(nvram_get wan_ifname)
	ip link add link $ifname "$NWAN_DEV" type macvlan >/dev/null 2>&1
	ip link set dev "$NWAN_DEV" up >/dev/null 2>&1
}

nwan_delete_iptable_rule() {
	iptables -t nat -D POSTROUTING -o $NWAN_PPPOE_DEV -j MASQUERADE >/dev/null 2>&1
}

nwan_create_iptable_rule() {
	cnt=$(iptables -t filter -L INPUT | grep $NWAN_IPTABLE_NAME | wc -l)
	if [ $cnt -eq 0 ] ; then	
		iptables -t filter -N "$NWAN_IPTABLE_NAME"	
		iptables -t filter -A INPUT -i $NWAN_PPPOE_DEV -j "$NWAN_IPTABLE_NAME"
	fi
}

nwan_setup(){
	nwan_init_rtable
	nwan_create_ifn
	nwan_create_iptable_rule
}

nwan_call_pppoe(){
	nwan_log nwan_call_pppoe 
	local username=$(nvram_get ppp_username)
	local password=$(nvram_get ppp_passwd)
	
	$PPPD_CMD nodetach lcp-echo-interval 5 lcp-echo-failure 3 nodefaultroute usepeerdns user $username password $password "ip-up-script" "${NWAN_DIR}/_dy_dialup.sh" "ip-down-script" "${NWAN_DIR}/_dy_dialdown.sh" mtu 1492 mru 1492 plugin rp-pppoe.so ifname ${NWAN_PPPOE_DEV} nic-${NWAN_DEV}  >$NWAN_TMP_DIR/pppd$INDEX.log 2>&1 & 
	pppd_pid=$!
	nvram_set $nvkey_pppd_pid $pppd_pid
}

nwan_build_ip_rule(){
	ifname=$NWAN_PPPOE_DEV
	ipaddress=$(nvram_get $nvkey_ip)
	gateway=$(nvram_get $nvkey_gw)
	pppd_pid=$(nvram_get $nvkey_pppd_pid)
	vnum=$INDEX
	rtable=$((200-$vnum))
	# route table create
	ip route flush table $rtable	
	ip route add default via $gateway dev $ifname table $rtable
	ip rule del from $ipaddress >/dev/null 2>&1
	ip rule del lookup $rtable >/dev/null 2>&1
	ip rule del lookup $rtable >/dev/null 2>&1
	ip rule add from $ipaddress lookup $rtable 
}

nwan_call_tinyproxy(){
	ifname=$NWAN_PPPOE_DEV
	ipaddress=$(nvram_get $nvkey_ip)
	gateway=$(nvram_get $nvkey_gw)
	pppd_pid=$(nvram_get $nvkey_pppd_pid)
	# start tinyproxy
	port=$(sel_proxy_port)
	cp $TINYPROXY_CFG $cfgfile
	sed -i "/^Bind/d" $cfgfile &&	sed -i "/^Listen/d" $cfgfile &&	sed -i "/^Port/d" $cfgfile && sed -i "/^LogFile/d" $cfgfile && sed -i "/^PidFile/d" $cfgfile
	echo "Bind $ipaddress" >> $cfgfile
	echo "Listen $ipaddress" >> $cfgfile
	echo "Port $port" >> $cfgfile
	echo "LogFile \"$logfile\"" >> $cfgfile
	echo "PidFile \"$pidfile\"" >> $cfgfile
	tinyproxy -c $cfgfile > /dev/null 2>&1 &
	# iptables, allow remote connect tinyproxy	
	iptables -t filter -F $NWAN_IPTABLE_NAME
	iptables -t filter -A $NWAN_IPTABLE_NAME  -p tcp --dport $port -j ACCEPT
	#echo nwan_on_pppoe_up $1 $2 $3 $4
	nwan_log "nwan_on_pppoe_up $vnum $ifname, ip=$ipaddress tinyproxy.port=$port"
	nvram_set $nvkey_tp_port $port
	do_report_tinyproxy $NWAN_PPPOE_DEV $ipaddress $port
}

nwan_check_pppoe_gateway(){
	gw=$(nvram_get $nvkey_gw)
	if [ -z "$gw" ] ; then
		echo 1
		return
	fi

	ping -I $NWAN_PPPOE_DEV -c 1 $gw > /dev/null 2>&1
	echo $?
}

nwan_check_pppoe_up_timeout(){
	timeout=$1
	tick=$(date +%s)
	while true
	do
		cur=$(date +%s)
		inv=$(($cur-$tick))
		
		if [ $inv -gt $timeout ] ; then
			echo 1
			return
		fi	

		status=$(nvram_get $nvkey_status 0)
		up_time=$(nvram_get $nvkey_up_time 0)
	
		if [ "$status" == "up" ] ; then
			if [ $up_time -lt $tick ] ; then
				nvram_del $nvkey_status
				continue
			fi
			echo 0
			return
		fi
		
		sleep 2
	done
}

nwan_keepalive(){
	total_timeout=$1
	ifname=$NWAN_PPPOE_DEV
	ipaddress=$(nvram_get $nvkey_ip)
	gateway=$(nvram_get $nvkey_gw)
	port=$(nvram_get $nvkey_tp_port)
	pppd_pid=$(nvram_get $nvkey_pppd_pid)
	vnum=$INDEX
	tick=$(date +%s)
	
	nwan_log "swan_keealive($total_timeout) ip=$ipaddress gw=$gateway pppdpid=$pppd_pid index=$INDEX"
	while true
	do
		cur=$(date +%s)
		inv=$(($cur-$tick))
		nwan_log "nwan_keepalive $inv -- $total_timeout"
		if [ $inv -gt $total_timeout ] ; then
			nwan_log swan_keepalive excceed
			break
		fi

		status=$(nvram_get $nvkey_status 0)
		if [ "$status" != "up" ] ; then
			nwan_log something happen to clear ${NWAN_PPPOE_DEV} status
			break
		fi

		# check wan gateway
		ping $gateway -I $ifname -c 10 > /dev/null 2>&1
		if [ $? -ne 0 ] ; then
			nwan_log ping wan_gateway error, network down
			break
		fi

		# check default route
		ret=$(check_network_timeout 10)
		if [ $ret -ne 0 ] ; then
			nwan_log "default route down $NWAN_PPPOE_DEV !!"
			nwan_round_finished
			nvram_set nwan_mode 0
			nvram commit
			exit
		fi

		sleep 20

		cdata=$(do_keepalive $ifname $ipaddress $port)

		if [ "$cdata" == "finished" ] ; then
			nwan_log "server control round finished"
			break
		elif [ "$cdata" == "delay" ] ; then
			nwan_log "server control round delay 30 secs"
			total_timeout=$(($total_timeout+30))
		fi
	done
	
}


clear_round_info(){
	nvram_del $nvkey_status
	nvram_del $nvkey_up_time
	nvram_del $nvkey_ip
	nvram_del $nvkey_gw
	nvram_del $nvkey_pppd_pid
	nvram_del $nvkey_tp_port
}

 
nwan_round_finished(){
	pppd_pid=$(nvram_get $nvkey_pppd_pid)
	kill -9 "$pppd_pid" > /dev/null 2>&1

	if [ -f "$pidfile" ] ; then
		tp_pid=$(cat "$pidfile")
		kill -TERM "$tp_pid" > /dev/null 2>&1
	fi
	
	clear_round_info 
}

nwan_check_default_route(){
	ret=$(check_network_timeout 10)
	echo $ret
}

nwan_round(){
	nwan_log "nwan_round start"
	nwan_call_pppoe
	ret=$(nwan_check_pppoe_up_timeout 40)
	if [ $ret -ne 0 ] ; then
		nwan_log "wait $NWAN_PPPOE_DEV timeout"
		PPPOE_FAILED_TIMES=$(($PPPOE_FAILED_TIMES+1))
		add_failed_times "$NWAN_PPPOE_DEV"
		return
	fi
	
	# check default route
	ret=$(check_network_timeout 10)
	if [ $ret -ne 0 ] ; then
		nwan_log "default route down $NWAN_PPPOE_DEV !!"
		nwan_round_finished
		nvram_set nwan_mode 0
		nvram commit
		exit
	fi

	add_ok_times "$NWAN_PPPOE_DEV"
	nwan_build_ip_rule
	nwan_call_tinyproxy
	nwan_keepalive 300
	do_report_tinyproxydown $NWAN_PPPOE_DEV
	nwan_log "nwan_round finished"
	PPPOE_FAILED_TIMES=0

}

nwan_loop(){
	rounds=0
	while [ $PPPOE_FAILED_TIMES -lt 100 ] 
	do
		instance_keepalive $NWAN_PPPOE_DEV
		nwan_round
		nwan_round_finished
		sleep $((100+$PPPOE_FAILED_TIMES*300))
		if [ $rounds -gt 50 ] ; then
			break
		fi
	done

}

nwan_check(){
	try_times=3
	nwan_log nwan_check start index=$INDEX
	while true 
	do
		nvram_del ${NWAN_PPPOE_DEV}_failed
		nvram_del ${NWAN_PPPOE_DEV}_ok
		nwan_round_finished
		nwan_call_pppoe
		ret=$(nwan_check_pppoe_up_timeout 60)
		if [ $ret -ne 0 ] ; then
			if [ $try_times -gt 0 ] ; then
				nwan_log "action=check,wait $NWAN_PPPOE_DEV timeout,round $try_times"
				add_failed_times $NWAN_PPPOE_DEV
				try_times=$(($try_times-1))
				sleep 60
				continue
			else
				nwan_log "action=check,wait $NWAN_PPPOE_DEV timeout, exiting"
				add_failed_times $NWAN_PPPOE_DEV
				break
			fi
		fi
		nwan_build_ip_rule
		nwan_log "action=check, $NWAN_PPPOE_DEV ok"
		add_ok_times $NWAN_PPPOE_DEV
		break
	done
}

nwan_clean(){
	nwan_round_finished
	nwan_delete_ifn
}


nwan_setup
if [ "$ACTION" == "CHECK" ] ; then
	instance_start $NWAN_PPPOE_DEV 0
	nwan_check
	instance_exit $NWAN_PPPOE_DEV
elif [ "$ACTION" == "CLEAN" ] ; then
	instance_start $NWAN_PPPOE_DEV 0
	nwan_clean
	instance_exit $NWAN_PPPOE_DEV
else
	instance_start $NWAN_PPPOE_DEV 0
	nwan_loop
	instance_exit $NWAN_PPPOE_DEV
	nwan_log "round>20, rerun shell in another process"
	INDEX=$INDEX $(pwd)/_dy_nwan_start.sh > /dev/null 2>&1 & 
fi



