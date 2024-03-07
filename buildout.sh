#!/bin/bash
unset MAC
[[ $OSTYPE == 'darwin'* ]] && MAC=1

#only mount cgroups with v1
#https://github.com/jepsen-io/jepsen/issues/532#issuecomment-1128067136
[ ! -f /sys/fs/cgroup/cgroup.controllers ] && SYSDFSMOUNTS="
      - /dev/log:/dev/log
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/:/sys/:ro
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
" || SYSDFSMOUNTS="
      - /dev/log:/dev/log
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
"

CACHE_DESTROYER="$(find scaleout/patch.d -type f -name '*.patch' -print0 | sort -z | xargs -0 cat | sha256sum | cut -b1-20)"

SLURM_RELEASE="${SLURM_RELEASE:-master}"
DISTRO="almalinux:8"
if [ -z "$SUBNET" -o "$SUBNET" = "10.11" ]
then
	ES_PORTS="
    ports:
      - 9200:9200
"
	KIBANA_PORTS="
    ports:
      - 5601:5601
"
	PROXY_PORTS="
    ports:
      - 8080:8080
"
	GRAFANA_PORTS="
    ports:
      - 3000:3000
"
	ONDEMAND_PORTS="
    ports:
      - 8081:80
"
	XDMOD_PORTS="
    ports:
      - 8082:80
"
else
	ES_PORTS=
	KIBANA_PORTS=
	PROXY_PORTS=
	GRAFANA_PORTS=
	XDMOD_PORTS=
fi

SUBNET=${SUBNET:-"10.11"}
SUBNET6=${SUBNET6:-"2001:db8:1:1::"}
NODELIST=${NODELIST:-"scaleout/nodelist"}

if [ ! -s "$NODELIST" ]
then
	if [ ! -z "$FEDERATION" ]
	then
		c_sub=5
		[ -f "$NODELIST" ] && unlink "$NODELIST" 2>&1 >/dev/null
		for c in $FEDERATION
		do
			#generate list of 10 nodes per cluster
			seq 0 9 | while read i
			do
				echo "$(printf "$c-node%02d" $i) $c ${SUBNET}.${c_sub}.$((${i} + 10)) ${SUBNET6}${c_sub}:$((${i} + 10))"
			done >> $NODELIST

			c_sub=$((c_sub+1))
		done
	else
		#generate list of 10 nodes
		seq 0 9 | while read i
		do
			echo "$(printf "node%02d" $i) cluster ${SUBNET}.5.$((${i} + 10)) ${SUBNET6}5:$((${i} + 10))"
		done > $NODELIST
	fi
fi

unlink scaleout/hosts.nodes
cat "$NODELIST" | while read name cluster ip4 ip6
do
	[ ! -z "$ip4" ] && echo "$ip4 $name" >> scaleout/hosts.nodes
	[ ! -z "$ip6" ] && echo "$ip6 $name" >> scaleout/hosts.nodes
done

HOSTLIST="    extra_hosts:
      - \"db:${SUBNET}.1.3\"
      - \"db:${SUBNET6}1:3\"
      - \"slurmdbd:${SUBNET}.1.2\"
      - \"slurmdbd:${SUBNET6}1:2\"
      - \"login:${SUBNET}.1.5\"
      - \"login:${SUBNET6}1:5\"
      - \"rest:${SUBNET}.1.6\"
      - \"rest:${SUBNET6}1:6\"
      - \"proxy:${SUBNET}.1.7\"
      - \"proxy:${SUBNET6}1:7\"
      - \"es01:${SUBNET}.1.15\"
      - \"es01:${SUBNET6}1:15\"
      - \"es02:${SUBNET}.1.16\"
      - \"es02:${SUBNET6}1:16\"
      - \"es03:${SUBNET}.1.17\"
      - \"es03:${SUBNET6}1:17\"
      - \"kibana:${SUBNET}.1.18\"
      - \"kibana:${SUBNET6}1:18\"
      - \"influxdb:${SUBNET}.1.19\"
      - \"influxdb:${SUBNET6}1:19\"
      - \"grafana:${SUBNET}.1.20\"
      - \"grafana:${SUBNET6}1:20\"
      - \"open-ondemand:${SUBNET}.1.21\"
      - \"open-ondemand:${SUBNET6}1:21\"
      - \"xdmod:${SUBNET}.1.22\"
      - \"xdmod:${SUBNET6}1:22\"
