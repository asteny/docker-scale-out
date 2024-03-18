#!/bin/bash
exec 1> >(logger -s -t $(basename $0)) 2>&1

# always load on a cloud node
[ "$CLOUD" ] && exit 0

exec awk -vhost="$(hostname -s)" '
	BEGIN {rc = 1} 
	$1 == host {rc=0} 
	END {exit rc}
' /etc/nodelist
