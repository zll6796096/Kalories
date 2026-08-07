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
revision_json="${preflight_tmp}/revision.json"
iam_json="${preflight_tmp}/iam.json"
logs_json="${preflight_tmp}/logs.json"

cleanup() {
  local exit_status=$?
  local private_file

  trap - EXIT
  for private_file in \
    "${service_json}" \
    "${revision_json}" \
    "${iam_json}" \
    "${logs_json}"; do
    if [[ -f "${private_file}" ]]; then
      unlink -- "${private_file}" || true
    fi
  done
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
production_revision=''
service_url=''
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
  if ! production_revision="$(jq -er '
    [.status.traffic[]? |
      {revision: (.revisionName // ""), percent: (.percent // 0)}] as $traffic
    | select(($traffic | length) > 0)
    | select(all($traffic[];
        (.revision | type == "string" and length > 0)
        and (.percent | type == "number" and . >= 0 and . <= 100)))
    | ($traffic
       | group_by(.revision)
       | map({revision: .[0].revision, percent: (map(.percent) | add)})) as $sums
    | [$sums[] | select(.percent > 0)] as $active
    | select(($sums | map(.percent) | add) == 100)
    | if (($active | length) == 1 and $active[0].percent == 100)
      then $active[0].revision
      else empty
      end
  ' "${service_json}" 2>/dev/null)" || [[ -z "${production_revision}" ]]; then
    production_revision=''
    add_finding 'Cloud Run production traffic is not exactly one revision at 100 percent'
  fi

  if [[ -n "${KALORIES_EXPECTED_REVISION:-}" ]] &&
    [[ "${production_revision}" != "${KALORIES_EXPECTED_REVISION}" ]]; then
    add_finding 'expected production revision is not serving 100 percent'
  fi

  if ! service_url="$(jq -er '.status.url // .uri // empty' "${service_json}" 2>/dev/null)" ||
    [[ "${service_url}" != https://* ]]; then
    service_url=''
    add_finding 'Cloud Run service URL unavailable'
  fi
fi

revision_described=false
if [[ -n "${production_revision}" ]]; then
  if gcloud run revisions describe "${production_revision}" \
    --project "${PROJECT_ID}" \
    --region "${REGION_ID}" \
    --format=json >"${revision_json}" 2>/dev/null &&
    jq -e --arg expected_revision "${production_revision}" '
      type == "object" and .metadata.name? == $expected_revision
    ' "${revision_json}" >/dev/null 2>&1; then
    revision_described=true
  else
    add_finding 'Cloud Run production revision description unavailable'
  fi
fi

if [[ "${revision_described}" == true ]]; then
  if ! jq -e '
    ([
      .metadata.annotations["autoscaling.knative.dev/maxScale"]?,
      .scaling.maxInstanceCount?,
      .spec.scaling.maxInstanceCount?
    ] | map(select(. != null) | tostring)) as $values
    | (($values | length) == 1 and $values[0] == "1")
  ' "${revision_json}" >/dev/null 2>&1; then
    add_finding 'Cloud Run production revision maxScale is not exactly 1'
  fi

  if ! jq -e --arg expected_secret "${EXPECTED_SECRET_ID}" '
    def all_env:
      [.spec.containers[]?.env[]?, .containers[]?.env[]?];
    all_env as $env
    | [$env[] | select(.name? == "GEMINI_API_KEY")] as $matches
    | ([$matches[0].valueFrom.secretKeyRef?] | map(select(. != null))) as $v1_refs
    | ([$matches[0].valueSource.secretKeyRef?] | map(select(. != null))) as $v2_refs
    | (($matches | length) == 1)
      and ($matches[0] | has("value") | not)
      and (
        (
          ($v1_refs | length) == 1
          and ($v2_refs | length) == 0
          and ($matches[0] | has("valueFrom"))
          and ($matches[0] | has("valueSource") | not)
          and $v1_refs[0].name? == $expected_secret
          and ($v1_refs[0].key? | type == "string")
          and ($v1_refs[0].key | test("^[1-9][0-9]*$"))
        )
        or
        (
          ($v1_refs | length) == 0
          and ($v2_refs | length) == 1
          and ($matches[0] | has("valueFrom") | not)
          and ($matches[0] | has("valueSource"))
          and $v2_refs[0].secret? == $expected_secret
          and ($v2_refs[0].version? | type == "string")
          and ($v2_refs[0].version | test("^[1-9][0-9]*$"))
        )
      )
  ' "${revision_json}" >/dev/null 2>&1; then
    add_finding 'GEMINI_API_KEY is not exactly one pinned secret-backed entry'
  fi

  if ! jq -e --arg expected_model "${EXPECTED_MODEL}" '
    def all_env:
      [.spec.containers[]?.env[]?, .containers[]?.env[]?];
    all_env as $env
    | [$env[] | select(.name? == "GEMINI_MODEL")] as $matches
    | (($matches | length) == 1)
      and ($matches[0] | has("value"))
      and $matches[0].value == $expected_model
      and ($matches[0] | has("valueFrom") | not)
      and ($matches[0] | has("valueSource") | not)
  ' "${revision_json}" >/dev/null 2>&1; then
    add_finding 'GEMINI_MODEL is not exactly one direct value set to gemini-3.6-flash'
  fi

  if ! jq -e '
    ([.spec.containers[]?.image?, .containers[]?.image?]
      | map(select(type == "string"))) as $images
    | (($images | length) == 1
       and ($images[0] | test("@sha256:[0-9a-fA-F]{64}$")))
  ' "${revision_json}" >/dev/null 2>&1; then
    add_finding 'Cloud Run production revision image is not immutable'
  fi
fi

iam_read=false
if [[ "${have_gcloud}" == true && "${have_jq}" == true && "${active_account_present}" == true ]]; then
  if gcloud run services get-iam-policy "${SERVICE_ID}" \
    --project "${PROJECT_ID}" \
    --region "${REGION_ID}" \
    --format=json >"${iam_json}" 2>/dev/null &&
    jq -e '
      type == "object"
      and (.bindings? | type == "array")
      and all(.bindings[]?;
        (.role? | type == "string") and (.members? | type == "array"))
    ' "${iam_json}" >/dev/null 2>&1; then
    iam_read=true
  else
    add_finding 'Cloud Run IAM policy unavailable'
  fi
fi

# No machine-verifiable application-layer access architecture exists in this
# release gate. Public invoker policy is checked privately, but either public
# access or this missing protection keeps external TestFlight fail-closed.
public_invoker_present=false
if [[ "${iam_read}" == true ]] && jq -e '
    any(.bindings[]?;
      .role == "roles/run.invoker" and any(.members[]?; . == "allUsers"))
  ' "${iam_json}" >/dev/null 2>&1; then
  public_invoker_present=true
fi
if [[ "${public_invoker_present}" == true ]]; then
  add_finding 'public access or application-layer protection is not compliant'
else
  add_finding 'application-layer access protection is not verified'
fi

request_started_at=''
if [[ -n "${service_url}" && "${have_curl}" == true ]]; then
  request_started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  for endpoint_spec in 'health|/health' 'privacy|/privacy/' 'support|/support/'; do
    endpoint_name="${endpoint_spec%%|*}"
    endpoint_path="${endpoint_spec#*|}"
    http_status=''
    if ! http_status="$(
      curl \
        --silent \
        --output /dev/null \
        --write-out '%{http_code}' \
        --connect-timeout 10 \
        --max-time 20 \
        "${service_url}${endpoint_path}" 2>/dev/null
    )"; then
      add_finding "/${endpoint_name} request failed"
    elif [[ "${http_status}" != '200' ]]; then
      add_finding "/${endpoint_name} did not return HTTP 200"
    fi
  done
fi

if [[ "${have_gcloud}" == true && "${have_jq}" == true && "${have_rg}" == true &&
  "${active_account_present}" == true ]]; then
  log_filter='resource.type="cloud_run_revision" AND resource.labels.service_name="kalories" AND resource.labels.location="asia-northeast1"'
  if [[ -n "${production_revision}" ]]; then
    log_filter+=" AND resource.labels.revision_name=\"${production_revision}\""
  fi
  if [[ -n "${request_started_at}" ]]; then
    log_filter+=" AND timestamp>=\"${request_started_at}\""
  fi

  if gcloud logging read "${log_filter}" \
    --project "${PROJECT_ID}" \
    --limit 200 \
    --order desc \
    --format=json >"${logs_json}" 2>/dev/null; then
    if ! jq -e 'type == "array" and length > 0' "${logs_json}" >/dev/null 2>&1; then
      add_finding 'Cloud Run logs are not a nonempty JSON array'
    else
      sensitive_log_data=false
      if jq -e '
        def normalized_key: ascii_downcase | gsub("[-_]"; "");
        def sensitive_key:
          normalized_key as $key
          | [
              "authorization", "xgoogapikey", "apikey", "geminiapikey",
              "request", "requestbody", "providerrequest", "providerresponse",
              "response", "responsebody", "assessment", "nutrients",
              "fooddetected", "image", "prompt", "contents", "candidates"
            ]
          | index($key) != null;
        any(.. | objects | keys_unsorted[]?; sensitive_key)
        or any(.. | strings;
          test("(?i)data:image/|bearer[[:space:]]+[A-Za-z0-9._~+/-]+=*|AIza[0-9A-Za-z_-]{35}|[A-Za-z0-9+/]{256,}={0,2}|(^|[^[:alnum:]_])\\\"?(food_detected|nutrients|assessment|request|response|provider[ _-]?(request|response)|authorization|x-goog-api-key|api[_-]?key)\\\"?[[:space:]]*[:=]"))
      ' "${logs_json}" >/dev/null 2>&1; then
        sensitive_log_data=true
      else
        jq_scan_status=$?
        if [[ "${jq_scan_status}" -ne 1 ]]; then
          add_finding 'Cloud Run log safety scan failed'
        fi
      fi

      set +e
      rg -q -F \
        -e 'data:image/' \
        -e 'GEMINI_API_KEY' \
        -e 'Authorization:' \
        -e 'api_key=' \
        "${logs_json}"
      literal_scan_status=$?
      set -e
      case "${literal_scan_status}" in
        0) sensitive_log_data=true ;;
        1) ;;
        *) add_finding 'Cloud Run log safety scan failed' ;;
      esac

      if [[ "${sensitive_log_data}" == true ]]; then
        add_finding 'Cloud Run logs contain sensitive application data'
      fi

      if [[ -z "${production_revision}" ]] || ! jq -e --arg revision "${production_revision}" '
        def target($suffix):
          any(.[];
            .resource.labels.revision_name? == $revision
            and ((.httpRequest.requestUrl? // "") | endswith($suffix)));
        target("/health") and target("/privacy/") and target("/support/")
      ' "${logs_json}" >/dev/null 2>&1; then
        add_finding 'Cloud Run target request logs are missing'
      fi
    fi
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
