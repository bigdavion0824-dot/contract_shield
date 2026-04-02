# Contract Shield Release Operations Playbook

Date: 2026-04-02
Audience: Founder/operator and QA support
Scope: First 30 days after public launch

## 1) Daily Operations Dashboard Template

Use this twice per day (morning and evening).

### Snapshot Header

- Date:
- App version:
- Platform split: iOS / Android
- Rollout stage: 1%, 5%, 20%, 50%, 100%
- Release-safe mode: ON/OFF

### Core Reliability Metrics

- Crash-free users (%):
- Crash-free sessions (%):
- ANR/Freeze rate (Android):
- Startup failure count:
- Runtime diagnostics entries (last 24h):

### Purchase and Revenue Health

- Purchase success rate (%):
- Restore success rate (%):
- Purchase failed count (24h):
- Purchase canceled count (24h):

### Flow Health

- Buyer report generated count:
- PDF share success/failure:
- Contract scan success/failure:
- Legal link open failures:

### User Support Health

- New support tickets (24h):
- Open critical tickets:
- Median first response time:

## 2) Guardrails and Rollout Stops

If any of the following happen, pause rollout and investigate.

- Crash-free users < 99.5%
- Purchase success rate drops > 5 points from baseline
- Restore failure rate > 3%
- New high-volume runtime error cluster appears
- Startup failure count spikes day-over-day

## 3) Rollout Ladder

Only proceed when metrics are stable for the full hold period.

1. Stage 1: 1% for 24h
2. Stage 2: 5% for 24-48h
3. Stage 3: 20% for 48h
4. Stage 4: 50% for 48h
5. Stage 5: 100%

At each stage, confirm:

- No new P0/P1 crash cluster
- Purchase and restore are stable
- Runtime diagnostics trend is flat or improving

## 4) Incident Severity Matrix

### P0 (Critical)

Definition:

- App startup crash for many users
- Purchase flow hard failure across many devices
- Data corruption/loss

SLA:

- Triage: immediately
- Mitigation: within 2 hours
- Hotfix decision: within 4 hours

### P1 (High)

Definition:

- Crash in key workflows (buyer costs, report export, scanner)
- Restore purchases unreliable for a meaningful segment

SLA:

- Triage: same day
- Fix plan: within 24 hours
- Patch release: 1-3 days

### P2 (Medium)

Definition:

- Non-blocking errors, UX regressions, edge-case failures

SLA:

- Triage: within 48 hours
- Fix in next planned patch

## 5) Incident Response Runbook

1. Detect
- Confirm signal from store console, crash tool, runtime diagnostics, or support.

2. Triage
- Classify severity (P0/P1/P2).
- Capture app version, OS, device model, exact action path.

3. Stabilize
- Pause rollout if threshold breached.
- Keep release-safe mode ON.
- Disable risky promotion surfaces if needed.

4. Diagnose
- Reproduce with same version/device where possible.
- Confirm root cause and blast radius.

5. Fix
- Create minimal patch with smallest possible change set.
- Re-run analyze and smoke tests.
- Verify purchase and restore flows.

6. Validate
- Test on at least one iOS and one Android real device.
- Confirm no new runtime diagnostics spike.

7. Roll forward
- Resume rollout gradually using the ladder.

8. Postmortem
- Record trigger, impact, root cause, fix, and preventive action.

## 6) Hotfix Checklist

- Repro steps documented
- Root cause identified
- Patch validated locally
- flutter analyze passes
- flutter test passes
- Purchase/restore smoke checks pass
- Legal links open correctly
- Runtime diagnostics checked after fix
- Release notes prepared

## 7) User Support Templates

### Request for Details

Subject: We are investigating your issue

Body:

Thanks for reporting this. To help us fix this quickly, please share:

- App version
- Device model and OS version
- Exact steps before the issue happened
- Screenshot or screen recording if possible
- Whether this happens every time or occasionally

### Issue Resolved

Subject: Fix is now available

Body:

Thanks again for reporting this issue. We released a fix in version <VERSION>. Please update the app and let us know if the issue is resolved on your device.

## 8) Weekly Review Cadence

Once per week, review:

- Top 5 runtime errors by count
- Top 5 support reasons
- Purchase funnel drop-off points
- Feature stability trend (buyer reports, scanner, exports)
- Decision: keep release-safe mode ON or OFF for next week

## 9) Minimum Tooling to Keep Active

- Store console crash dashboards
- In-app Runtime Diagnostics page
- In-app System Health Check page
- Analytics Dashboard (debug/internal use)

## 10) Decision Log Template

- Date:
- Decision:
- Why:
- Data used:
- Risk level:
- Owner:
- Next review date:
