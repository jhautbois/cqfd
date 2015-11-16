#! /bin/bash -

#
# Copyright (C) 2015 Savoir-faire Linux, Inc.
#
# Author: mathieu.audat@savoirfairelinux.com
#

EERROR=1
ESUCCESS=0

PROGNAME=`basename $0`

## usage() - print the usage in stdin
usage() {
cat << EOF
Usage: ${PROGNAME} -g <GIT_BRANCH> [OPTIONS]

* If you have a .sflproject: ${PROGNAME}
* If you want to build with a special command: ${PROGNAME} -b <"CMD">
* If you want default build command: ${PROGNAME} <OPTIONS>

Options are:
	-m <buildroot | yocto | openwrt>    Model of build system to use.
	-p <build parameter>		    It can be the name of the
                                              configuration file in buildroot
					      or the recipe in yocto.
	-b <build command>		    Specify a build command to pass to
					      docker.
	-g <git branch>			    The git branch you want to build.
					      Default is master
	-j				    Make an archive out of release
					      files
EOF
}

## die() - exit when an error occured
# $@ messages and variables shown in the error message
die() {
	echo "Fatal: $@" 1>&2
	exit ${EERROR}
}

## docker_run() - run command in configured container
docker_run() {
	docker -D build -t "${GIT_BRANCH}" .
	docker -D run --privileged -v "$PWD":/home/builder -v ~/.ssh:/home/builder/.ssh \
	-v `dirname $SSH_AUTH_SOCK`:/home/builder/.sockets -it \
		"${GIT_BRANCH}" /bin/bash -c "groupadd -og ${GROUPS} -f builders && \
		                useradd -s /bin/bash -u ${UID} -g ${GROUPS} builder && \
				su - builder -c \"$1\""
}

DISTRO_BUILD_PARAM=
GIT_BRANCH="master"
BUILD_MODEL=
DOCKER_FILE="Dockerfile"
SFL_PROJECT=".sflproject"
BUILD_CMD=
RELEASE_FILES=
MAKE_ARCHIVE=0

### main ###

# The .sflproject file allows per-project customizations
if [ -f "${SFL_PROJECT}" ]; then
	source "${SFL_PROJECT}"
fi

# Compatibility with P_BUILD_CMD or P_RELEASE_FILE
if [ -n "${P_BUILD_CMD}" ]; then
	BUILD_CMD=${P_BUILD_CMD}
fi

if [ -n "${P_RELEASE_FILES}" ]; then
	RELEASE_FILES=${P_RELEASE_FILES}
fi


while getopts "jhp:m:b:g:" OPTION
do
	case "${OPTION}" in
		h)
			usage
			exit ${ESUCCESS};;
		m)
			BUILD_MODEL="${OPTARG}";;
		p)
			DISTRO_BUILD_PARAM="${OPTARG}";;
		b)
			BUILD_CMD="${OPTARG}";;
		g)
			GIT_BRANCH="${OPTARG}";;
		j)
			MAKE_ARCHIVE=1;;
		*)
			die "Unknown parameter ${OPTION}";;

	esac
done

if [ ! -f "${DOCKER_FILE}" ]; then
	die " ${DOCKER_FILE} not found"
fi

# BUILD_CMD can be taken from Dockerfile or you can choose your own with -b
if [ -n "${BUILD_CMD}" ]; then
	docker_run "${BUILD_CMD}"
else
	if [ -z "${DISTRO_BUILD_PARAM}" ]; then
		die "build parameters not specified. Use -p to specify a build \
parameter"
	fi
	case "${BUILD_MODEL}" in
		buildroot)
			 BUILD_CMD="\
make clean \
&& make ${DISTRO_BUILD_PARAM} \
&& make"
			;;

		yocto)
			BUILD_CMD="
set -e \
&& source oe-init-build-env build-${DISTRO_BUILD_PARAM} \
&& bitbake -f ${DISTRO_BUILD_PARAM}"
			;;

		openwrt)
			BUILD_CMD="
make clean \
&& echo ${DISTRO_BUILD_PARAM} > .config \
&& make defconfig \
&& make"
			;;
		*)
			die "build model not recognized"
	esac
	docker_run "${BUILD_CMD}"
fi

if [ "${MAKE_ARCHIVE}" = "1" ]; then
# Create Release package
	if [ -z "$JOB_NAME" ]; then
		JOB_NAME="local-build"
		BUILD_ID="`date --rfc-3339='date'`"
	fi
	if [ -z "$RELEASE_FILES" ]; then
		die "No files to put in archive, check RELEASE_FILE variable \
		in $SFL_PROJECT"
	fi
	for file in $RELEASE_FILES;
	do
		[ -f $file ] || die "Cannot create release: $file missing"
	done

	RELEASE_PACKAGE=${JOB_NAME}_${BUILD_ID}.tar.xz
	XZ_OPT=-9 tar --transform "s/.*\///g" -cJf \
		$RELEASE_PACKAGE $RELEASE_FILES
fi
exit ${ESUCCESS}