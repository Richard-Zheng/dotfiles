#!/usr/bin/env bash

# Render-test every checked-in hosts/*.toml profile for both the user (`home/`)
# and root (`root/`) chezmoi sources without modifying the current machine.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
repo_root="$(realpath "${script_dir}/..")"

if ! command -v chezmoi >/dev/null 2>&1; then
  echo "chezmoi is required to run check-hosts.sh" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

for host_file in "${repo_root}"/hosts/*.toml; do
  host="$(basename "${host_file}" .toml)"
  echo "==> Checking host profile: ${host}"

  host_tmp="${tmpdir}/${host}"
  mkdir -p "${host_tmp}/home" "${host_tmp}/root"

  home_cfg="${host_tmp}/home/chezmoi.toml"
  home_state="${host_tmp}/home/state.boltdb"
  home_cache="${host_tmp}/home/cache"
  root_cfg="${host_tmp}/root/chezmoi.toml"
  root_state="${host_tmp}/root/state.boltdb"
  root_cache="${host_tmp}/root/cache"

  # 1. Generate ~/.config/chezmoi/chezmoi.toml via home/.chezmoi.toml.tmpl.
  CHEZMOI_HOST="${host}" chezmoi init \
    --source "${repo_root}" \
    --config "${home_cfg}" \
    --persistent-state "${home_state}" \
    --cache "${home_cache}" \
    --config-format toml \
    --force >/dev/null

  # 2. Verify home/ data & managed file list (excluding encrypted files so no age key is required).
  home_managed="${host_tmp}/home/managed.txt"
  chezmoi \
    --source "${repo_root}" \
    --config "${home_cfg}" \
    --persistent-state "${home_state}" \
    --cache "${home_cache}" \
    managed --exclude=encrypted >"${home_managed}"

  # Render every non-encrypted home/ template file and check scripts syntax.
  while IFS= read -r target; do
    src="$(chezmoi \
      --source "${repo_root}" \
      --config "${home_cfg}" \
      --persistent-state "${home_state}" \
      --cache "${home_cache}" \
      source-path "${HOME}/${target}" 2>/dev/null || true)"
    [[ "${src}" == *.tmpl ]] || continue
    out="${host_tmp}/home/rendered.out"
    chezmoi \
      --source "${repo_root}" \
      --config "${home_cfg}" \
      --persistent-state "${home_state}" \
      --cache "${home_cache}" \
      cat "${HOME}/${target}" >"${out}"
    if head -n 1 "${out}" | grep -q 'bash'; then
      bash -n "${out}"
    elif head -n 1 "${out}" | grep -q '/bin/sh'; then
      sh -n "${out}"
    fi
  done <"${home_managed}"

  # Render every non-ignored home/ script template and syntax-check it.
  while IFS= read -r script_rel; do
    out="${host_tmp}/home/script.sh"
    chezmoi \
      --source "${repo_root}" \
      --config "${home_cfg}" \
      --persistent-state "${home_state}" \
      --cache "${home_cache}" \
      cat "${HOME}/${script_rel}" >"${out}"
    bash -n "${out}"
  done < <(
    chezmoi \
      --source "${repo_root}" \
      --config "${home_cfg}" \
      --persistent-state "${home_state}" \
      --cache "${home_cache}" \
      managed --include=scripts --exclude=files,dirs,symlinks,encrypted
  )

  # 3. Render rootmoi config and test root/ templates & scripts.
  chezmoi \
    --source "${repo_root}" \
    --config "${home_cfg}" \
    --persistent-state "${home_state}" \
    --cache "${home_cache}" \
    cat "${HOME}/.config/rootmoi/chezmoi.toml" >"${root_cfg}"

  root_managed="${host_tmp}/root/managed.txt"
  chezmoi \
    --config "${root_cfg}" \
    --persistent-state "${root_state}" \
    --cache "${root_cache}" \
    managed --exclude=encrypted >"${root_managed}"

  while IFS= read -r target; do
    src="$(chezmoi \
      --config "${root_cfg}" \
      --persistent-state "${root_state}" \
      --cache "${root_cache}" \
      source-path "/${target}" 2>/dev/null || true)"
    [[ "${src}" == *.tmpl ]] || continue
    out="${host_tmp}/root/rendered.out"
    chezmoi \
      --config "${root_cfg}" \
      --persistent-state "${root_state}" \
      --cache "${root_cache}" \
      cat "/${target}" >"${out}"
    if [[ "${target}" == etc/default/grub.d/* ]]; then
      sh -n "${out}"
    fi
  done <"${root_managed}"

  while IFS= read -r script_rel; do
    out="${host_tmp}/root/script.sh"
    chezmoi \
      --config "${root_cfg}" \
      --persistent-state "${root_state}" \
      --cache "${root_cache}" \
      cat "/${script_rel}" >"${out}"
    bash -n "${out}"
  done < <(
    chezmoi \
      --config "${root_cfg}" \
      --persistent-state "${root_state}" \
      --cache "${root_cache}" \
      managed --include=scripts --exclude=files,dirs,symlinks,encrypted
  )

  # 4. Sanity assertions per host class.
  case "${host}" in
    zzzlab|default)
      if grep -qE '^(\.config/i3/|\.config/ghostty/|\.config/fcitx5/|\.codex/|\.pi/)' "${home_managed}"; then
        echo "FAIL: headless host ${host} unexpectedly manages GUI/AI home files" >&2
        exit 1
      fi
      if grep -qE '^(etc/keyd|etc/environment|etc/btrbk|etc/greetd|etc/pam\.d/greetd|etc/default/grub\.d|etc/pacman\.d/mirrorlist|etc/systemd/timesyncd\.conf\.d)' "${root_managed}"; then
        echo "FAIL: headless host ${host} unexpectedly manages desktop/arch/btrbk root files" >&2
        exit 1
      fi
      ;;
    thinkarch)
      grep -qx 'etc/greetd/config.toml' "${root_managed}" || { echo "FAIL: thinkarch missing greetd config" >&2; exit 1; }
      grep -qx 'etc/btrbk/btrbk.conf' "${root_managed}" || { echo "FAIL: thinkarch missing btrbk config" >&2; exit 1; }
      grep -qx 'etc/udev/rules.d/90-backlight-permissions.rules' "${root_managed}" || { echo "FAIL: thinkarch missing backlight rule" >&2; exit 1; }
      ;;
    vccarch)
      grep -qx '.config/i3/conf.d/monitors.conf' "${home_managed}" || { echo "FAIL: vccarch missing monitors.conf" >&2; exit 1; }
      grep -qx '.config/i3/monitor.sh' "${home_managed}" || { echo "FAIL: vccarch missing monitor.sh" >&2; exit 1; }
      grep -qx 'etc/greetd/config.toml' "${root_managed}" || { echo "FAIL: vccarch missing greetd config" >&2; exit 1; }
      if grep -qx '.config/i3blocks/battery/battery' "${home_managed}"; then
        echo "FAIL: vccarch desktop should not deploy battery block" >&2
        exit 1
      fi
      ;;
  esac

  echo "   OK (home targets: $(wc -l <"${home_managed}"), root targets: $(wc -l <"${root_managed}"))"
done

echo "✅ All host profiles rendered and passed checks."
