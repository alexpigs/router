#!/bin/sh


NWAN_DIR=$(pwd)
. $NWAN_DIR/_dy_def.sh
NWAN_IPTABLE_NAME=$ACTION
NWAN_LOG_FILE=$NWAN_DIR/swan.log


ROUND_TIMEOUT=300
logfile=$NWAN_TINYPROXY_DIR/tinyproxy.log
pidfile=$NWAN_TINYPROXY_DIR/tinyproxy.pid
cfgfile=$NWAN_TINYPROXY_DIR/tinyproxy.cfg
	

swan_start_redial(){
	nwan_log swan_start_redial
	ft=0
	while true
	do
		if [ $ft -gt 5 ] ; then
			reboot
		fi
		service wan restart
		f=$(check_network_timeout 120)
		if [ $f == 0 ] ; then
			echo "redial ok"
		else 
			ft=$(($ft+1))
			continue
		fi
		break
	done
	
}

swan_start_tinyproxy(){
	port=$(sel_proxy_port)
	ipaddress=$(nvram_get wan_ipaddr nullip)
	cp $TINYPROXY_CFG $cfgfile
	sed -i "/^Bind/d" $cfgfile &&	sed -i "/^Listen/d" $cfgfile &&	sed -i "/^Port/d" $cfgfile && sed -i "/^LogFile/d" $cfgfile && sed -i "/^PidFile/d" $cfgfile
	echo "Bind $ipaddress" >> $cfgfile
	echo "Listen $ipaddress" >> $cfgfile
	echo "Port $port" >> $cfgfile
	echo "LogFile \"$logfile\"" >> $cfgfile
	echo "PidFile \"$pidfile\"" >> $cfgfile
	tinyproxy -c $cfgfile & > /dev/null 2>&1
	# iptables, allow remote connect tinyproxy	
	iptables -t filter -F "swan"
	iptables -t filter -A "swan"  -p tcp --dport $port -j ACCEPT
	nvram_set swan_tp_port $port
	dev=$(ip route | grep default | awk '{print $5}')
	do_report_tinyproxy $dev $ipaddress $port
}

swan_stop_tinyproxy(){
	tppid=$(cat $pidfile)
	kill -TERM "$tppid" > /dev/null 2>&1
	rm $logfile >/dev/null 2>&1
	rm $pidfile >/dev/null 2>&1
	rm $cfgfile >/dev/null 2>&1
	nvram_del swan_tp_port
	iptables -t filter -F "swan" > /dev/null 2>&1
}

swan_round_finished(){
	tppid=$(cat $pidfile)
	kill -TERM "$tppid" > /dev/null 2>&1
	iptables -t filter -F "swan" > /dev/null 2>&1
	nvram_del swan_tp_port
	rm $logfile >/dev/null 2>&1
	rm $pidfile >/dev/null 2>&1
	rm $cfgfile >/dev/null 2>&1
}

swan_keepalive(){
	total_timeout=$1
	
	url=mac/$wan_mac/ip/$wan_ip
	tick=$(date +%s)
	
	nwan_log "swan_keealive($total_timeout)"
	pre_ip=$(nvram_get wan_ipaddr)
	while true
	do
		dev=$(ip route | grep default | awk '{print $5}')
		wan_ip=$(nvram_get wan_ipaddr)
		wan_gateway=$(nvram_get wan_gateway_get)

		if [ "$wan_ip" != "$pre_ip" ] ; then
			swan_stop_tinyproxy
			swan_start_tinyproxy
			pre_ip=$wan_ip
		fi
	
		tp_port=$(nvram_get swan_tp_port)
		cur=$(date +%s)
		inv=$(($cur-$tick))

		nwan_log "swan_keepalive $inv -- $total_timeout"
		if [ $inv -gt $total_timeout ] ; then
			nwan_log swan_keepalive excceed
			break
		fi

		ret=$(check_network_timeout 10 $dev)
		if [ $ret -ne 0 ] ; then
			nwan_log check wan_gateway error, network down
			break
		fi
		sleep 20

		cdata=$(do_keepalive $dev $wan_ip $tp_port)
		if [ "$cdata" == "finished" ] ; then
			nwan_log "server control round finished"
			break
		elif [ "$cdata" == "delay" ] ; then
			nwan_log "server control round delay 30 secs"
			total_timeout=$(($total_timeout+30))
		fi
	done
}

swan_round(){
	instance_keepalive "swan"
	nwan_log "swan_round"
	swan_start_tinyproxy
	swan_keepalive "$ROUND_TIMEOUT"

	cnt=$(has_arp)
	force=$(nvram_get swan_force 0)
	if [ "$force" == "1" ] ; then
		cnt=0
	fi
	while [ $cnt -ne 0 ] 
	do
		swan_keepalive "$ROUND_TIMEOUT"
		cnt=$(has_arp)
		nwan_log "arp clients = $cnt"
	done	
	do_report_tinyproxydown "swan"
	swan_round_finished
	swan_start_redial
}

swan_loop(){
	rounds=0
	while true
	do
		swan_round
		rounds=$(($rounds+1))
		if [ $rounds -gt 20 ] ; then
			break
		fi

	done
}


instance_start swan 0
swan_round_finished
swan_loop
instance_exit swan

nwan_log "round>20, rerun shell in another proces"
$(pwd)/_dy_swan_start.sh > /dev/null 2>&1 &
