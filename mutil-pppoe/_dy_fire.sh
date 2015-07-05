#!/bin/sh



iptables -N swan > /dev/null 2>&1 
iptables -N nwan2 > /dev/null 2>&1 
iptables -N nwan3 > /dev/null 2>&1 
iptables -N nwan4 > /dev/null 2>&1 
iptables -N nwan5 > /dev/null 2>&1 
iptables -N nwan6 > /dev/null 2>&1 
iptables -N nwan7 > /dev/null 2>&1 
iptables -N nwan8 > /dev/null 2>&1 
iptables -N nwan9 > /dev/null 2>&1 

iptables -A INPUT -j swan > /dev/null 2>&1
iptables -A INPUT -i p-hid2 -j nwan2 > /dev/null 2>&1
iptables -A INPUT -i p-hid3 -j nwan3 > /dev/null 2>&1
iptables -A INPUT -i p-hid4 -j nwan4 > /dev/null 2>&1
iptables -A INPUT -i p-hid5 -j nwan5 > /dev/null 2>&1
iptables -A INPUT -i p-hid6 -j nwan6 > /dev/null 2>&1
iptables -A INPUT -i p-hid7 -j nwan7 > /dev/null 2>&1
iptables -A INPUT -i p-hid8 -j nwan8 > /dev/null 2>&1
iptables -A INPUT -i p-hid9 -j nwan9 > /dev/null 2>&1


restore_port(){
	key=$1
	table=$2
	value=$(nvram get $key)
	if [ -z "$value" ] ; then
		return
	fi
	
	iptables -t filter -A "$table"  -p tcp --dport $value -j ACCEPT > /dev/null 2>&1
}


restore_port swan_tp_port swan
restore_port nwan_p-hid2_tp_port nwan2 
restore_port nwan_p-hid3_tp_port nwan3 
restore_port nwan_p-hid4_tp_port nwan4 
restore_port nwan_p-hid5_tp_port nwan5 
restore_port nwan_p-hid6_tp_port nwan6 
restore_port nwan_p-hid7_tp_port nwan7 
restore_port nwan_p-hid8_tp_port nwan8 
restore_port nwan_p-hid9_tp_port nwan9 
