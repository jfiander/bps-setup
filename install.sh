#!/usr/bin/env bash
#
# bpsd9 AMI provisioning script — coordinator.
#
# Usage:
#   sudo bash install.sh            # run all steps
#   sudo bash install.sh 7          # run only the step whose number is 7
#   sudo bash install.sh nginx      # run only the step matching "nginx"
#
# Run on a clean Ubuntu LTS server image. Idempotent — safe to re-run.
# The user provisions the EC2 instance, opens SSH, drops authorized_keys
# for the deploy user, and tests a Capistrano deploy after this completes.

SCRIPT_START=${SECONDS}
SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "${SETUP_ROOT}/lib/common.sh"

# Build the ordered list of step files.
mapfile -t STEPS < <(printf '%s\n' "${SETUP_ROOT}/steps/"*.sh | sort)
TOTAL_STEPS=${#STEPS[@]}

# Optional filter: numeric prefix or filename substring. Single-step runs
# show their own counter (1/1, 2/1, ...) rather than 13/14 — that's
# expected, the filter narrows the active step list.
if [[ $# -gt 0 ]]; then
  filter=$1
  if [[ ${filter} =~ ^[0-9]+$ ]]; then
    # Numeric: match the step's number prefix exactly so "1" doesn't
    # also pull in 10/11/12/13/14.
    mapfile -t STEPS < <(printf '%s\n' "${STEPS[@]}" \
      | grep -E "/0?${filter}-" || true)
  else
    # Non-numeric: substring match against the filename only (anchored
    # to the last path segment so the working directory's name doesn't
    # leak into matches).
    quoted=$(printf '%s' "${filter}" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
    mapfile -t STEPS < <(printf '%s\n' "${STEPS[@]}" \
      | grep -E "/[^/]*${quoted}[^/]*\.sh$" || true)
  fi
  if [[ ${#STEPS[@]} -eq 0 ]]; then
    echo "No steps match: ${filter}" >&2
    exit 2
  fi
  TOTAL_STEPS=${#STEPS[@]}
fi

trap 'rc=$?
  if (( rc == 0 )); then
    step_summary
  else
    printf "\n!!! install.sh failed in step %d/%d after %s !!!\n" \
      "${STEP_NUM}" "${TOTAL_STEPS}" \
      "$(fmt_duration $((SECONDS - SCRIPT_START)))" >&2
  fi' EXIT

for step in "${STEPS[@]}"; do
  name=$(basename "${step}" .sh | sed -E 's/^[0-9]+-//; s/-/ /g')
  step_start "${name}"
  . "${step}"
done