"

if [ ! -z "$FEDERATION" ]
then
	FIRST_CLUSTER="$(echo "$FEDERATION" | awk '{print $1}')"
	FIRST_MGMTNODE="${FIRST_CLUSTER}-mgmtnode"
	c_sub=5

	for c in $FEDERATION
	do
		HOSTLIST="${HOSTLIST}      - \"${c}-mgmtnode:${SUBNET}.${c_sub}.1\""$'\n'
		HOSTLIST="${HOSTLIST}      - \"${c}-mgmtnode:${SUBNET6}${c_sub}:1\""$'\n'
		HOSTLIST="${HOSTLIST}      - \"${c}-mgmtnode2:${SUBNET}.${c_sub}.2\""$'\n'
		HOSTLIST="${HOSTLIST}      - \"${c}-mgmtnode2:${SUBNET6}${c_sub}:2\""$'\n'

		c_sub=$((c_sub + 1))
	done
else
	FIRST_CLUSTER="cluster"
	FIRST_MGMTNODE="mgmtnode"
	HOSTLIST="${HOSTLIST}      - \"mgmtnode:${SUBNET}.1.1\""$'\n'
	HOSTLIST="${HOSTLIST}      - \"mgmtnode:${SUBNET6}1:1\""$'\n'
	HOSTLIST="${HOSTLIST}      - \"mgmtnode2:${SUBNET}.1.4\""$'\n'
	HOSTLIST="${HOSTLIST}      - \"mgmtnode2:${SUBNET6}1:4\""$'\n'
fi

LOGGING="
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
"

XDMOD="
  xdmod:
    build:
      context: ./xdmod
      network: host
    image: xdmod:latest
    environment:
      - SUBNET=\"${SUBNET}\"
      - SUBNET6=\"${SUBNET6}\"
      - container=docker
    hostname: xdmod
    command: [\"/sbin/startup.sh\"]
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.22
        ipv6_address: ${SUBNET6}1:22
    volumes:
$SYSDFSMOUNTS
      - xdmod:/xdmod/
$XDMOD_PORTS
$LOGGING
$HOSTLIST
"

if [ "$DISABLE_XDMOD" ]
then
	XDMOD=""
fi

if [ "$CLOUD" ]
then
	CLOUD_MOUNTS="
      - type: bind
        source: $(readlink -e $(pwd)/cloud_socket)
        target: /run/cloud_socket
"
else
	CLOUD_MOUNTS=""
fi
# disable Linux specific options
[ $MAC ] && LOGGING=

cat <<EOF
---
version: "3.8"
networks:
  internal:
    driver: bridge
    driver_opts:
        com.docker.network.bridge.enable_ip_masquerade: 'true'
        com.docker.network.bridge.enable_icc: 'true'
    internal: false
    enable_ipv6: true
    ipam:
      config:
        - subnet: "${SUBNET}.0.0/16"
        - subnet: "${SUBNET6}/64"
volumes:
  root-home:
  home:
  etc-ssh:
EOF

if [ ! -z "$FEDERATION" ]
then

	for c in $FEDERATION
	do
		cat <<EOF
  ${c}-etc-slurm:
  ${c}-slurmctld:
EOF
	done

else

cat <<EOF
  cluster-etc-slurm:
  slurmctld:
EOF

fi

cat <<EOF
  elastic_data01:
  elastic_data02:
  elastic_data03:
  mail:
  auth:
  xdmod:
  src:
  container-shared:
services:
  db:
    image: sql_server:latest
    build:
      context: ./sql_server
      args:
        SUBNET: "$SUBNET"
        SUBNET6: "$SUBNET6"
      network: host
    environment:
      - MYSQL_ROOT_PASSWORD=password
      - MYSQL_USER=slurm
      - MYSQL_PASSWORD=password
      - MYSQL_DATABASE=slurm_acct_db
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
    volumes:
      - /dev/log:/dev/log
    hostname: db
$LOGGING
    networks:
      internal:
        ipv4_address: "${SUBNET}.1.3"
        ipv6_address: "${SUBNET6}1:3"
$HOSTLIST
  slurmdbd:
    build:
      context: ./scaleout
      args:
        DOCKER_FROM: $DISTRO
        SLURM_RELEASE: $SLURM_RELEASE
        SUBNET: "$SUBNET"
        SUBNET6: "$SUBNET6"
        CACHE_DESTROYER: "$CACHE_DESTROYER"
      network: host
    image: scaleout:latest
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET}"
    hostname: slurmdbd
    networks:
      internal:
        ipv4_address: "${SUBNET}.1.2"
        ipv6_address: "${SUBNET6}1:2"
    volumes:
      - root-home:/root
      - ${FIRST_CLUSTER}-etc-slurm:/etc/slurm
      - mail:/var/spool/mail/
      - src:/usr/local/src/
