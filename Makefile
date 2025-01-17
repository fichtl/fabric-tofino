PROFILES ?= all
ONOS_HOST ?= localhost
P4CFLAGS ?=

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
curr_dir := $(patsubst %/,%,$(dir $(mkfile_path)))
curr_dir_sha := $(shell echo -n "$(curr_dir)" | shasum | cut -c1-7)

mvn_image := maven:3.6.1-jdk-11-slim
mvn_container := mvn-build-${curr_dir_sha}

onos_url := http://${ONOS_HOST}:8181/onos
onos_curl := curl --fail -sSL --user onos:rocks --noproxy localhost

pipeconf_app_name := org.opencord.fabric-tofino
pipeconf_oar_file := $(shell ls -1 ${curr_dir}/target/fabric-tofino-*.oar)

p4-build := ./src/main/p4/build.sh

.PHONY: pipeconf

build: clean $(PROFILES) pipeconf p4-changelog

all: fabric fabric-bng fabric-spgw fabric-int fabric-spgw-int

fabric:
	@${p4-build} fabric $(P4CFLAGS)

fabric-simple:
	@${p4-build} fabric-simple -DWITH_SIMPLE_NEXT $(P4CFLAGS)

fabric-bng:
	@${p4-build} fabric-bng -DWITH_BNG -DWITHOUT_XCONNECT $(P4CFLAGS)

fabric-int:
	@${p4-build} fabric-int -DWITH_INT_SOURCE -DWITH_INT_TRANSIT $(P4CFLAGS)

fabric-spgw:
	@${p4-build} fabric-spgw -DWITH_SPGW $(P4CFLAGS)

fabric-spgw-int:
	@${p4-build} fabric-spgw-int -DWITH_SPGW -DWITH_INT_SOURCE -DWITH_INT_TRANSIT $(P4CFLAGS)

p4-changelog:
	./src/main/p4/gen_changelog.sh > P4_CHANGELOG

# Reuse the same container to persist mvn repo cache.
_create_mvn_container:
	@if ! docker container ls -a --format '{{.Names}}' | grep -q ${mvn_container} ; then \
		docker create -v ${curr_dir}:/mvn-src -w /mvn-src --name ${mvn_container} ${mvn_image} mvn clean package verify; \
	fi

_mvn_package:
	$(info *** Building ONOS app...)
	@mkdir -p target
	@docker start -a -i ${mvn_container}

pipeconf: _create_mvn_container _mvn_package
	$(info *** ONOS pipeconf .oar package created succesfully)
	@ls -1 ${curr_dir}/target/*.oar

pipeconf-install:
	$(info *** Installing and activating pipeconf app in ONOS at ${ONOS_HOST}...)
	${onos_curl} -X POST -HContent-Type:application/octet-stream \
		'${onos_url}/v1/applications?activate=true' \
		--data-binary @${pipeconf_oar_file}
	@echo

pipeconf-uninstall:
	$(info *** Uninstalling pipeconf app from ONOS (if present) at ${ONOS_HOST}...)
	-${onos_curl} -X DELETE ${onos_url}/v1/applications/${pipeconf_app_name}
	@echo

netcfg:
	$(info *** Pushing tofino-netcfg.json to ONOS at ${ONOS_HOST}...)
	${onos_curl} -X POST -H 'Content-Type:application/json' \
		${onos_url}/v1/network/configuration -d@./tofino-netcfg.json
	@echo

clean:
	-rm -rf src/main/resources/p4c-out

deep-clean: clean
	-rm -rf target
	-rm -rf p4c-out
	-docker rm ${mvn_container} > /dev/null 2>&1
