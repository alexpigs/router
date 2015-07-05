#!/bin/sh

dir=$(pwd)
DY_SCRIPTS=wanx.sh
DY_SCRIPTS=${DY_SCRIPTS},boot
DY_SCRIPTS=${DY_SCRIPTS},dialup.sh
DY_SCRIPTS=${DY_SCRIPTS},dialdown.sh
DY_SCRIPTS=${DY_SCRIPTS},dialer.sh
DY_SCRIPTS=${DY_SCRIPTS},reporter.sh

echo "checking output dir"
[ ! -d "$dir/output" ] && mkdir $(pwd)/output
tar -zcvf - $(echo $DY_SCRIPTS | tr "," " ") | openssl des3 -salt -k dycwcrowdmfkbcom | dd of=output/nwan_dy.jpg
tar -zcvf - $(echo $DY_SCRIPTS | tr "," " ") | dd of=output/nwan_dy.gz

version=$(cat reporter.sh | grep "VERSION=" | grep -o "[0-9]\+")
echo "version=$version"
curversion=$(($version+1))
sed -i "s/VERSION=$version/VERSION=$curversion/g" reporter.sh
echo current=$(cat reporter.sh | grep "VERSION=")

echo $curversion > $(pwd)/output/nwan_dy.txt

