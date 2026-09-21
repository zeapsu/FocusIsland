---
name: HealthKit companion feasibility
about: Evaluate a privacy-preserving HealthKit companion before implementation
title: "Assess a HealthKit companion integration"
labels: [proposal, privacy]
assignees: ''
---

## Problem

Some people may want focus and break routines to appear alongside activity habits, but Focus Island is currently a local macOS timer with no HealthKit integration.

## Proposed scope

Evaluate a privacy-preserving iPhone or Apple Watch companion. Define the user benefit, supported platforms, exact HealthKit data types, authorization copy, storage boundary, and deletion behavior before writing HealthKit code.

## Acceptance criteria

- A feasibility decision documents supported platforms, data types, permission prompts, deletion, and the rationale to proceed or decline.
- The design follows HealthKit’s fine-grained authorization model and handles limited or unavailable data correctly.
- Focus Island’s local timer remains usable with no HealthKit access.

## Non-goals

- HealthKit access in the current macOS utility.
- Medical conclusions or health advice.
- Background collection or making HealthKit required.

## Dependencies

Apple capability/entitlements, a companion-app decision, privacy review, and real-device validation.

## Status

Proposal only. No HealthKit code or entitlement is present.
