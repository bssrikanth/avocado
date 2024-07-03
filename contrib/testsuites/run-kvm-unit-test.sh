#!/bin/sh
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; specifically version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# See LICENSE for more details.
#
# Copyright: 2016 Red Hat, Inc.
# Author: Lukas Doktor <ldoktor@redhat.com>

#
# This script runs kvm-unit-tests as individual tests inside avocado.
# Optionally it downloads the kvm-unit-tests from git.
#

# Parse arguments
WILDCARD="*"
UEFI_TEST=""
UEFI_ENV=""
while [ true ]; do
    case $1 in
        "--endian")
            shift
            ENDIAN="--endian=$1"
            ;;
        "--configure-args")
            shift
            CONFIGURE_ARGS=$1
            ;;
        "--repository")
            shift
            REPOSITORY=$1
            ;;
        "--branch")
            shift
            BRANCH=$1
            ;;
        "--path")
            shift
            KVM_UNIT_TEST=$1
            ;;
	"--uefi-test")
	    shift
	    UEFI_TEST=$1
	    ;;
        "--uefi-env")
            shift
            UEFI_ENV="$1=y"
            ;;
        "--wildcard")
            shift
            WILDCARD="$1"
            ;;
        "-h"|"--help")
            echo "Usage: $0 [-h] [--endian ENDIAN] [--configure-args KVM_UNIT_TEST_CONFIGURE_ARGS] [--branch KVM_UNIT_TEST_BRANCH] [--path PATH] [--wildcard WILDCARD] [avocado arguments ...]"
            echo
            echo "  -h                  Show this help"
            echo "  --endian            Endian flag to kvm-unit-test configure"
            echo "  --configure-args    Arguments given to configure kvm-unit-tests"
            echo "  --repository        Repository for fetching kvm-unit-tests (default is https://gitlab.com/kvm-unit-tests/kvm-unit-tests.git)"
            echo "  --branch            Branch/tag of kvm-unit-tests to clone (default is master)"
            echo "  --path              Path to kvm-unit-test suite (default is tmp)"
            echo "  --wildcard          BASH Wildcard to select tests (by default all),only applies for non-uefi tests"
            echo "  --uefi-test		Testcase to run with UEFI"
            echo "  --uefi-env		Environment to run testcases with UEFI"
            echo
            echo "Note: You might need to set ACCEL and/or QEMU env variables."
            exit 1
            ;;
        *)
            break
    esac
    shift
done

CONF_FILE=~/.config/avocado/avocado.conf
restore_config()
{
	rm $CONF_FILE 2>/dev/null
	mv "$CONF_FILE".kvm-unit-tests "$CONF_FILE" 2>/dev/null
}

setup_skip_exitcode()
{
	mkdir -p $(dirname $CONF_FILE)
	[ -f $CONF_FILE ] && cp "$CONF_FILE" "$CONF_FILE".kvm-unit-tests
	trap restore_config EXIT

	echo "[runner.exectest.exitcodes]" >>$CONF_FILE
	echo "skip = [2, 77]" >>$CONF_FILE
}

# Initialize directory and download kvm-unit-test if necessary
[ "$KVM_UNIT_TEST" ] || { KVM_UNIT_TEST="$(mktemp -d)"; CLEAN_DIR=true; }
[ -n "$BRANCH" ] || BRANCH="master"
[ -n "$REPOSITORY" ] || REPOSITORY="https://gitlab.com/kvm-unit-tests/kvm-unit-tests.git"
[ -d "$KVM_UNIT_TEST" ] || mkdir -p "$KVM_UNIT_TEST"
cd "$KVM_UNIT_TEST"
[ -f "configure" ] || git clone --depth 1 -b $BRANCH -q $REPOSITORY . || exit

# Compile kvm-unit-test as standalone to get tests as separate files
./configure $ENDIAN $CONFIGURE_ARGS || { echo Fail to configure kvm-unit-test; exit -1; }
make standalone >/dev/null || { echo Fail to "make standalone" kvm-unit-test; exit -1; }

setup_skip_exitcode

if [ -n "$UEFI_TEST" ]
then
	echo "#!/usr/bin/env bash
$UEFI_ENV ./x86/efi/run ./x86/$UEFI_TEST" > ./$UEFI_TEST
        chmod 755 ./$UEFI_TEST
        eval "avocado run ./$UEFI_TEST"
        RET=$?
else
        cd tests
        eval "avocado run ./$WILDCARD $*"
        RET=$?
fi

# Cleanup and exit
[ "$CLEAN_DIR" ] && rm -Rf "$KVM_UNIT_TEST"
exit $RET
