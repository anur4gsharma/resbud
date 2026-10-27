# ADR 0003: Represent unknown research facts explicitly

- **Status:** Accepted for the unreleased MVP contract
- **Date:** 2026-10-27

## Context

The product requirements and paper schema distinguish facts supplied by the user, facts explicitly unavailable/not collected, and facts unknown because they were not supplied. The generation request enums had only the first two categories, so clients could not preserve that distinction. The request also allowed a `provided` status with no corresponding content.

## Decision

Add `unknown` to methodology, dataset/materials, results, and limitations status enums. Keep specific explicit states such as `results_status: not_collected` and `limitations_status: not_identified`. A `provided` status requires a corresponding non-empty detail string. Synchronize the JSON Schema, OpenAPI, Pydantic models, and tests. Paper schema version remains unchanged because this only changes generation input.

## Consequences

- Unknown information can be carried through the workflow without implying that the user confirmed its absence.
- Requests that label a fact `provided` without content are rejected.
- The contract is not yet released; clients should use the synchronized schema rather than older enum copies.

## Alternatives considered

- **Treat omitted detail as unknown while keeping old enums:** rejected because status is required and the omitted detail is already allowed for explicit unavailable/not-applicable states; omission alone cannot distinguish them.
- **Reuse `not_available` for unknown:** rejected because it falsely asserts that the user knows the fact is unavailable.
