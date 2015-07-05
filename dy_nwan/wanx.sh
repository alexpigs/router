#!/bin/sh

VPREX=mc
PPREX=ppp
wan_ppp_num=$(nvram get wan_ppp_num)
ACTION=$1
wanx_dir=$(nvram get wanx_dir)

echo ----wanx $# $*> /dev/kmsg

assign_ports(){
	t=$(nvram get ports_assgin)
	iptables -t mangle -F wan_pre
	echo $t | tr ">" "\n" | tr "<" " " | while read enable ptype stype str wanx ; do 
		if [ -z "$enable" ] || [ "$enable" != "1" ] || [ -z "$ptype" ] || [ -z "$stype" ] || [ -z "$str" ] || [ -z "$wanx" ] ; then
			continue
		fi	

		# ptype 1=tcp 2=udp
		[ "$ptype" != "1" ] && [ "$ptype" != "2" ] && continue
		# stype 0=dport 1=dip 2=sport 3=sip
		[ "$stype" != "0" ] && [ "$stype" != "1" ] && [ "$stype" != "2" ] && [ "$stype" != "3" ] && continue
		echo "enable=$enable,ptype=$ptype,stype=$stype,str=$str,wanx=$wanx" 
		cmd="iptables -t mangle -A wan_pre"
		[ "$ptype" == "1" ] && cmd="${cmd} -p tcp"
		[ "$ptype" == "2" ] && cmd="${cmd} -p udp"

		[ "$stype" == "0" ] && cmd="${cmd} -m multiport --dports $str"
		[ "$stype" == "1" ] && cmd="${cmd} -d $str"
		[ "$stype" == "2" ] && cmd="${cmd} -m multiport --sports $str"
		[ "$stype" == "3" ] && cmd="${cmd} -s $str"

		target=$(eval echo \$$wanx)
		echo "wanx=$wanx, taget=$target"
		[ -z "$target}" ] && continue
		cmd="${cmd} -j $target"
		echo $cmd
		$cmd
	done
}

