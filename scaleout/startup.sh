#!/bin/bash
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Add hosts in the not crazy slow manner
cat /etc/hosts.nodes >> /etc/hosts
unlink /etc/hosts.nodes

# Force use of /etc/hosts first
sed -e '/^hosts:/d' -i /etc/nsswitch.conf
echo 'hosts:      files dns myhostname' >> /etc/nsswitch.conf

#ensure the systemd cgroup directory exists for enroot
mkdir -p $(awk -F: '$2 ~ /systemd/ {printf "/sys/fs/cgroup/systemd/%s", $3}' /proc/self/cgroup)

mkdir -p -m 0755 /run/slurm/
mkdir -p -m 0770 /auth
chmod -R 0770 /auth
chown slurm:slurm -R /run/slurm /auth

/usr/local/bin/slurmd.check.sh
if [ $? -eq 0 ]
then
	# Compute node only:
	# Force configless by removing copy from original docker build
	# Preserve slurm.key for auth/slurm
	grep 'auth/slurm' /etc/slurm/slurm.conf &>/dev/null
	if [ $? -eq 0 ]
	then
		find /etc/slurm/ ! -name slurm.key ! -name slurm | xargs rm -f
		chown slurm:slurm -R /etc/slurm/

	else
		find /etc/slurm/ | xargs rm -f
	fi
fi

#systemd user@.service handles on normal nodes
for i in arnold bambam barney betty chip dino edna fred gazoo pebbles wilma; do
	uid=$(id -u $i)
	mkdir -m 0700 -p /run/user/$uid
	chown $i:users /run/user/$uid
done

for s in sackd.service slurmctld.service slurmd.service slurmdbd.service slurmrestd.service
do
	#We must set the cluster environment variable for all services since systemd drops it for the services
	p="/etc/systemd/system/${s}.d/"
	f="${p}/cluster.conf"
	mkdir -p ${p}
	echo -e "[Service]\n" > ${f}
	echo -e "Environment=SLURM_FEDERATION_CLUSTER=${SLURM_FEDERATION_CLUSTER}\n" >> ${f}
	[ ! -z "$SLURM_CONF_SERVER" ] && echo -e "Environment=SLURM_CONF_SERVER=${SLURM_CONF_SERVER}\n" >> ${f}
done

[ ! -z "$SLURM_CONF_SERVER" ] && echo "export SLURM_CONF_SERVER=${SLURM_CONF_SERVER}" >> /etc/profile
echo "export SLURM_FEDERATION_CLUSTER=${SLURM_FEDERATION_CLUSTER}" >> /etc/profile

if [ $CLOUD ]
then
	# Override slurmd.service with cloud version
	mv /usr/local/etc/slurmd.cloud.service \
		/etc/systemd/system/slurmd.service.d/local.conf

	while true
	do
		#init this cloud node
		host="$(echo "whoami:$(hostname)" | socat -t999 STDIO UNIX-CONNECT:/run/cloud.socket)"

		[ -z "$host" -o "$host" == "FAIL" ] || break
		sleep 0.25
	done

	hostname $host
	echo "$host" > /etc/hostname

	echo "Environment=\"NODENAME=$host\"" >>/etc/systemd/system/slurmd.service.d/local.conf
fi

#start systemd
exec /lib/systemd/systemd --system --log-level=info --crash-reboot --log-target=console
