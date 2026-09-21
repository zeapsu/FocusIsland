---
name: Optional product telemetry
about: Propose explicit opt-in operational telemetry
title: "Consider optional product telemetry"
labels: [proposal, privacy]
assignees: ''
---

## Problem

Maintainers may need aggregate reliability signals, while users should not have to trade privacy for a timer.

## Proposed scope

Design explicit opt-in telemetry limited to documented operational events such as update-check outcomes and crash/reliability signals.

## Acceptance criteria

- Telemetry is off by default and the app works the same when it is off.
- Consent can be withdrawn.
- No timer contents, session history, advertising identifiers, or HealthKit data are sent.
- Every event, retention period, processor, and deletion path is documented before collection.

## Non-goals

Default analytics, advertising, cross-app tracking, sale/sharing of data, or hidden diagnostics.

## Dependencies

Privacy policy, legal review, backend design, and data-deletion/incident processes.

## Status

Proposal only. Focus Island currently sends no product analytics.