$SYSDFSMOUNTS
$LOGGING
    depends_on:
      - "db"
$HOSTLIST
EOF

if [ ! -z "$FEDERATION" ]
then
	LOGIN_MOUNTS=

	c_sub=5
	for c in $FEDERATION
	do

cat <<EOF
  ${c}-mgmtnode:
    image: scaleout:latest
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - container=docker
      - SLURM_FEDERATION_CLUSTER=${c}
    hostname: ${c}-mgmtnode
    networks:
      internal:
        ipv4_address: ${SUBNET}.${c_sub}.1
        ipv6_address: ${SUBNET6}${c_sub}:1
    volumes:
      - root-home:/root
      - home:/home/
      - ${c}-slurmctld:/var/spool/slurm
      - etc-ssh:/etc/ssh
      - ${c}-etc-slurm:/etc/slurm
      - mail:/var/spool/mail/
      - auth:/auth/
      - xdmod:/xdmod/
      - src:/usr/local/src/
$SYSDFSMOUNTS
$CLOUD_MOUNTS
$LOGGING
    depends_on:
      - "slurmdbd"
$HOSTLIST
  ${c}-mgmtnode2:
    image: scaleout:latest
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - container=docker
      - SLURM_FEDERATION_CLUSTER=${c}
    hostname: ${c}-mgmtnode2
    networks:
      internal:
        ipv4_address: ${SUBNET}.${c_sub}.4
        ipv6_address: ${SUBNET6}${c_sub}:4
    volumes:
      - root-home:/root
      - etc-ssh:/etc/ssh
      - ${c}-etc-slurm:/etc/slurm
      - home:/home/
      - ${c}-slurmctld:/var/spool/slurm
      - mail:/var/spool/mail/
      - src:/usr/local/src/
$SYSDFSMOUNTS
$CLOUD_MOUNTS
$LOGGING
    depends_on:
      - "slurmdbd"
      - "${c}-mgmtnode"
$HOSTLIST
EOF

		c_sub=$((c_sub+1))
	done

else

	LOGIN_MOUNTS="      - slurmctld:/var/spool/slurm"

cat <<EOF
  mgmtnode:
    image: scaleout:latest
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - container=docker
      - SLURM_FEDERATION_CLUSTER=${FIRST_CLUSTER}
    hostname: mgmtnode
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.1
        ipv6_address: ${SUBNET6}1:1
    volumes:
      - root-home:/root
      - home:/home/
      - slurmctld:/var/spool/slurm
      - etc-ssh:/etc/ssh
      - ${FIRST_CLUSTER}-etc-slurm:/etc/slurm
      - mail:/var/spool/mail/
      - auth:/auth/
      - xdmod:/xdmod/
      - src:/usr/local/src/
