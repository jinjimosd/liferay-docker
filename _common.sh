#!/bin/bash

function check_docker_buildx {
	docker build buildx --help > /dev/null 2>&1

	if [ $? -gt 0 ]
	then
		echo "Docker Buildx is not available."

		exit 1
	fi

	if [ $(docker buildx ls | grep -c -w "liferay-buildkit") -eq 0 ]
	then
		docker buildx create --name "liferay-buildkit"
	fi
}

function check_utils {

	#
	# https://stackoverflow.com/a/677212
	#

	for util in "${@}"
	do
		command -v "${util}" >/dev/null 2>&1 || { echo >&2 "The utility ${util} is not installed."; exit 1; }
	done
}

function clean_up_temp_directory {
	rm -fr "${TEMP_DIR}"
}

function configure_tomcat {
	printf "\nCATALINA_OPTS=\"\${CATALINA_OPTS} \${LIFERAY_JVM_OPTS}\"" >> "${TEMP_DIR}/liferay/tomcat/bin/setenv.sh"
}

function date {
	export LC_ALL=en_US.UTF-8
	export TZ=America/Los_Angeles

	if [ -z ${1+x} ] || [ -z ${2+x} ]
	then
		if [ "$(uname)" == "Darwin" ]
		then
			/bin/date
		elif [ -e /bin/date ]
		then
			/bin/date --iso-8601=seconds
		else
			/usr/bin/date --iso-8601=seconds
		fi
	else
		if [ "$(uname)" == "Darwin" ]
		then
			/bin/date -jf "%a %b %e %H:%M:%S %Z %Y" "${1}" "${2}"
		elif [ -e /bin/date ]
		then
			/bin/date -d "${1}" "${2}"
		else
			/usr/bin/date -d "${1}" "${2}"
		fi
	fi
}

function delete_local_images {
	if [[ "${LIFERAY_DOCKER_DEVELOPER_MODE}" == "true" ]] && [ -n "${1}" ]
	then
		echo "Deleting local ${1} images."

		for image_id in $(docker image ls | grep "${1}" | awk '{print $3}' | uniq)
		do
			docker image rm -f "${image_id}"
		done
	fi
}

