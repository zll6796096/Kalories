#!/usr/bin/env bash

set -euo pipefail

if (($# != 2)); then
  printf '%s\n' 'usage: export-app-store-screenshots.sh RESULT_BUNDLE OUTPUT_DIR'
  exit 64
fi

result_bundle="$1"
output_dir="$2"

if [[ ! -d "${result_bundle}" ]]; then
  printf 'NO-GO: result bundle does not exist: %s\n' "${result_bundle}" >&2
  exit 1
fi

if [[ "${output_dir}" == / || "${output_dir}" == . || \
  "${output_dir}" == .. || "${output_dir}" == */ ]]; then
  printf 'NO-GO: invalid screenshot output directory: %s\n' "${output_dir}" >&2
  exit 1
fi

output_parent_input="$(dirname -- "${output_dir}")"
output_name="$(basename -- "${output_dir}")"
if [[ ! -d "${output_parent_input}" ]]; then
  printf 'NO-GO: screenshot output parent is not a directory: %s\n' \
    "${output_parent_input}" >&2
  exit 1
fi
output_parent="$(cd "${output_parent_input}" && pwd -P)"
output_path="${output_parent}/${output_name}"
if [[ ! -w "${output_parent}" ]]; then
  printf 'NO-GO: screenshot output parent is not writable: %s\n' \
    "${output_parent}" >&2
  exit 1
fi

if [[ -L "${output_path}" ]]; then
  printf 'NO-GO: screenshot output directory must not be a symlink: %s\n' \
    "${output_path}" >&2
  exit 1
fi
if [[ -e "${output_path}" && ! -d "${output_path}" ]]; then
  printf 'NO-GO: screenshot output target is not a directory: %s\n' \
    "${output_path}" >&2
  exit 1
fi

if ! xcrun --find xcresulttool >/dev/null 2>&1; then
  xcode_beta_developer_dir="/Applications/Xcode-beta.app/Contents/Developer"
  if [[ ! -d "${xcode_beta_developer_dir}" ]] || \
    ! DEVELOPER_DIR="${xcode_beta_developer_dir}" \
      xcrun --find xcresulttool >/dev/null 2>&1; then
    printf '%s\n' \
      'NO-GO: xcresulttool is unavailable in the selected developer directories' >&2
    exit 1
  fi
  export DEVELOPER_DIR="${xcode_beta_developer_dir}"
fi

names=(
  app-store-01-capture
  app-store-02-summary
  app-store-03-nutrition
  app-store-04-consent
  app-store-05-uncertainty
)

is_canonical_name() {
  local candidate="$1"
  local name
  for name in "${names[@]}"; do
    if [[ "${candidate}" == "${name}.png" ]]; then
      return 0
    fi
  done
  return 1
}

validate_canonical_directory() {
  local directory="$1"
  local require_all="$2"
  local entry
  local entry_name
  local entry_count=0
  local name

  if [[ ! -r "${directory}" || ! -x "${directory}" ]]; then
    printf 'NO-GO: screenshot directory is not readable: %s\n' "${directory}" >&2
    return 1
  fi

  while IFS= read -r -d '' entry; do
    entry_name="$(basename -- "${entry}")"
    if ! is_canonical_name "${entry_name}"; then
      printf 'NO-GO: unexpected screenshot output entry: %s\n' "${entry}" >&2
      return 1
    fi
    if [[ -L "${entry}" || ! -f "${entry}" ]]; then
      printf 'NO-GO: screenshot output entry must be a regular non-symlink file: %s\n' \
        "${entry}" >&2
      return 1
    fi
    entry_count=$((entry_count + 1))
  done < <(find "${directory}" -mindepth 1 -maxdepth 1 -print0)

  if [[ "${require_all}" == true ]]; then
    if [[ "${entry_count}" != 5 ]]; then
      printf '%s\n' 'NO-GO: screenshot output count is not exactly five' >&2
      return 1
    fi
    for name in "${names[@]}"; do
      entry="${directory}/${name}.png"
      if [[ -L "${entry}" || ! -f "${entry}" ]]; then
        printf 'NO-GO: canonical screenshot is missing or unsafe: %s\n' \
          "${entry}" >&2
        return 1
      fi
    done
  fi
}

if [[ -d "${output_path}" ]]; then
  validate_canonical_directory "${output_path}" false
fi

export_tmp=""
stage_dir=""
backup_path=""
preserve_backup=false

remove_temp_tree() {
  local temp_path="$1"
  if [[ -z "${temp_path}" ]]; then
    return 0
  fi
  if [[ "${temp_path}" == / || \
    "$(dirname -- "${temp_path}")" != "${output_parent}" ]]; then
    printf 'NO-GO: refused unsafe temporary cleanup path: %s\n' "${temp_path}" >&2
    return 1
  fi
  if [[ -e "${temp_path}" || -L "${temp_path}" ]]; then
    find "${temp_path}" -depth -delete
  fi
}

cleanup_export() {
  local cleanup_status=0
  remove_temp_tree "${export_tmp}" || cleanup_status=$?
  remove_temp_tree "${stage_dir}" || cleanup_status=$?
  if [[ "${preserve_backup}" != true ]]; then
    remove_temp_tree "${backup_path}" || cleanup_status=$?
  fi
  return "${cleanup_status}"
}
trap cleanup_export EXIT

export_tmp="$(mktemp -d "${output_parent}/.${output_name}.export.XXXXXX")"
stage_dir="$(mktemp -d "${output_parent}/.${output_name}.stage.XXXXXX")"

xcrun xcresulttool export attachments \
  --path "${result_bundle}" \
  --output-path "${export_tmp}"

manifest_path="${export_tmp}/manifest.json"
if [[ ! -f "${manifest_path}" || -L "${manifest_path}" ]]; then
  printf '%s\n' 'NO-GO: exported attachment manifest is missing or unsafe' >&2
  exit 1
fi
if ! jq -e '
  type == "array"
  and all(.[];
    type == "object"
    and (.attachments | type) == "array"
    and all(.attachments[];
      type == "object"
      and (.suggestedHumanReadableName | type) == "string"
      and (.exportedFileName | type) == "string"
    )
  )
' "${manifest_path}" >/dev/null 2>&1; then
  printf '%s\n' 'NO-GO: exported attachment manifest schema is invalid' >&2
  exit 1
fi

for name in "${names[@]}"; do
  match_count="$(jq -r --arg name "${name}" '
    [.[].attachments[]
      | select(
          (.suggestedHumanReadableName == $name)
          or (.suggestedHumanReadableName | startswith($name + "_"))
        )]
    | length
  ' "${manifest_path}")"
  if [[ "${match_count}" != 1 ]]; then
    printf 'NO-GO: %s matched %s attachments; expected exactly one\n' \
      "${name}" "${match_count}" >&2
    exit 1
  fi

  exported_name="$(jq -er --arg name "${name}" '
    [.[].attachments[]
      | select(
          (.suggestedHumanReadableName == $name)
          or (.suggestedHumanReadableName | startswith($name + "_"))
        )][0].exportedFileName
  ' "${manifest_path}")"
  if [[ "${exported_name}" == */* || "${exported_name}" != *.png ]]; then
    printf 'NO-GO: unsafe or non-PNG exported name for %s: %s\n' \
      "${name}" "${exported_name}" >&2
    exit 1
  fi

  source_path="${export_tmp}/${exported_name}"
  staged_path="${stage_dir}/${name}.png"
  if [[ -L "${source_path}" || ! -f "${source_path}" ]]; then
    printf 'NO-GO: exported attachment is missing or unsafe for %s\n' \
      "${name}" >&2
    exit 1
  fi
  cp "${source_path}" "${staged_path}"

  if ! image_info="$(sips -g format -g pixelWidth -g pixelHeight -g hasAlpha \
    "${staged_path}" 2>/dev/null)"; then
    printf 'NO-GO: %s is not a readable PNG screenshot\n' "${name}" >&2
    exit 1
  fi
  format="$(awk '/format:/ {print $2}' <<<"${image_info}")"
  width="$(awk '/pixelWidth:/ {print $2}' <<<"${image_info}")"
  height="$(awk '/pixelHeight:/ {print $2}' <<<"${image_info}")"
  alpha="$(awk '/hasAlpha:/ {print $2}' <<<"${image_info}")"
  if [[ "${format}" != png || "${width}" != 1320 || \
    "${height}" != 2868 || "${alpha}" != no ]]; then
    printf 'NO-GO: %s is not an opaque 1320x2868 PNG\n' "${name}" >&2
    exit 1
  fi
done

validate_canonical_directory "${stage_dir}" true
chmod 755 "${stage_dir}"

if [[ -d "${output_path}" ]]; then
  backup_path="$(mktemp -d "${output_parent}/.${output_name}.backup.XXXXXX")"
  rmdir "${backup_path}"
  if ! mv -h "${output_path}" "${backup_path}"; then
    printf '%s\n' 'NO-GO: could not create recoverable screenshot backup' >&2
    exit 1
  fi
  preserve_backup=true
fi

if [[ -e "${output_path}" || -L "${output_path}" ]]; then
  printf '%s\n' 'NO-GO: screenshot output target changed during promotion' >&2
  if [[ -n "${backup_path}" ]]; then
    if ! mv -h "${backup_path}" "${output_path}"; then
      printf 'NO-GO: backup restore failed; preserved backup at %s\n' \
        "${backup_path}" >&2
    else
      preserve_backup=false
    fi
  fi
  exit 1
fi

if ! mv -h "${stage_dir}" "${output_path}"; then
  printf '%s\n' 'NO-GO: screenshot directory promotion failed' >&2
  if [[ -n "${backup_path}" ]]; then
    if ! mv -h "${backup_path}" "${output_path}"; then
      printf 'NO-GO: backup restore failed; preserved backup at %s\n' \
        "${backup_path}" >&2
    else
      preserve_backup=false
    fi
  fi
  exit 1
fi
stage_dir=""

if [[ -n "${backup_path}" ]]; then
  remove_temp_tree "${backup_path}"
  backup_path=""
  preserve_backup=false
fi

printf '%s\n' 'PASS: five opaque 6.9-inch App Store screenshots exported'