$SYSDFSMOUNTS
$CLOUD_MOUNTS
$LOGGING
    depends_on:
      - "slurmdbd"
$HOSTLIST
  mgmtnode2:
    image: scaleout:latest
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - container=docker
      - SLURM_FEDERATION_CLUSTER=${FIRST_CLUSTER}
    hostname: mgmtnode2
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.4
        ipv6_address: ${SUBNET6}1:4
    volumes:
      - root-home:/root
      - etc-ssh:/etc/ssh
      - ${FIRST_CLUSTER}-etc-slurm:/etc/slurm
      - home:/home/
      - slurmctld:/var/spool/slurm
      - mail:/var/spool/mail/
      - src:/usr/local/src/
$SYSDFSMOUNTS
$CLOUD_MOUNTS
$LOGGING
    depends_on:
      - "slurmdbd"
      - "mgmtnode"
$HOSTLIST
EOF

fi #end mgmtnode creation

cat <<EOF
  login:
    image: scaleout:latest
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - container=docker
    hostname: login
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.5
        ipv6_address: ${SUBNET6}1:5
    volumes:
      - root-home:/root
      - etc-ssh:/etc/ssh
      - ${FIRST_CLUSTER}-etc-slurm:/etc/slurm
      - home:/home/
$LOGIN_MOUNTS
      - mail:/var/spool/mail/
      - src:/usr/local/src/
      - /var/lib/containers
      - /dev/fuse:/dev/fuse:rw
      - container-shared:/srv/containers
$SYSDFSMOUNTS
$LOGGING
$HOSTLIST
EOF

lastcluster="$FIRST_CLUSTER"
lastname="$FIRST_MGMTNODE"
oi=0
cat "$NODELIST" | while read name cluster ip4 ip6
do
	[ "$cluster" != "$lastcluster" ] && lastname="${cluster}-mgmtnode"
	lastcluster="$cluster"

	oi=$(($oi + 1))
	i=$(($i + 1))

	i4=
	i6=
	[ ! -z "$ip4" ] && i4="ipv4_address: $ip4"
	[ ! -z "$ip6" ] && i6="ipv6_address: $ip6"
cat <<EOF
  $name:
    image: scaleout:latest
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - container=docker
      - SLURM_FEDERATION_CLUSTER=${cluster}
    hostname: $name
    networks:
      internal:
        $i4
        $i6
    volumes:
      - root-home:/root
      - etc-ssh:/etc/ssh
      - ${cluster}-etc-slurm:/etc/slurm
      - home:/home/
      - mail:/var/spool/mail/
      - src:/usr/local/src/
      - container-shared:/srv/containers
$SYSDFSMOUNTS
    ulimits:
      nproc:
        soft: 65535
        hard: 65535
      nofile:
        soft: 131072
        hard: 131072
      memlock:
        soft: -1
        hard: -1
$LOGGING
    depends_on:
      - "$lastname"
$HOSTLIST
EOF

	[ $oi -gt 100 -a ! -z "$name" ] && oi=0 && lastname="$name"
done

[ "$CLOUD" ] && cat <<EOF
  cloud:
    image: scaleout:latest
    networks:
      internal: {}
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - container=docker
      - CLOUD=1
    volumes:
      - root-home:/root
      - etc-ssh:/etc/ssh
      - ${FIRST_CLUSTER}-etc-slurm:/etc/slurm
      - home:/home/
      - mail:/var/spool/mail/
      - src:/usr/local/src/
      - container-shared:/srv/containers
$SYSDFSMOUNTS
$CLOUD_MOUNTS
    ulimits:
      nproc:
        soft: 65535
        hard: 65535
      nofile:
        soft: 131072
        hard: 131072
      memlock:
        soft: -1
        hard: -1
$LOGGING
$HOSTLIST
EOF

