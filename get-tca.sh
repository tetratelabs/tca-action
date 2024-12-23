#!/usr/bin/env bash

# download the TCA file from github relase page, e.g. https://github.com/tetratelabs/tca-action/releases/download/latest/tca-auth_latest_linux_amd64.tar.gz
# extract the tar file
# copy the tca-auth binary to /usr/local/bin
# make it executable
# remove the tar file

set -e

TCA_VERSION=${TCA_VERSION:-latest}
# Determines the operating system.
OS="${TARGET_OS:-$(uname)}"
if [ "${OS}" = "Darwin" ] ; then
  OSEXT="darwin"
elif [ "${OS}" = "Linux" ] ; then
  OSEXT="linux"
else
  echo "This system's OS, ${OS}, isn't supported"
  exit 1;
fi

LOCAL_ARCH=$(uname -m)
if [ "${TARGET_ARCH}" ]; then
    LOCAL_ARCH=${TARGET_ARCH}
fi

case "${LOCAL_ARCH}" in
  x86_64|amd64)
    TCA_ARCH=amd64
    ;;
  armv8*|aarch64*|arm64)
    TCA_ARCH=arm64
    ;;
  *)
    echo "This system's architecture, ${LOCAL_ARCH}, isn't supported"
    exit 1
    ;;
esac

if [ "${TCA_VERSION}" = "" ] ; then
  printf "Unable to get latest TCA version."
  exit 1;
fi

NAME="tca-auth_${TCA_VERSION}_${OSEXT}_${TCA_ARCH}.tar.gz"
URL="https://github.com/tetratelabs/tca-action/releases/download/${TCA_VERSION}/${NAME}"
echo "Downloading ${URL}"

curl -fsLO "${URL}"
tar -xzf "${NAME}"
rm -f "${NAME}"
chmod +x tca-auth
mv tca-auth /usr/local/bin/tca-auth

echo "Downloading ${NAME} completed"
