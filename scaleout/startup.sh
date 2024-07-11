#!/bin/bash

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

ls /usr/lib/systemd/system/{slurm*.service,sackd.service} | while read s
do
	#We must set the cluster environment variable for all services since systemd drops it for the services
	mkdir -p ${s}.d
	echo -e "[Service]\n" > ${s}.d/cluster.conf
	echo -e "Environment=SLURM_FEDERATION_CLUSTER=${SLURM_FEDERATION_CLUSTER}\n" >> ${s}.d/cluster.conf
	[ ! -z "$SLURM_CONF_SERVER" ] && echo -e "Environment=SLURM_CONF_SERVER=${SLURM_CONF_SERVER}\n" >> ${s}.d/cluster.conf
done

echo "export SLURM_CONF_SERVER=${SLURM_CONF_SERVER} SLURM_FEDERATION_CLUSTER=${SLURM_FEDERATION_CLUSTER}" >> /etc/profile

#start systemd
exec /lib/systemd/systemd --system --log-level=info --crash-reboot --log-target=console
