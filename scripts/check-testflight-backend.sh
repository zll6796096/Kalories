#!/usr/bin/env bash

set -euo pipefail

umask 077

readonly PROJECT_ID="zhang23-23"
readonly REGION_ID="asia-northeast1"
readonly SERVICE_ID="kalories"
readonly EXPECTED_MODEL="gemini-3.6-flash"
readonly EXPECTED_SECRET_ID="kalories-gemini-api-key"

preflight_tmp="$(mktemp -d)"
service_json="${preflight_tmp}/service.json"
logs_json="${preflight_tmp}/logs.json"

cleanup() {
  local exit_status=$?

  trap - EXIT
  if [[ -f "${service_json}" ]]; then
    unlink -- "${service_json}" || true
  fi
  if [[ -f "${logs_json}" ]]; then
    unlink -- "${logs_json}" || true
  fi
  if [[ -d "${preflight_tmp}" ]]; then
    rmdir -- "${preflight_tmp}" || true
  fi
  exit "${exit_status}"
}
trap cleanup EXIT

declare -a findings=()

add_finding() {
  findings+=("$1")
}

have_gcloud=false
have_jq=false
have_curl=false
have_rg=false

for dependency in gcloud jq curl rg; do
  if command -v "${dependency}" >/dev/null 2>&1; then
    case "${dependency}" in
      gcloud) have_gcloud=true ;;
      jq) have_jq=true ;;
      curl) have_curl=true ;;
      rg) have_rg=true ;;
    esac
  else
    add_finding "required dependency missing: ${dependency}"
  fi
done

active_account_present=false
if [[ "${have_gcloud}" == true ]] &&
  gcloud auth list \
    --filter='status:ACTIVE' \
    --format='value(account)' 2>/dev/null |
    awk 'NF { present = 1 } END { exit present ? 0 : 1 }' >/dev/null; then
  active_account_present=true
  printf '%s\n' 'CHECK active-gcloud-account: present'
else
  add_finding 'active gcloud account missing'
  printf '%s\n' 'CHECK active-gcloud-account: missing'
fi

service_described=false
if [[ "${have_gcloud}" == true && "${have_jq}" == true && "${active_account_present}" == true ]]; then
  if gcloud run services describe "${SERVICE_ID}" \
    --project "${PROJECT_ID}" \
    --region "${REGION_ID}" \
    --format=json >"${service_json}" 2>/dev/null; then
    service_described=true
  else
    add_finding 'Cloud Run service description unavailable'
  fi
fi

if [[ "${service_described}" == true ]]; then
  if ! jq -e '
    ([
      .spec.template.metadata.annotations["autoscaling.knative.dev/maxScale"]?,
      .template.scaling.maxInstanceCount?,
      .spec.template.scaling.maxInstanceCount?
    ] | map(select(. != null) | tostring)) as $values
    | (($values | length) == 1 and $values[0] == "1")
  ' "${service_json}" >/dev/null 2>&1; then
    add_finding 'Cloud Run maxScale is not exactly 1'
  fi

  if ! jq -e --arg expected_secret "${EXPECTED_SECRET_ID}" '
    def all_env:
      [
        .spec.template.spec.containers[]?.env[]?,
        .template.containers[]?.env[]?
      ];
    all_env as $env
    | [$env[] | select(.name? == "GEMINI_API_KEY")] as $matches
    | ([$matches[0].valueFrom.secretKeyRef?] | map(select(. != null))) as $v1_refs
    | ([$matches[0].valueSource.secretKeyRef?] | map(select(. != null))) as $v2_refs
    | (
        ($matches | length) == 1
        and ($matches[0] | has("value") | not)
        and (
          (
            ($v1_refs | length) == 1
            and ($v2_refs | length) == 0
            and ($matches[0] | has("valueFrom"))
            and ($matches[0] | has("valueSource") | not)
            and $v1_refs[0].name? == $expected_secret
            and ($v1_refs[0].key? | type == "string" and length > 0)
          )
          or
          (
            ($v1_refs | length) == 0
            and ($v2_refs | length) == 1
            and ($matches[0] | has("valueFrom") | not)
            and ($matches[0] | has("valueSource"))
            and $v2_refs[0].secret? == $expected_secret
            and ($v2_refs[0].version? | type == "string" and length > 0)
          )
        )
      )
  ' "${service_json}" >/dev/null 2>&1; then
    add_finding 'GEMINI_API_KEY is not exactly one secret-backed entry without plaintext value'
  fi

  if ! jq -e --arg expected_model "${EXPECTED_MODEL}" '
    def all_env:
      [
        .spec.template.spec.containers[]?.env[]?,
        .template.containers[]?.env[]?
      ];
    all_env as $env
    | [$env[] | select(.name? == "GEMINI_MODEL")] as $matches
    | (
        ($matches | length) == 1
        and ($matches[0] | has("value"))
        and $matches[0].value == $expected_model
        and ($matches[0] | has("valueFrom") | not)
        and ($matches[0] | has("valueSource") | not)
      )
  ' "${service_json}" >/dev/null 2>&1; then
    add_finding 'GEMINI_MODEL is not exactly one direct value set to gemini-3.6-flash'
  fi

  service_url=''
  if service_url="$(jq -er '.status.url // .uri // empty' "${service_json}" 2>/dev/null)" &&
    [[ "${service_url}" == https://* ]]; then
    if [[ "${have_curl}" == true ]]; then
      for endpoint_spec in 'health|/health' 'privacy|/privacy/' 'support|/support/'; do
        endpoint_name="${endpoint_spec%%|*}"
        endpoint_path="${endpoint_spec#*|}"
        http_status="$(
          curl \
            --silent \
            --output /dev/null \
            --write-out '%{http_code}' \
            --connect-timeout 10 \
            --max-time 20 \
            "${service_url}${endpoint_path}" 2>/dev/null || true
        )"
        if [[ "${http_status}" != '200' ]]; then
          add_finding "/${endpoint_name} did not return HTTP 200"
        fi
      done
    fi
  else
    add_finding 'Cloud Run service URL unavailable'
  fi
fi

if [[ "${have_gcloud}" == true && "${have_rg}" == true && "${active_account_present}" == true ]]; then
  if gcloud logging read \
    'resource.type="cloud_run_revision" AND resource.labels.service_name="kalories" AND resource.labels.location="asia-northeast1"' \
    --project "${PROJECT_ID}" \
    --limit 200 \
    --order desc \
    --format=json >"${logs_json}" 2>/dev/null; then
    set +e
    rg -q -F \
      -e 'data:image/' \
      -e 'GEMINI_API_KEY' \
      -e 'Authorization:' \
      -e 'api_key=' \
      "${logs_json}"
    log_scan_status=$?
    set -e

    case "${log_scan_status}" in
      0) add_finding 'Cloud Run logs contain a forbidden sensitive literal' ;;
      1) ;;
      *) add_finding 'Cloud Run log safety scan failed' ;;
    esac
  else
    add_finding 'Cloud Run log read failed'
  fi
fi

if ((${#findings[@]} > 0)); then
  printf '%s\n' 'NO-GO: TestFlight backend preflight'
  for finding in "${findings[@]}"; do
    printf 'NO-GO: %s\n' "${finding}"
  done
  exit 1
fi

printf '%s\n' 'PASS: TestFlight backend preflight'
