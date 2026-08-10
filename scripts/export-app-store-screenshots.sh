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

if [[ -d "${output_dir}" ]]; then
  while IFS= read -r existing_png; do
    existing_base="$(basename "${existing_png}" .png)"
    is_expected=false
    for name in "${names[@]}"; do
      if [[ "${existing_base}" == "${name}" ]]; then
        is_expected=true
        break
      fi
    done
    if [[ "${is_expected}" != true ]]; then
      printf 'NO-GO: unexpected stale screenshot: %s\n' "${existing_png}" >&2
      exit 1
    fi
  done < <(find "${output_dir}" -maxdepth 1 -type f -name '*.png' -print)
fi

export_tmp="$(mktemp -d)"
cleanup_export() {
  find "${export_tmp}" -depth -delete
}
trap cleanup_export EXIT

xcrun xcresulttool export attachments \
  --path "${result_bundle}" \
  --output-path "${export_tmp}"

manifest_path="${export_tmp}/manifest.json"
if [[ ! -f "${manifest_path}" ]] || ! jq -e 'type == "array"' "${manifest_path}" >/dev/null; then
  printf '%s\n' 'NO-GO: exported attachment manifest is missing or invalid' >&2
  exit 1
fi

validated_dir="${export_tmp}/validated"
mkdir "${validated_dir}"

for name in "${names[@]}"; do
  match_count="$(jq -r --arg name "${name}" '
    [.[].attachments[]?
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
    [.[].attachments[]?
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
  validated_path="${validated_dir}/${name}.png"
  if [[ ! -f "${source_path}" ]]; then
    printf 'NO-GO: exported attachment is missing for %s\n' "${name}" >&2
    exit 1
  fi
  cp "${source_path}" "${validated_path}"

  image_info="$(sips -g format -g pixelWidth -g pixelHeight -g hasAlpha \
    "${validated_path}")"
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

mkdir -p "${output_dir}"
for name in "${names[@]}"; do
  cp "${validated_dir}/${name}.png" "${output_dir}/${name}.png"
done

output_count="$(find "${output_dir}" -maxdepth 1 -type f -name '*.png' \
  | wc -l | tr -d ' ')"
if [[ "${output_count}" != 5 ]]; then
  printf '%s\n' 'NO-GO: screenshot output count is not exactly five' >&2
  exit 1
fi

for name in "${names[@]}"; do
  if [[ ! -f "${output_dir}/${name}.png" ]]; then
    printf 'NO-GO: canonical screenshot is missing after export: %s\n' \
      "${name}" >&2
    exit 1
  fi
done

printf '%s\n' 'PASS: five opaque 6.9-inch App Store screenshots exported'
