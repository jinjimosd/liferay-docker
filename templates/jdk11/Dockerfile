FROM --platform=linux/arm64 jinjimosd/liferay-base as liferay-base-arm64

ARG LABEL_JDK_11_AMD64_VERSION
ARG LABEL_JDK_11_ARM64_VERSION
ARG LABEL_JDK_11_VERSION=${LABEL_JDK_11_ARM64_VERSION}

FROM --platform=linux/amd64 jinjimosd/liferay-base as liferay-base-amd64

ARG LABEL_JDK_11_AMD64_VERSION
ARG LABEL_JDK_11_ARM64_VERSION
ARG LABEL_JDK_11_VERSION=${LABEL_JDK_11_AMD64_VERSION}

FROM liferay-base-${TARGETARCH}

ARG LABEL_BUILD_DATE
ARG LABEL_NAME
ARG LABEL_VCS_REF
ARG LABEL_VCS_URL
ARG LABEL_VERSION
ARG TARGETARCH
ARG TARGETPLATFORM

COPY --chown=liferay:liferay resources/home/liferay/.bashrc /home/liferay/
COPY resources/usr/local/bin/* /usr/local/bin/

ENV JAVA_VERSION=jdk-11

LABEL org.label-schema.build-date="${LABEL_BUILD_DATE}"
LABEL org.label-schema.name="${LABEL_NAME}"
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.vcs-ref="${LABEL_VCS_REF}"
LABEL org.label-schema.vcs-url="${LABEL_VCS_URL}"
LABEL org.label-schema.vendor="Liferay, Inc."
LABEL org.label-schema.version="${LABEL_VERSION}"
LABEL org.label-schema.jdk11_version="${LABEL_JDK_11_VERSION}"
LABEL org.label-schema.jdk11_arm64_version="${LABEL_JDK_11_ARM64_VERSION}"
LABEL org.label-schema.jdk11_amd64_version="${LABEL_JDK_11_AMD64_VERSION}"

RUN apt-get update && \
	apt-get install --no-install-recommends --yes jattach && \
	apt-get upgrade --yes && \
	apt-get clean && \
	curl -H 'accept: */*' -L -s -X 'GET' -o /tmp/jdk11.deb "https://cloud.dogoo.vn/index.php/s/WfsD33YyjtaHN9n/download/jdk-11.0.16_linux-x64_bin.deb" && \
	apt-get install --no-install-recommends --yes /tmp/jdk11.deb && \
	rm /tmp/jdk11.deb && \
	/usr/local/bin/set_java_version.sh