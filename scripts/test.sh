#!/usr/bin/env bash

# Smoke-test the dotfiles installation inside a throwaway container.
#
# Usage: scripts/test.sh [--os <image>] [--debug]
#   --os     Container image to test against. Default: archlinux.
#   --debug  Enable DOTFILES_DEBUG for verbose output.

set -euo pipefail

os="archlinux"
debug=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --os)
    os="$2"
    shift 2
    ;;
  --os=*)
    os="${1#--os=}"
    shift
    ;;
  --debug)
    debug=true
    shift
    ;;
  *)
    echo "Unknown argument: $1" >&2
    exit 1
    ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
dotfiles_root="$(realpath "${script_dir}/..")"

# Pick a base image per OS family and the command that bootstraps the test user.
case "${os}" in
archlinux*)
  image="archlinux:latest"
  setup='
    pacman -Sy --noconfirm --needed git curl sudo
    useradd --create-home --shell /bin/bash tester
    echo "tester ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/tester
  '
  ;;
ubuntu*)
  image="ubuntu:${os#ubuntu-}"
  setup='
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git curl sudo ca-certificates
    useradd --create-home --shell /bin/bash tester
    echo "tester ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/tester
  '
  ;;
*)
  echo "Unsupported OS: ${os}" >&2
  exit 1
  ;;
esac

echo "==> Testing against ${image}"

docker run --rm --init \
  --env TERM --env COLORTERM \
  --volume "${dotfiles_root}:/dotfiles:ro" \
  "${image}" \
  bash -c "
    set -euxo pipefail
    ${setup}
    cp -r /dotfiles /home/tester/.dotfiles
    chown -R tester:tester /home/tester/.dotfiles
    cd /home/tester
    sudo -u tester env HOME=/home/tester \
      DOTFILES_TEST=true ${debug:+DOTFILES_DEBUG=true} \
      bash -c '
        export PATH=\$HOME/.local/bin:\$PATH
        if ! command -v chezmoi >/dev/null; then
          sh -c \"\$(curl -fsSL https://get.chezmoi.io)\" -- -b \$HOME/.local/bin
        fi
        chezmoi init --source \$HOME/.dotfiles --apply --force
        chezmoi data
      '
  "
