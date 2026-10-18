# Security Policy

Hartwell Labs takes security reports seriously. This applies to every repository
in the organisation.

## Reporting a vulnerability

**Do not open a public issue.** Report privately through GitHub's
[private vulnerability reporting](https://github.com/Hartwell-Labs/labbridge/security/advisories/new)
on this repository, or by email to **security@hartwell-labs.pl**.

Include the affected component, steps to reproduce, and the impact you believe
it has. A proof of concept is worth more than a description.

## What to expect

| Stage | Target |
|---|---|
| Acknowledgement | 2 business days |
| First assessment | 7 days |
| Fix or mitigation plan | 30 days from the report |
| Disclosure | Coordinated with the reporter |

We will tell you when a fix ships and credit you in the advisory unless you
prefer otherwise.

## Scope

In scope: any code in a Hartwell Labs repository, including the release
binaries and container images built from it.

Out of scope: findings that require physical access to the machine, and
denial-of-service against our own infrastructure.

## Supported versions

Fixes land on the default branch and in the newest release. Older releases are
patched only for actively exploited issues.
