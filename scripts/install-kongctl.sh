#!/usr/bin/env bash
set -euo pipefail

version="1.16.0"
archive="kongctl_linux_amd64.zip"
checksum="197e453dc9b5c15b6af73762cb5c44d1958ed17fd1dbea3eb61adf1f0e54ab99"
install_dir="${RUNNER_TEMP:?RUNNER_TEMP is required}/kongctl-bin"
mkdir -p "${install_dir}"
curl --fail --location --silent --show-error --retry 3 \
  "https://github.com/Kong/kongctl/releases/download/v${version}/${archive}" \
  --output "${RUNNER_TEMP}/${archive}"
printf '%s  %s\n' "${checksum}" "${RUNNER_TEMP}/${archive}" | sha256sum --check -
unzip -q "${RUNNER_TEMP}/${archive}" -d "${install_dir}"
chmod 755 "${install_dir}/kongctl"
printf '%s\n' "${install_dir}" >> "${GITHUB_PATH:?GITHUB_PATH is required}"
"${install_dir}/kongctl" version --full
