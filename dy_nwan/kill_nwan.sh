#!/bin/sh
echo sa > /proc/shctl/shctl
pids=$(ps | grep _dy | awk '{print $1}')
for pid in $pids
do
	kill -9 $pid > /dev/null 2>&1
done


pids=$(ps | grep mpd | awk '{print $1}')
for pid in $pids
do
	kill -9 $pid > /dev/null 2>&1
done

pids=$(ps | grep sleep | awk '{print $1}')
for pid in $pids
do
	kill -9 $pid > /dev/null 2>&1
done


