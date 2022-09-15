#!/bin/bash

set -ex

JAVA_VERSION=8
JDK="jdk"
JRE="jre"
OPENJ9="openj9"
OPENJ9_OPENJDK="${OPENJ9}-openjdk"
JDK_FLAVOR="${OPENJ9_OPENJDK}-${JDK}${JAVA_VERSION}"
JRE_FLAVOR="${OPENJ9_OPENJDK}-${JRE}${JAVA_VERSION}"
INSTRUCTION_SET="x86_64"

OS_TYPE="linux"
# cmake correct paths for
TOP_DIR=${HOME}
# https://raw.githubusercontent.com/archlinux/svntogit-packages/packages/java8-openjdk/trunk/PKGBUILD
# Avoid optimization of HotSpot being lowered from O3 to O2
_CFLAGS="-O3 -pipe"
if [[ "${OSTYPE}" == "cygwin" || "${OSTYPE}" == "msys" ]]; then
  OS_TYPE="windows"
  TOP_DIR="/cygdrive/c"
  export JAVA_HOME=${TOP_DIR}/dev/tools/openjdk${JAVA_VERSION}
  _CFLAGS="/O2"
fi
JDK_DIR="${TOP_DIR}/${JDK_FLAVOR}"
OS_TYPE_AND_INSTRUCTION_SET="${OS_TYPE}-${INSTRUCTION_SET}"

BRANCH_TO_BUILD="v0.33.1-release"
#BRANCH_TO_BUILD="main"

git config --global user.email "anatoly.a.shipov@gmail.com"
git config --global user.name "Anatoly Shipov"

if [ ! -d "${JDK_DIR}/.git" ]; then
  cd ${TOP_DIR}
  git clone https://github.com/ibmruntimes/${JDK_FLAVOR}.git
  cd ${JDK_DIR}
  git checkout ${BRANCH_TO_BUILD}
else
  cd ${JDK_DIR}
  git checkout master
  git pull
  git checkout ${BRANCH_TO_BUILD}
  git pull
fi

rm -rf ${JDK_DIR}/omr/ ${JDK_DIR}/openj9/

export CFLAGS=${_CFLAGS}
export CXXFLAGS=${_CFLAGS}

bash get_source.sh -openj9-branch=${BRANCH_TO_BUILD} -omr-branch=${BRANCH_TO_BUILD}

VERSION_STRING=$(awk -F" := " '{print $2}' ${JDK_DIR}/closed/openjdk-tag.gmk)

MINOR_VER=$(printf ${VERSION_STRING} | cut -d'-' -f 1)
MINOR_VER=${MINOR_VER#${JDK}${JAVA_VERSION}u}

UPDATE_VER=$(printf ${VERSION_STRING} | cut -d'-' -f 2)
UPDATE_VER=${UPDATE_VER#"b"}

bash configure \
  --verbose \
  --with-debug-level=release \
  --with-native-debug-symbols=none \
  --with-jvm-variants=server \
  --with-milestone="fcs" \
  --enable-unlimited-crypto \
  --with-extra-cflags="${_CFLAGS}" \
  --with-extra-cxxflags="${_CFLAGS}" \
  --enable-jfr=yes \
  --with-update-version="${MINOR_VER}" \
  --with-build-number="${UPDATE_VER}" \
#  --with-freetype-src=${TOP_DIR}/dev/VCS/freetype-2.5.3 \
#  --with-toolchain-type=clang

make clean
make all

if [[ $? -eq 0 ]]; then
  cd ${JDK_DIR}/build/${OS_TYPE_AND_INSTRUCTION_SET}-normal-server-release/images/
  find "${PWD}" -type f -name '*.debuginfo' -exec rm {} \;
  find "${PWD}" -type f -name '*.diz' -exec rm {} \;
  GZIP=-9 tar -czhf ./${JDK_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${VERSION_STRING}-${BRANCH_TO_BUILD}.tar.gz j2sdk-image/
  GZIP=-9 tar -czhf ./${JRE_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${VERSION_STRING}-${BRANCH_TO_BUILD}.tar.gz j2re-image/
fi