function download {
	local file_name="${1}"
	local file_url="${2}"

	if [ -e "${file_name}" ] && [[ "${file_url}" != */nightly/* ]] && [[ "${file_url}" != */latest/* ]]
	then
		return
	fi

	if [[ "${file_url}" != http*://* ]]
	then
		file_url="http://${file_url}"
	fi

	if [[ "${file_url}" != http://mirrors.*.liferay.com* ]] &&
	   [[ "${file_url}" != http://release-1* ]] &&
	   [[ "${file_url}" != https://release.liferay.com* ]]
	then
		if [ ! -n "${LIFERAY_DOCKER_MIRROR}" ]
		then
			LIFERAY_DOCKER_MIRROR=lax
		fi

		file_url="http://mirrors.${LIFERAY_DOCKER_MIRROR}.liferay.com/"${file_url##*//}
	fi

	echo ""
	echo "Downloading ${file_url}."
	echo ""

	mkdir -p $(dirname "${file_name}")

	curl $(echo "${LIFERAY_DOCKER_CURL_OPTIONS}") --fail --location --output "${file_name}" "${file_url}" || exit 2
}

function get_current_arch {
	if [ $(uname -m) == "aarch64" ]
	then
		echo "arm64"
	else
		echo "amd64"
	fi
}

function get_docker_image_tags_args {
	local docker_image_tags_args=""

	for docker_image_tag in "${@}"
	do
		docker_image_tags_args="${docker_image_tags_args} --tag ${docker_image_tag}"
	done

	echo "${docker_image_tags_args}"
}

function get_tomcat_version {
	for temp_file_name in "${1}"/tomcat-*
	do
		if [ -e  "${temp_file_name}" ]
		then
			local tomcat_folder=${temp_file_name##*/}
			local liferay_tomcat_version=${tomcat_folder#*-}
		fi
		break
	done

	if [ -z ${liferay_tomcat_version+x} ]
	then
		echo "Unable to determine Tomcat version."

		exit 1
	fi

	echo "${liferay_tomcat_version}"
}

function log_in_to_docker_hub {
	if [ ! -n "${LIFERAY_DOCKER_HUB_LOGGED_IN}" ] && [ -n "${LIFERAY_DOCKER_HUB_TOKEN}" ] && [ -n "${LIFERAY_DOCKER_HUB_USERNAME}" ]
	then
		echo ""
		echo "Logging in to Docker Hub."
		echo ""

		echo "${LIFERAY_DOCKER_HUB_TOKEN}" | docker login --password-stdin -u "${LIFERAY_DOCKER_HUB_USERNAME}"

		LIFERAY_DOCKER_HUB_LOGGED_IN=true
	fi
}

function make_temp_directory {
	CURRENT_DATE=$(date)

	TIMESTAMP=$(date "${CURRENT_DATE}" "+%Y%m%d%H%M%S")

	TEMP_DIR="temp-${TIMESTAMP}"

	mkdir -p "${TEMP_DIR}"

	cp -r "${1}"/* "${TEMP_DIR}"
}

function pid_8080 {
	local pid=$(lsof -Fp -i 4tcp:8080 -sTCP:LISTEN | head -n 1)

	echo "${pid##p}"
}

function prepare_tomcat {
	local liferay_tomcat_version=$(get_tomcat_version "${TEMP_DIR}/liferay")

	mv "${TEMP_DIR}/liferay/tomcat-${liferay_tomcat_version}" "${TEMP_DIR}/liferay/tomcat"

	ln -s tomcat "${TEMP_DIR}/liferay/tomcat-${liferay_tomcat_version}"

	configure_tomcat

	if [[ ! " ${@} " =~ " --no-warm-up " ]]
	then
		warm_up_tomcat
	fi

	rm -fr "${TEMP_DIR}"/liferay/logs/*
	rm -fr "${TEMP_DIR}"/liferay/tomcat/logs/*
}

function remove_temp_dockerfile_target_platform {
	sed -i'.bak' 's/${TARGETARCH}'/$(get_current_arch)/ "${TEMP_DIR}"/Dockerfile
	sed -i'' 's/--platform=${TARGETPLATFORM} //g' "${TEMP_DIR}"/Dockerfile
}

function start_tomcat {

	#
	# Increase the available memory for warming up Tomcat. This is needed
	# because LPKG hash and OSGi state processing for 7.0.x is expensive. Set
	# this for all scenarios since it is limited to warming up Tomcat.
	#

	LIFERAY_JVM_OPTS="-Xmx3G"

	local pid=$(pid_8080)

	if [ -n "${pid}" ]
	then
		echo ""
		echo "Killing process ${pid} that is listening on port 8080."
		echo ""

		kill -9 "${pid}" 2>/dev/null
	fi

	"./${TEMP_DIR}/liferay/tomcat/bin/catalina.sh" start

	until curl --fail --head --output /dev/null --silent http://localhost:8080
	do
		sleep 3
	done

	pid=$(pid_8080)

	"./${TEMP_DIR}/liferay/tomcat/bin/catalina.sh" stop

	for i in {0..30..1}
	do
		if kill -0 "${pid}" 2>/dev/null
		then
			sleep 1
		fi
	done

	kill -0 "${pid}" 2>/dev/null && kill -9 "${pid}" 2>/dev/null

	rm -fr "${TEMP_DIR}/liferay/data/osgi/state"
	rm -fr "${TEMP_DIR}/liferay/osgi/state"
}

function stat {
	if [ "$(uname)" == "Darwin" ]
	then
		/usr/bin/stat -f "%z" "${1}"
	else
		/usr/bin/stat --printf="%s" "${1}"
	fi
}

function test_docker_image {
	export LIFERAY_DOCKER_IMAGE_ID="${DOCKER_IMAGE_TAGS[0]}"

	if [[ ! " ${@} " =~ " --no-test-image " ]]
	then
		./test_image.sh

		if [ $? -gt 0 ]
		then
			echo "Testing failed, exiting."

			exit 2
		fi
	fi
}

function warm_up_tomcat {

	#
	# Warm up Tomcat for older versions to speed up starting Tomcat. Populating
	# the Hypersonic files can take over 20 seconds.
	#

	if [ -e "${TEMP_DIR}/liferay/data/hsql/lportal.script" ]
	then
		if [ $(stat "${TEMP_DIR}/liferay/data/hsql/lportal.script") -lt 1024000 ]
		then
			start_tomcat
		else
			echo Tomcat is already warmed up.
		fi
	elif [ -e "${TEMP_DIR}/liferay/data/hypersonic/lportal.script" ]
	then
		if [ $(stat "${TEMP_DIR}/liferay/data/hypersonic/lportal.script") -lt 1024000 ]
		then
			start_tomcat
		else
			echo Tomcat is already warmed up.
		fi
	else
		start_tomcat
	fi
}