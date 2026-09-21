---
name: Private local personal statistics
about: Propose an optional on-device focus history without a dashboard
title: "Consider private local personal statistics"
labels: [proposal, privacy]
assignees: ''
---

## Problem

People may want a lightweight history of completed focus and break blocks without turning Focus Island into a productivity dashboard.

## Proposed scope

Design an optional local-only history with a clear retention limit, export/delete controls, and a small secondary summary.

## Acceptance criteria

- Data stays on-device by default and can be fully deleted in Settings.
- No free-text content, health data, or behavioral profiling is retained.
- The retention rule is visible and the feature does not affect timer behavior.

## Non-goals

Accounts, cloud sync, leaderboards, streaks, social comparison, or gamification.

## Dependencies

Data-model and migration design, privacy review, and user research.

## Status

Proposal only. Focus Island currently has no session history.
