---
name: frantic-board-health-audit
description: Validate a captured public Frantic board-health audit packet for bounty 43.
source:
  type: cli-tool
  command: pwsh
  args:
    - -NoProfile
    - -ExecutionPolicy
    - Bypass
    - -File
    - run.ps1
  timeout_seconds: 60
  sandbox:
    profile: readonly
    cwd_policy: skill-directory
    require_enforcement: false
inputs:
  capture_dir:
    type: string
    required: true
    description: Directory containing captured public Frantic board and bounty responses.
  output_dir:
    type: string
    required: true
    description: Directory where the generated audit artifacts are written.
  claim_id:
    type: string
    required: true
    description: Active Frantic claim id being audited.
runx:
  input_resolution:
    required:
      - capture_dir
      - output_dir
      - claim_id
---

Validate the public Frantic board health audit packet against the captured board, bounty API, and page responses.
