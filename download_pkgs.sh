#!/bin/bash

## Copyright (C) 2014 Red Hat, Inc., Kiril Nesenko <knesenko@redhat.com>
### This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.

## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
## GNU General Public License for more details.

## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

SCRIPTDIR="$(dirname "${0}")"
REPO_PATH="/var/www/html/pub"

die() {
	local m="${1}"
	echo "FATAL: ${m}"
	exit 1
}

usage() {
	cat << __EOF__
    ${0} [options]
    --conf-file=               - configuration file
    --output-directory=        - tmp directory where to download pkgs
    --destination-repository   - destination repository

    CONF_FILE
    The configuration file must be a plain text file with one package
    or url on each line.

    URL DEFINITION
    The url must be a canonical http/https url that must contain
    the links to the packages (not the link to the package directly).
    In the case of koji, the url can be a the first level task
    that links to to the tasks that created the packages (for example
    http://koji.fedoraproject.org/koji/taskinfo?taskID=6397141).


    PACKAGE DEFINITON
    The package definition is a reference to an already existing
    package on previous repository, from the ones under $REPO_PATH
    For example:

    3.3:ovirt-engine-3.3.0-1

    that will get all the packages that have ovirt-engine-3.3.0-1
    on their name from $REPO_PATH/3.3 and add them to the new repo.


    CONFIGURATION EXAMPLE
    http://jenkins.ovirt.org/job/manual-build-tarball/130/
    http://jenkins.ovirt.org/job/manual-build-tarball/130/
    http://koji.fedoraproject.org/koji/taskinfo?taskID=6279142
    3.3:ovirt-engine-3.3.0-1
__EOF__
}

get_opts() {
	while [ -n "${1}" ]; do
		opt="${1}"
		v="${opt#*=}"
		shift
		case "${opt}" in
			--conf-file=*)
				CONF_FILE="${v}"
				;;
			--output-directory=*)
				OUTPUT_DIR="${v}"
				;;
			--destination-repository=*)
				DST_REPO="${v}"
				;;
			--help|-h)
				usage
				exit 0
				;;
			*)
				die "Wrong option"
				;;
		esac
	done
}

validation() {
	[ -n "${CONF_FILE}" ] || die "Please specify --conf-file= option"
	[ -f "${CONF_FILE}" ] || die "Cannot find configuration file"
	[ -n "${OUTPUT_DIR}" ] || die "Please specify --output-directory= option"
	[ "${OUTPUT_DIR}" != "/" ] || die "--output-directory= can not be /"
	[ -n "${DST_REPO}" ] || die "Please specify --destination-repository= option"
	[ -e "${OUTPUT_DIR}" ] && die "${OUTPUT_DIR} should not exist"
	[ -e "${OUTPUT_DIR}" ] || mkdir -p "${OUTPUT_DIR}"
}

get_packages_from_koji_2lvl() {
	local url="${1?}"
	local builds=($(wget -q -O - "${url}" \
                    | grep -Po '(?<=href=")[^"]+(?=.*(buildArch|buildSRPM))' \
                    | sort | uniq))
	local path_url="${url#*//*/koji/}"
	local base_url="${url:0:$((${#url}-${#path_url}))}"
	for build in "${builds[@]}"; do
		for package in $(wget -q -O - "${base_url}${build}" \
							| grep -Po '(?<=href=")[^"]+\.(iso|rpm|tar.gz)' \
							| sort | uniq); do
			echo "${package}"
		done
	done
	exit
}

download_package() {
	local url="${1?}"
	local dst_dir="${2?}"
	local failed=false
	local packages package labels
	echo
	echo "Downloading packages from ${url} to ${dst_dir}"

	pushd "${dst_dir}" >& /dev/null

	#
	# Handle jenkins builds with configuration (labels)
	#

	packages=($(wget -q -O - "${url}" | grep -Po '(?<=href=")[^"]+\.(iso|rpm|tar.gz)' | sort | uniq))

	#
	# Handle koji 2level pages
	#
	if [ "${#packages[@]}" -eq 0 ] \
		&& [[ "${url}" =~ ^.*koji.*$ ]]; then
		packages=($(get_packages_from_koji_2lvl "${url}"))
	fi

	for package in "${packages[@]}"; do
		## handle relative links
		[[ "${package}" =~ ^http.*$ ]] \
			|| package="$url/$package"
		wget -qnc "${package}" || die "Cannot download pkgs ${package}"
		echo "Got package ${package}"
	done

	popd >& /dev/null
}

download_pkgs() {
	cat "${CONF_FILE}" | while read url; do
		if [[ "${url}" =~ ^http ]]; then
			download_package "${url}" "${OUTPUT_DIR}"
		else
			link_pkg "${url}" "${OUTPUT_DIR}"
		fi
	done
}

publish_artifacts() {
	local src_dir="${1}"
	local dst_dir="${2}"
	"${SCRIPTDIR}/publish_artifacts.sh" \
		--source-repository="${src_dir}" \
		--destination-repository="${dst_dir}"
}

clean() {
	rm -rf "${OUTPUT_DIR}"
}

main() {
	get_opts "${@}"
	validation

	download_pkgs
	publish_artifacts "${OUTPUT_DIR}" "${DST_REPO}"

	clean
}

main "${@}"
