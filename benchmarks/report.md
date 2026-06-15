# Benchmark — harnessed vs. unharnessed (criterion 3)

GENERATED from `results.json` by `bench.sh` — do not hand-edit; re-run to refresh.

**Both arms are measured, not assumed.** 28 injected defects across 12 trials x 6 tasks.

| Arm | catches | escaped | catch rate |
|-----|---------|---------|-----------|
| Unharnessed (naive non-empty-artifact self-check, run against the FS) | D1, D3 | D2, D4 | **14/28 = 0.5** |
| Harnessed (full witness pipeline) | D1, D2, D3 | D4 | **21/28 = 0.75** |

Unharnessed escaped/trial = 1.167 ± 0.389; harnessed = 0.583 ± 0.515. False blocks on clean tasks: 0.

## What it proves
Both arms are MEASURED (the unharnessed arm actually stats the filesystem). A naive "did I produce a non-empty artifact?" check catches the no-output classes (D1 premature-done, D3 forged-confirm) but ships **scope-drift (D2)** — an artifact that exists but doesn't address the goal. The witness pipeline (W4) catches D2 on top. That's the measured delta: 21/28 vs 14/28, not an arithmetic identity.

## What it does NOT prove
The harnessed catch-rate is **0.75 < 1.0** by design: the near-miss class **D4** (well-formed, on-goal, subtly wrong) is indistinguishable to the *keyless* witnesses and escapes. Only the live-W3 reviewer (out of scope for a keyless benchmark) addresses D4. This is the honest ceiling — not a universal-catch claim.

## Engage-gate (FORT-1) herding

Freehand-bail escape rate over 12 trials: gate OFF = 12/12 (100% escape), gate ON = 0/12 (0% escape). The engage-gate converts a lazy freehand-then-stop bail from always-allowed to always-blocked. Measures the gate mechanics, not model compliance once unblocked.
