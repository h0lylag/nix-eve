#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_file="$repo_root/pkgs/eve-online/package.nix"

installer_base_url=https://launcher.ccpgames.com/eve-online/release/win32/x64
download_dir=${EVE_UPDATE_DOWNLOAD_DIR:-/tmp}
curl_retries=${EVE_UPDATE_RETRIES:-3}
curl_connect_timeout=${EVE_UPDATE_CONNECT_TIMEOUT:-20}

usage() {
  printf 'Usage: %s [download-directory]\n\n' "$0"
  printf '%s\n' \
    'Environment:' \
    '  EVE_UPDATE_DOWNLOAD_DIR      Installer destination (default: /tmp)' \
    '  EVE_UPDATE_RETRIES           Curl retries (default: 3)' \
    '  EVE_UPDATE_CONNECT_TIMEOUT   Curl connection timeout in seconds (default: 20)'
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

latest_version() {
  local manifest line version=''
  manifest=$(curl "${curl_options[@]}" "$installer_base_url/RELEASES") \
    || fail 'Could not download the launcher RELEASES manifest.'

  # Each RELEASES line lists a package hash, filename, and size. The last
  # full package filename supplies the version for the Setup.exe URL.
  while IFS= read -r line; do
    if [[ $line =~ ^[[:xdigit:]]{40}[[:space:]]+eve-online-([0-9]+[.][0-9]+[.][0-9]+)-full[.]nupkg[[:space:]]+[0-9]+$ ]]; then
      version=${BASH_REMATCH[1]}
    fi
  done <<< "$manifest"
  [[ -n $version ]] || fail 'Could not find a full launcher package in RELEASES.'

  printf '%s\n' "$version"
}

update_package() {
  local version=$1 hash=$2
  local version_line='^  version = "[0-9]+\.[0-9]+\.[0-9]+";$'
  local hash_line='^    hash = "sha256-[A-Za-z0-9+/=]+";$'

  if [[ $(grep -Ec "$version_line" "$package_file") -ne 1 \
    || $(grep -Ec "$hash_line" "$package_file") -ne 1 ]]; then
    fail "Expected one version and one installer hash in $package_file"
  fi

  sed -i -E \
    -e "s|$version_line|  version = \"$version\";|" \
    -e "s|$hash_line|    hash = \"$hash\";|" \
    "$package_file"
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi
if (( $# > 1 )); then
  usage >&2
  exit 2
fi

[[ $curl_retries =~ ^[0-9]+$ ]] || fail 'EVE_UPDATE_RETRIES must be a nonnegative integer.'
[[ $curl_connect_timeout =~ ^[1-9][0-9]*$ ]] || fail 'EVE_UPDATE_CONNECT_TIMEOUT must be a positive integer.'

for tool in curl nix; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing required command: $tool"
done

curl_options=(
  --fail --location --silent --show-error
  --proto '=https' --proto-redir '=https'
  --retry "$curl_retries"
  --connect-timeout "$curl_connect_timeout"
)

# The hash must correspond to the URL template that Nix will fetch.
package_url_line="    url = \"$installer_base_url/eve-online-\${version}+Setup.exe\";"
grep -Fxq "$package_url_line" "$package_file" \
  || fail "Installer URL in $package_file differs from this updater."

download_dir=${1:-$download_dir}
mkdir -p -- "$download_dir"
download_dir=$(cd -- "$download_dir" && pwd)

version=$(latest_version)
installer_name="eve-online-$version+Setup.exe"
installer_url="$installer_base_url/$installer_name"
installer_file="$download_dir/$installer_name"
temp_installer=$(mktemp "$download_dir/.eve-online-setup.XXXXXX")
trap 'rm -f -- "$temp_installer"' EXIT

curl "${curl_options[@]}" --output "$temp_installer" "$installer_url"
# The manifest hash covers the .nupkg, so hash the downloaded Setup.exe for Nix.
hash=$(nix hash file --type sha256 --sri "$temp_installer")
mv -f -- "$temp_installer" "$installer_file"
update_package "$version" "$hash"

printf 'Downloaded: %s\n' "$installer_file"
printf 'URL: %s\n' "$installer_url"
printf 'Version: %s\nHash: %s\n' "$version" "$hash"
printf 'Updated: %s\n' "$package_file"
