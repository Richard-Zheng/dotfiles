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

# Per-OS bootstrap: install the minimal tools chezmoi needs and create a
# passwordless-sudo test user. The encrypted files are skipped because CI has no
# age key.
case "${os}" in
archlinux*)
  image="archlinux:latest"
  bootstrap='
    pacman-key --init
    pacman-key --populate archlinux
    pacman -Sy --noconfirm --needed git curl sudo
  '
  ;;
ubuntu*)
  image="ubuntu:${os#ubuntu-}"
  bootstrap='
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends git curl ca-certificates sudo
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
    ${bootstrap}
    useradd --create-home --shell /bin/bash tester
    echo 'tester ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/tester
    cp -r /dotfiles /home/tester/.dotfiles
    chown -R tester:tester /home/tester/.dotfiles

    sudo -u tester env HOME=/home/tester PATH=/home/tester/.local/bin:/usr/local/bin:/usr/bin:/bin bash -c '
      set -euxo pipefail
      cd \$HOME
      if ! command -v chezmoi >/dev/null; then
        sh -c \"\$(curl -fsSL https://get.chezmoi.io)\" -- -b \$HOME/.local/bin
      fi
      export PATH=\$HOME/.local/bin:\$PATH
      ${debug:+export DOTFILES_DEBUG=true}
      chezmoi init --source \$HOME/.dotfiles --apply --force --exclude=encrypted
      chezmoi data
    '
  "
