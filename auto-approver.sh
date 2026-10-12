#!/usr/bin/env bash
set -u

# Approve every one-shot permission prompt in this Herdr session. This never
# selects "Allow always" and ignores ordinary questions and confirmations.
log_file="$(dirname "$0")/approval-listener.log"
declare -A prompt_signature=()
declare -A approval_attempts=()
declare -A last_sent=()

log() {
  printf '%s %s\n' "$(date -Is)" "$*" >>"$log_file"
}

log "listener started workspace=${HERDR_WORKSPACE_ID:-unknown}"
while sleep 0.5; do
  agents_json="$(herdr agent list 2>/dev/null)" || continue
  mapfile -t agents < <(
    jq -r '.result.agents[] | .name // .pane_id' <<<"$agents_json"
  )

  for agent in "${agents[@]}"; do
    screen="$(herdr agent read "$agent" --source detection --lines 80 2>/dev/null)" || continue
    if [[ "$screen" != *"Permission required"*"Allow once"* ]]; then
      unset 'prompt_signature[$agent]' 'approval_attempts[$agent]' 'last_sent[$agent]'
      continue
    fi

    prompt="${screen##*Permission required}"
    if [[ "${prompt_signature[$agent]:-}" != "$prompt" ]]; then
      prompt_signature["$agent"]="$prompt"
      approval_attempts["$agent"]=0
      last_sent["$agent"]=0
    fi

    now="$(date +%s)"
    attempts="${approval_attempts[$agent]:-0}"
    sent_at="${last_sent[$agent]:-0}"
    (( attempts < 3 )) || continue
    (( now - sent_at >= 3 )) || continue

    approval_attempts["$agent"]=$((attempts + 1))
    last_sent["$agent"]="$now"
    if herdr agent send-keys "$agent" enter >/dev/null 2>&1; then
      log "approved-once agent=$agent attempt=$((attempts + 1))"
    fi
  done
done