cat <<EOF
  open-ondemand:
    build:
      context: ./open-ondemand
      network: host
    image: open-ondemand
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - DEFAULT_SSHHOST=login
    volumes:
      - /dev/log:/dev/log
      - etc-ssh:/etc/shared-ssh
      - home:/home/
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.21
        ipv6_address: ${SUBNET6}1:21
    depends_on:
      - "login"
$ONDEMAND_PORTS
$LOGGING
  influxdb:
    build:
      context: ./influxdb
      network: host
    image: influxdb
    command: ["bash", "-c", "/setup.sh & source /entrypoint.sh"]
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=user
      - DOCKER_INFLUXDB_INIT_PASSWORD=password
      - DOCKER_INFLUXDB_INIT_ORG=scaleout
      - DOCKER_INFLUXDB_INIT_BUCKET=scaleout
      - DOCKER_INFLUXDB_INIT_RETENTION=1w
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=token
      - DOCKER_INFLUXDB_INIT_USER_ID=
      - INFLUXDB_DATA_QUERY_LOG_ENABLED=true
      - INFLUXDB_REPORTING_DISABLED=false
      - INFLUXDB_HTTP_LOG_ENABLED=true
      - INFLUXDB_CONTINUOUS_QUERIES_LOG_ENABLED=true
      - LOG_LEVEL=debug
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.19
        ipv6_address: ${SUBNET6}1:19
$LOGGING
  grafana:
    image: grafana
    build:
      context: ./grafana
      network: host
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
    volumes:
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.20
        ipv6_address: ${SUBNET6}1:20
$GRAFANA_PORTS
$LOGGING
  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.1
    environment:
      - node.name=es01
      - cluster.name=scaleout
      - discovery.seed_hosts=es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elastic_data01:/usr/share/elasticsearch/data
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.15
        ipv6_address: ${SUBNET6}1:15
${ES_PORTS}
$LOGGING
  es02:
    image: docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.1
    environment:
      - node.name=es02
      - cluster.name=scaleout
      - discovery.seed_hosts=es01,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elastic_data02:/usr/share/elasticsearch/data
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.16
        ipv6_address: ${SUBNET6}1:16
$LOGGING
  es03:
    image: docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.1
    environment:
      - node.name=es03
      - cluster.name=scaleout
      - discovery.seed_hosts=es01,es02
      - cluster.initial_master_nodes=es01,es02,es03
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elastic_data03:/usr/share/elasticsearch/data
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.17
        ipv6_address: ${SUBNET6}1:17
$LOGGING
  kibana:
    image: docker.elastic.co/kibana/kibana-oss:7.10.1
    volumes:
      - /dev/log:/dev/log
    environment:
      - SERVER_NAME=scaleout
      - ELASTICSEARCH_HOSTS=http://es01:9200
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.18
        ipv6_address: ${SUBNET6}1:18
${KIBANA_PORTS}
    depends_on:
      - "es01"
      - "es02"
      - "es03"
$LOGGING
  rest:
    hostname: rest
    image: scaleout:latest
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.6
        ipv6_address: ${SUBNET6}1:6
    volumes:
      - etc-ssh:/etc/ssh
      - ${FIRST_CLUSTER}-etc-slurm:/etc/slurm
$SYSDFSMOUNTS
$LOGGING
    depends_on:
      - "${FIRST_MGMTNODE}"
$HOSTLIST
  proxy:
    build:
      context: ./proxy
      network: host
    image: proxy:latest
    environment:
      - SUBNET="${SUBNET}"
      - SUBNET6="${SUBNET6}"
      - container=docker
    hostname: proxy
    command: ["bash", "-c", "/usr/sbin/nginx& /usr/sbin/php-fpm81 -F& wait"]
    networks:
      internal:
        ipv4_address: ${SUBNET}.1.7
        ipv6_address: ${SUBNET6}1:7
    volumes:
      - auth:/auth/
      - /dev/log:/dev/log
$LOGGING
${PROXY_PORTS}
    depends_on:
      - "rest"
$HOSTLIST
$XDMOD
EOF

exit 0

