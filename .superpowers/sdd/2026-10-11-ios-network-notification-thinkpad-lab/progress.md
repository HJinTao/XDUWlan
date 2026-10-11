# SDD ledger — plan: docs/superpowers/plans/2026-10-11-ios-network-notification-thinkpad-lab.md

## Pre-flight scan

| Task | Shared input/output | Finding and ruling |
| --- | --- | --- |
| 1 | `domain.dart`, `recovery_service.dart`, diagnostics; consumed by Tasks 2, 3, 5 | Defines the shared observation and authentication gate first. Ruling: execute before consumers; old fake compatibility is required. |
| 2 | `network_probe.dart`, `main.dart`, `AppDelegate.swift`; consumed by Tasks 3 and 6 | Path source and probe composition must land before notification/runtime wiring and proxy injection. Ruling: execute after Task 1. |
| 3 | `AppDelegate.swift`, runtime/UI; consumes Task 1/2 reports | Native AppDelegate changes overlap Task 2. Ruling: execute after Task 2 and preserve path handler teardown. |
| 4 | New tool, README/current/protocol docs; no code interface overlap | Independent fixed-action ThinkPad controller. Ruling: may run in parallel with Task 1. |
| 5 | `recovery_validation.dart`, Srun protocol; consumes shared safety rules | Independent from Task 4's new controller but uses existing production protocol. Ruling: may run in parallel; no real credentials or network execution. |
| 6 | `http_transport.dart`, `main.dart`; consumes Task 2 wiring | Proxy constructor must remain test/debug-only and wait for Task 2's main wiring. Ruling: execute after Task 2. |
| 7 | docs only; consumes completed runtime/tool behavior | Real acceptance requires authorized hardware and is unavailable here. Ruling: document as unverified; do not run down/up. |
| 8 | all affected tests/builds; consumes Tasks 1-6 | Final verification after implementation. Simulator may be used; no physical iOS device assumed. |

| Task self-consistency | Finding and ruling |
| --- | --- |
| 1 | Tests, interfaces, and gate location agree; compatibility adapter prevents existing fakes from blocking migration. |
| 2 | Native payload and Dart fallback agree; portal evidence remains the only campus evidence. |
| 3 | Permission status/request lifecycle and deduplicated events are internally consistent. |
| 4 | Allowlisted actions and private evidence output agree; real actions are explicitly restricted to authorized ThinkPad. |
| 5 | Single candidate, one challenge/login sequence, and two-run promotion gate agree. |
| 6 | Loopback-only proxy and direct production defaults agree; smoke script is environment-only. |
| 7 | Evidence chains are separate and missing physical device evidence remains unverified. |
| 8 | Verification commands cover all implementation surfaces; simulator limitation is explicit. |

## Rulings

- Ruling: keep existing user edits in `README.md`, `docs/current.md`, and `docs/protocol.md` and layer implementation updates onto them — they predate this turn and must not be discarded — cost is possible documentation merge work.
- Ruling: execute offline implementation and simulator/build verification without a physical iOS device — user explicitly states no physical device is available — real notification/path and ThinkPad acceptance remain unverified.

## Completion ledger

- Task 1: complete — `8f50634`, safety migration `5c1f462`, legacy observations fail closed.
- Task 2: complete — `81920be`, safety/lifecycle fix `11fdf28`, deferred channel setup `024e138`.
- Task 3: complete — `0890776`, teardown fix `7bcc06c`.
- Task 4: complete — `4f2f949`, controller hardening `6ac7888`, evidence path hardening `b95a5ee`.
- Task 5: complete — `4de78d6`, promotion/counting fix `d5b71c9`.
- Task 6: complete — `5372ed5`.
- Task 7: not run — physical iOS device and authorized ThinkPad are unavailable in this turn; limits recorded in `docs/current.md` and `docs/protocol.md`.
- Task 8: complete for offline scope — full Flutter test suite, analyzer, iOS device/simulator builds, Android debug build, and iPhone 16 Pro Simulator launch verified.
- Final review follow-up: restored desktop/Linux legacy probing while keeping iOS/Android background fail-closed; wired the ThinkPad CLI management-link and one-shot observer adapters; Android notification status now reflects the plugin's enabled state; automatic/background network transitions participate in notification dedupe.

