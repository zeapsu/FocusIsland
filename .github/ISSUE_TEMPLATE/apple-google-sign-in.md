---
name: Optional Apple and Google sign-in
about: Evaluate optional authentication after a defined account-backed feature
title: "Evaluate optional Apple and Google sign-in"
labels: [proposal, security, privacy]
assignees: ''
---

## Problem

An account may eventually support a user-requested cross-device feature, but it adds security, privacy, and operations work absent from the local app.

## Proposed scope

First define the account-backed feature and backend threat model. If justified, design optional Sign in with Apple and Google OAuth using native authorization, PKCE, Keychain token storage, short-lived sessions, token verification, and account deletion.

## Acceptance criteria

- A concrete product benefit exists before authentication is built.
- Offline anonymous timer use remains complete.
- Token verification happens on the backend; clients use PKCE and Keychain.
- Users can delete their account and associated server data.
- Both provider flows receive security review.

## Non-goals

Required login, Focus Island-managed passwords, social profiles, or cloud sync without deletion and conflict-resolution design.

## Dependencies

Accepted account/cloud product decision, backend, privacy policy, provider registration, deletion service, and security review.

## Status

Proposal only. Focus Island currently has no accounts or sign-in.
