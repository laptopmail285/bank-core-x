# Tests

Reserved for future test suites:
- `backend/` — API integration tests (supertest + a disposable test DB)
- SQL — pgTAP tests for the double-entry balance trigger, RLS policies,
  and the maker-checker self-approval block are the highest-value tests
  to add first, since those enforce the system's core financial and
  security invariants.

No tests exist yet in this build — flagged here rather than silently
omitted.