# setup_basic_iptables_rules dev_index dev_name
setup_basic_policy_routes(){

	if [ $wan_ppp_num -lt 2 ] ; then
		return
	fi
	
	total=$(ip link show | grep POINTOPOINT | wc -l)

	if [ $total -lt 2 ] ; then
		return
	fi

	while [ "$(nvram get wanx_running)" == "1" ]
	do
		sleep 1
	done

	nvram set wanx_running=1
	sleep 10 && nvram unset wanx_running > /dev/null 2>&1 &

	# clean ip rule
	for t in $(ip rule | awk '{print $NF}')
	do
		if [ "$t" == "main" ] || [ "$t" == "local" ] || [ "$t" == "default" ] ; then
			continue
		fi
		echo "ip rule del table $t"
		ip rule del table $t 
	done

	iptables -t mangle -F > /dev/null 2>&1
	iptables -t mangle -Z
	iptables -t mangle -N wan_pre
	iptables -t mangle -F wan_pre
	iptables -t mangle -A PREROUTING -i br0 -j wan_pre
	iptables -t nat -F POSTROUTING
	iptables -t nat -F PREROUTING

	# wan0 100 wan1 101 wan2 102 ---- wan0-ppp0 wan2-ppp2 wan3-ppp3 wan4-ppp4 ....
	# policy route balance
	idx=0
	srouter="ip route add default scope global "
	wans=
	for dev in $(ip link show | grep POINTOPOINT | awk '{print $2}' | awk -F ":" '{print $1}' | sort)
	do
		gw=$(ifconfig $dev | grep "P-t-P" | awk -F " " '{print $3}' | awk -F ":" '{print $2}')
		ipaddr=$(ifconfig $dev | grep "P-t-P" | awk -F " " '{print $2}' | awk -F ":" '{print $2}')
		netmask=$(ip address show $dev | grep peer | awk '{print $4}')
		echo "dev $dev,ip=$ipaddr,netmask=$netmask,gw=$gw"
		if [ -z "$gw" ] || [ -z "$ipaddr" ] || [ -z "$netmask" ] ; then
			continue
		fi

		i=$(echo $dev | grep -o "[0-9]\+")
		chain=wan$i
		mark=$(($i+100))
		table=$(($i+100))
		pref=$((100+$i))
		fwpref=$((200+$i))
		wans="wan${idx}=$chain"
		echo $wans
		eval $wans
		
		iptables -t mangle -N $chain
		iptables -t mangle -F $chain
		iptables -t mangle -A $chain -j MARK --set-mark $mark
		iptables -t mangle -A $chain -j CONNMARK --save-mark
	
 		iptables -t nat -A POSTROUTING -o $dev -j MASQUERADE
		
		iptables -t mangle -A PREROUTING -i $dev -m state --state NEW -j MARK --set-mark $mark
		iptables -t mangle -A PREROUTING -i $dev -m state --state NEW -j CONNMARK --save-mark
		iptables -t mangle -A FORWARD -o $dev -j MARK --set-mark $mark
		iptables -t mangle -A FORWARD -o $dev -j CONNMARK --save-mark
		ip route flush table $table > /dev/null 2>&1		

		ip route add default via $gw dev $dev  table $table
		ip route show table main | grep "^[0-9]" | while read ROUTE ; do
	       		ip route add table $table $ROUTE
		done

		ip rule add from $ipaddr table $table pref $pref
		ip rule add fwmark $mark table $table pref $fwpref

		# nat
		#iptables -t nat -A PREROUTING -d $ipaddr -j WANPREROUTING

		idx=$(($idx+1))
		srouter=$srouter" nexthop via "$gw" dev "$dev" weight 1 "
	done

	iptables -t mangle -N RESTORE
	iptables -t mangle -F RESTORE
	iptables -t mangle -A RESTORE -j CONNMARK --restore-mark
	iptables -t mangle -A PREROUTING -m state --state ESTABLISHED,RELATED -j RESTORE


	# nat upnp restore
	iptables -t nat -A PREROUTING -j WANPREROUTING
	iptables -t nat -A PREROUTING -j upnp

	# filter FORWARD wanin
	idx=$(iptables -t filter -L FORWARD -nv --line-number | awk '$4=="wanin" {print $1}')
	if [ ! -z "$idx" ] ; then
		iptables -t filter -D FORWARD $idx
		iptables -t filter -I FORWARD $idx -i ppp+ -j wanin
	fi
	idx=$(iptables -t filter -L FORWARD -nv --line-number | awk '$4=="wanout" {print $1}')
	if [ ! -z "$idx" ] ; then
		iptables -t filter -D FORWARD $idx
		iptables -t filter -I FORWARD $idx -o ppp+ -j wanout 
	fi
	idx=$(iptables -t filter -L FORWARD -nv --line-number | awk '$4=="upnp" {print $1}')
	if [ ! -z "$idx" ] ; then
		iptables -t filter -D FORWARD $idx
		iptables -t filter -I FORWARD $idx -i ppp+ -j upnp
	fi
	
	
	ip route flush cache
	echo $srouter
	ip route del default > /dev/null 2>&1
	$srouter
	assign_ports
	nvram unset wanx_running 
}

for i in $(seq 2 1 10)
do
	key_enable=wan${i}_enable
	if [ $i -le $wan_ppp_num ] ; then
		nvram set $key_enable=1
	else
		nvram unset $key_enable
	fi
done


if [ "$ACTION" == "firewall-start" ] || [ "$ACTION" == "firewall-stop" ] ; then
	setup_basic_policy_routes
elif [ "$ACTION" == "pppup" ] ; then
	echo "action=pppup" > /dev/kmsg
	setup_basic_policy_routes
elif [ "$ACTION" == "pppdown" ] ; then
	setup_basic_policy_routes
elif [ "$ACTION" == "pppup2" ] ; then
	echo "action=pppup2 $IFNAME" > /dev/kmsg
	setup_basic_policy_routes
elif [ "$ACTION" == "pppdown2" ] ; then
	setup_basic_policy_routes
	echo ifname=${IFNAME} $ACTION > /dev/kmsg
elif [ "$ACTION" == "startall" ] ; then
	setup_basic_policy_routes
elif [ "$ACTION" == "stopall" ] ; then
	for i in $(seq 2 1 $wan_ppp_num)
	do
		key_enable=wan${i}_enable
		nvram set $key_enable=0
	done

	setup_basic_policy_routes
elif [ "${ACTION:0:11}" == "wanx-start-" ] ; then
	echo wanx.sh $ACTION > /dev/kmsg	
elif [ "${ACTION:0:10}" == "wanx-stop-" ] ; then
	echo wanx.sh $ACTION > /dev/kmsg	
else
	echo wanx.sh unknown $ACTION > /dev/kmsg
fi

