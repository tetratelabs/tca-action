#!/usr/bin/env bash

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

# download the TCA file directly from github release
NAME="tca-auth_${TCA_VERSION}_${OSEXT}_${TCA_ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/tetratelabs/tca-action/releases/download/tca-auth-${TCA_VERSION}/${NAME}"

echo "Downloading ${NAME} from ${DOWNLOAD_URL}"
if curl -L -f -o "${NAME}" "${DOWNLOAD_URL}"; then
    echo "Successfully downloaded ${NAME}"
else
    echo "Failed to download ${NAME} from ${DOWNLOAD_URL}"
    echo "HTTP Status: $?"
    exit 1
fi

# extract the tar file then remove it
tar -xzf "${NAME}"
rm -f "${NAME}"

# make tca executable and copy the tca-auth binary to /usr/local/bin
chmod +x tca-auth
mv tca-auth /usr/local/bin/tca

# check if tca is installed successfully
tca analyze -h

echo "Downloading ${NAME} completed"
