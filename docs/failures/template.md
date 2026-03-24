# Failure Report: [Short Title]

**Date:** YYYY-MM-DD
**Severity:** P1 (Critical) | P2 (High) | P3 (Medium) | P4 (Low)
**Duration:** Xh Ym
**Services Affected:** [internal service names + customer-facing impact, e.g. "product-api, storefront — checkout unavailable"]
**Author:** [name]

---

## Summary

One paragraph describing what happened, the impact, and how it was resolved.

---

## Timeline

| Time (UTC) | Event |
|------------|-------|
| HH:MM | Issue first observed |
| HH:MM | Alert fired / on-call paged |
| HH:MM | Investigation started |
| HH:MM | Root cause identified |
| HH:MM | Fix applied |
| HH:MM | Service fully recovered |

---

## Root Cause

What was the actual technical cause of the failure?
Be specific — avoid vague language like "misconfiguration".

---

## Contributing Factors

What conditions made this failure possible or worse?
(missing monitoring, lack of tests, unclear runbook, etc.)

---

## Impact

- **Users affected:** X
- **Requests failed:** X
- **Data loss:** Yes / No
- **SLO impact:** X% of error budget consumed

---

## Detection

How was the issue detected? How long after the actual start?
Was there an alert, or did a user report it?

---

## Resolution

Step-by-step what was done to resolve the issue.

---

## Action Items

| Action | Owner | Due Date | Status |
|--------|-------|----------|--------|
| Add alert for X | | | 🔴 Open |
| Write runbook for Y | | | 🔴 Open |
| Fix root cause Z | | | 🔴 Open |

---

## Lessons & Prevention

**What we learned:** What was surprising? What assumptions were wrong?

**What changes now:** Specific, concrete actions that prevent this class of failure.
(Vague answers like "be more careful" are not acceptable here.)
