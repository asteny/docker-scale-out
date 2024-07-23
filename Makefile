ROOT_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
HOST ?= "login"
BUILD ?= up --build --remove-orphans -d
DC ?= $(shell docker compose version 2>&1 >/dev/null && echo "docker compose" || echo "docker-compose")
IMAGES := $(shell $(DC) config | awk '{if ($$1 == "image:") print $$2;}' | sort | uniq)
SUBNET ?= 10.11
SUBNET6 ?= 2001:db8:1:1::
CLOUD_PID ?= $(ROOT_DIR)/cloud.pid
CLOUD_SOCKET ?= $(ROOT_DIR)/cloud.socket
COMPOSE_YAML ?= $(ROOT_DIR)/docker-compose.yml

# Tell Docker to always prefer the local arch type instead of just the default of the pulled images
DOCKER_DEFAULT_PLATFORM ?= linux/$(shell docker info -f '{{ .Architecture}}')

.EXPORT_ALL_VARIABLES:

default: cloud.socket ./docker-compose.yml run

./docker-compose.yml: buildout.sh
	bash buildout.sh > ./docker-compose.yml

build: ./docker-compose.yml ./cloud.socket
	python3 ./cloud_monitor.py3 "$(DC)" $(COMPOSE_YAML) $(CLOUD_PID) $(CLOUD_SOCKET)
	env BUILDKIT_PROGRESS=plain COMPOSE_HTTP_TIMEOUT=3000 $(DC) $(BUILD)

stop:
	$(DC) down

set_nocache:
	$(eval BUILD := build --no-cache slurmdbd)

nocache: set_nocache build

clean:
	test -f ./docker-compose.yml && ($(DC) up --scale cloud=0 -t1 --no-start; $(DC) kill -s SIGKILL; $(DC) down --remove-orphans -t1 -v; unlink ./docker-compose.yml) || true
	test -f ./docker-compose.yml && ($(DC) kill -s SIGKILL; $(DC) down --scale cloud=0 --remove-orphans -t1 -v; unlink ./docker-compose.yml) || true
	[ -f $(CLOUD_SOCKET) ] && unlink $(CLOUD_SOCKET) || true
	[ -f $(CLOUD_PID) ] && (kill $(shell cat $(CLOUD_PID)) && unlink $(CLOUD_PID)) || true

uninstall:
	$(DC) down --rmi all --remove-orphans -t1 -v
	$(DC) rm -v

run: ./docker-compose.yml ./cloud.socket
	python3 ./cloud_monitor.py3 "$(DC)" $(COMPOSE_YAML) $(CLOUD_PID) $(CLOUD_SOCKET)
	$(DC) up --remove-orphans --build --scale cloud=0 --no-recreate -d

bash:
	$(DC) exec $(HOST) /bin/bash

save: build
	docker save -o scaleout.tar $(IMAGES)

load:
	docker load -i scaleout.tar
