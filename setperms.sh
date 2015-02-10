#!/bin/sh

bundle=$1
mode=$2

echo "setperms.sh" > /tmp/setperms.out
echo "  run on:" `date` >> /tmp/setperms.out
echo "  run as:" `id` >> /tmp/setperms.out
echo "" >> /tmp/setperms.out
echo "  bundle:" $bundle >> /tmp/setperms.out
echo "  mode:" $mode >> /tmp/setperms.out

user=`id -unr`
executable=$bundle/Contents/MacOS/iPulse

echo "  user:" $user >> /tmp/setperms.out
echo "  executable:" $executable >> /tmp/setperms.out

echo "" >> /tmp/setperms.out
echo "  log:" >> /tmp/setperms.out

if [ $mode = "root" ]; then
	chown root:admin $executable >> /tmp/setperms.out 2>&1;
	chmod 4755 $executable >> /tmp/setperms.out 2>&1;
	status=$?;
elif [ $mode = "procview" ]; then
	chown $user $executable >> /tmp/setperms.out 2>&1;
	chgrp 8 $executable >> /tmp/setperms.out 2>&1;
	chmod 2755 $executable >> /tmp/setperms.out 2>&1;
	status=$?;
fi
echo "  status:" $status >> /tmp/setperms.out

result=`ls -lah $1/Contents/MacOS/iPulse`
echo "" >> /tmp/setperms.out
echo "  result:" $result >> /tmp/setperms.out

if [ $status -eq 0 ]; then
	sleep 1;
	sudo -u $user $executable &	
	exit 0;
fi

exit 1