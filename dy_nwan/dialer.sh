#!/bin/sh
# usage dialer.sh idx(1|2|3)

#test
IDX=$1
wanx_dir=$(nvram get wanx_dir)
VPREX=mc
PPREX=ppp

PPPD_CMD=$(pwd)/qpd

pid_file=$wanx_dir/tmp/dialer.pid
[ -e "$pid_file" ] && dialer_pid=$(cat "$pid_file") && rm "$pid_file" && kill -9 $dialer_pid 
echo $$ > $pid_file

do_connect(){
	x=$1
	local idx=$x
	local mc=$VPREX$idx
	local pc=$PPREX$idx
	local pl=$wanx_dir/tmp/pppd${idx}.log
	local username=$(nvram get ppp_username)
	local password=$(nvram get ppp_passwd)
	ifconfig $mc > /dev/null 2>&1 || ip link add link vlan2 $mc type macvlan
	ip link set dev $mc up > /dev/null 2>&1

	
	$PPPD_CMD nodetach lcp-echo-interval 5 lcp-echo-failure 3 nodefaultroute usepeerdns user $username password $password "ip-up-script" "$wanx_dir/dialup.sh" "ip-down-script" "$wanx_dir/dialdown.sh" mtu 1492 mru 1492 plugin rp-pppoe.so ifname $pc nic-$mc  >$pl 2>&1 & 
	pppd_pid=$!
	key_pppd=wan${x}_pppd_pid
	key_status=wan${x}_status
	key_conntime=wan${x}_conntime
		
	nvram set $key_conntime=$(date +%s)
	nvram set $key_status=connecting
	nvram set $key_pppd=$pppd_pid
}

do_disconnect(){
	#pppd_pid=$(nvram get $key_pppd)
	#kill -9 $pppd_pid > /dev/null 2>&1
	nvram unset shit
}


round=0
maxround=100
while true
do
	roundtime=30
	round=$(($round+1))
	if [ $round -gt $maxround ] ; then
		break
	fi

	for i in $(seq 2 1 8)
	do
		echo "checking wan $i..."
		IDX=$i
		key_ipaddr=wan${IDX}_ipaddr
		key_gateway_get=wan${IDX}_gateway_get
		key_hwaddr=wan${IDX}_hwaddr
		key_netmask=wan${IDX}_netmask
		key_proto=wan${IDX}_proto
		key_run_mtu=wan${IDX}_run_mtu
		key_pppd=wan${IDX}_pppd_pid
		key_status=wan${IDX}_status
		key_uptime=wan${IDX}_uptime
		key_conntime=wan${IDX}_conntime
		key_enable=wan${IDX}_enable

		enable=$(nvram get $key_enable)
		status=$(nvram get $key_status)
		pppd_pid=$(nvram get $key_pppd)
	
		# check stop
		if [ "$enable" != "1" ] ; then
			[ ! -z "$pppd_pid" ] && kill -9 $pppd_pid
			nvram unset $key_pppd
			echo "$IDX not enable,sleeping"
			continue
		fi

	
		if [ "$status" == "connected" ] ; then
			echo "$i connected, checking process"	
			if [ -z "$pppd_pid" ] || [ ! -f "/proc/$pppd_pid/cmdline" ] ; then
				echo "$i pppd process not exist"
				roundtime=0
				nvram unset $key_status
				continue
			fi
	
			continue
		elif [ -z "$status" ] ; then
			echo "$IDX connecting"
			
			# kill if pre instance
			[ ! -z "$pppd_pid" ] && kill -9 $pppd_pid > /dev/null 2>&1
			nvram unset $key_pppd
			do_connect $i
		elif [ "$status" == "connecting" ] ; then
			$roundtime=20
			echo "$i checking connecting timeout"
			conntime=$(nvram get $key_conntime)
			cur=$(date +%s)
			inv=$(($cur-$conntime))
			echo "$i connecting $inv secs"
			if [ $inv -gt 90 ] || [ -z "$pppd_pid" ] || [ ! -f "/proc/$pppd_pid/cmdline" ] ; then
				echo "$i connect timeout, redialing"
				do_connect $i
				continue
			fi
		fi

	done
	sleep $roundtime
done

rm $pid_file
$wanx_dir/dialer.sh > /dev/null 2>&1 &




