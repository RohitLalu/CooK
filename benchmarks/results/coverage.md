# BIST fault coverage

Every single stuck-at fault on the 2×2 mesh, one per simulation (`tb/tb_coverage.v`).
A link fault counts as detected when every router's dead-link mask marks that
link; a router fault when that router's self-test fails. False alarm: any other
link or router flagged.

Healthy run: nothing flagged.

| Fault site | Faults | Detected | Coverage | Runs with a false alarm |
|---|---|---|---|---|
| link data wire | 704 | 704 | 100.0 % | 0 |
| link valid | 16 | 16 | 100.0 % | 0 |
| link ready | 16 | 8 | 50.0 % | 0 |
| router output data wire | 1056 | 943 | 89.3 % | 0 |
| router output valid | 24 | 24 | 100.0 % | 0 |
| **all** | **1816** | **1695** | **93.3 %** | 0 |

Undetected, link ready: stuck-at-1 (8).

Undetected, router output data wire: dst x stuck-at-0 (6); dst x stuck-at-1 (6); dst y stuck-at-0 (6); dst y stuck-at-1 (6); parity stuck-at-0 (23); parity stuck-at-1 (18); poison stuck-at-0 (12); src stuck-at-0 (12); src stuck-at-1 (12); type stuck-at-1 (12).

<details><summary>Every undetected fault</summary>

- link ready: tile 0 port S stuck-at-1
- link ready: tile 0 port E stuck-at-1
- link ready: tile 1 port S stuck-at-1
- link ready: tile 1 port W stuck-at-1
- link ready: tile 2 port N stuck-at-1
- link ready: tile 2 port E stuck-at-1
- link ready: tile 3 port N stuck-at-1
- link ready: tile 3 port W stuck-at-1
- router output data wire: tile 0 port S dst x bit 32 stuck-at-0
- router output data wire: tile 0 port S dst y bit 33 stuck-at-1
- router output data wire: tile 0 port S src bit 34 stuck-at-0
- router output data wire: tile 0 port S src bit 35 stuck-at-0
- router output data wire: tile 0 port S type bit 36 stuck-at-1
- router output data wire: tile 0 port S poison bit 38 stuck-at-0
- router output data wire: tile 0 port S parity bit 39 stuck-at-0
- router output data wire: tile 0 port S parity bit 40 stuck-at-1
- router output data wire: tile 0 port S parity bit 41 stuck-at-1
- router output data wire: tile 0 port S parity bit 42 stuck-at-0
- router output data wire: tile 0 port E dst x bit 32 stuck-at-1
- router output data wire: tile 0 port E dst y bit 33 stuck-at-0
- router output data wire: tile 0 port E src bit 34 stuck-at-0
- router output data wire: tile 0 port E src bit 35 stuck-at-0
- router output data wire: tile 0 port E type bit 36 stuck-at-1
- router output data wire: tile 0 port E poison bit 38 stuck-at-0
- router output data wire: tile 0 port E parity bit 39 stuck-at-0
- router output data wire: tile 0 port E parity bit 40 stuck-at-1
- router output data wire: tile 0 port E parity bit 41 stuck-at-1
- router output data wire: tile 0 port E parity bit 42 stuck-at-0
- router output data wire: tile 0 port L dst x bit 32 stuck-at-0
- router output data wire: tile 0 port L dst y bit 33 stuck-at-0
- router output data wire: tile 0 port L src bit 34 stuck-at-0
- router output data wire: tile 0 port L src bit 35 stuck-at-0
- router output data wire: tile 0 port L type bit 36 stuck-at-1
- router output data wire: tile 0 port L poison bit 38 stuck-at-0
- router output data wire: tile 0 port L parity bit 41 stuck-at-1
- router output data wire: tile 0 port L parity bit 42 stuck-at-0
- router output data wire: tile 1 port S dst x bit 32 stuck-at-1
- router output data wire: tile 1 port S dst y bit 33 stuck-at-1
- router output data wire: tile 1 port S src bit 34 stuck-at-1
- router output data wire: tile 1 port S src bit 35 stuck-at-0
- router output data wire: tile 1 port S type bit 36 stuck-at-1
- router output data wire: tile 1 port S poison bit 38 stuck-at-0
- router output data wire: tile 1 port S parity bit 39 stuck-at-0
- router output data wire: tile 1 port S parity bit 40 stuck-at-1
- router output data wire: tile 1 port S parity bit 41 stuck-at-1
- router output data wire: tile 1 port S parity bit 42 stuck-at-0
- router output data wire: tile 1 port W dst x bit 32 stuck-at-0
- router output data wire: tile 1 port W dst y bit 33 stuck-at-0
- router output data wire: tile 1 port W src bit 34 stuck-at-1
- router output data wire: tile 1 port W src bit 35 stuck-at-0
- router output data wire: tile 1 port W type bit 36 stuck-at-1
- router output data wire: tile 1 port W poison bit 38 stuck-at-0
- router output data wire: tile 1 port W parity bit 39 stuck-at-0
- router output data wire: tile 1 port W parity bit 41 stuck-at-1
- router output data wire: tile 1 port W parity bit 42 stuck-at-0
- router output data wire: tile 1 port L dst x bit 32 stuck-at-1
- router output data wire: tile 1 port L dst y bit 33 stuck-at-0
- router output data wire: tile 1 port L src bit 34 stuck-at-1
- router output data wire: tile 1 port L src bit 35 stuck-at-0
- router output data wire: tile 1 port L type bit 36 stuck-at-1
- router output data wire: tile 1 port L poison bit 38 stuck-at-0
- router output data wire: tile 1 port L parity bit 41 stuck-at-1
- router output data wire: tile 1 port L parity bit 42 stuck-at-0
- router output data wire: tile 2 port N dst x bit 32 stuck-at-0
- router output data wire: tile 2 port N dst y bit 33 stuck-at-0
- router output data wire: tile 2 port N src bit 34 stuck-at-0
- router output data wire: tile 2 port N src bit 35 stuck-at-1
- router output data wire: tile 2 port N type bit 36 stuck-at-1
- router output data wire: tile 2 port N poison bit 38 stuck-at-0
- router output data wire: tile 2 port N parity bit 39 stuck-at-0
- router output data wire: tile 2 port N parity bit 40 stuck-at-0
- router output data wire: tile 2 port N parity bit 41 stuck-at-1
- router output data wire: tile 2 port N parity bit 42 stuck-at-0
- router output data wire: tile 2 port E dst x bit 32 stuck-at-1
- router output data wire: tile 2 port E dst y bit 33 stuck-at-1
- router output data wire: tile 2 port E src bit 34 stuck-at-0
- router output data wire: tile 2 port E src bit 35 stuck-at-1
- router output data wire: tile 2 port E type bit 36 stuck-at-1
- router output data wire: tile 2 port E poison bit 38 stuck-at-0
- router output data wire: tile 2 port E parity bit 39 stuck-at-0
- router output data wire: tile 2 port E parity bit 40 stuck-at-1
- router output data wire: tile 2 port E parity bit 41 stuck-at-1
- router output data wire: tile 2 port E parity bit 42 stuck-at-0
- router output data wire: tile 2 port L dst x bit 32 stuck-at-0
- router output data wire: tile 2 port L dst y bit 33 stuck-at-1
- router output data wire: tile 2 port L src bit 34 stuck-at-0
- router output data wire: tile 2 port L src bit 35 stuck-at-1
- router output data wire: tile 2 port L type bit 36 stuck-at-1
- router output data wire: tile 2 port L poison bit 38 stuck-at-0
- router output data wire: tile 2 port L parity bit 40 stuck-at-1
- router output data wire: tile 2 port L parity bit 41 stuck-at-1
- router output data wire: tile 2 port L parity bit 42 stuck-at-0
- router output data wire: tile 3 port N dst x bit 32 stuck-at-1
- router output data wire: tile 3 port N dst y bit 33 stuck-at-0
- router output data wire: tile 3 port N src bit 34 stuck-at-1
- router output data wire: tile 3 port N src bit 35 stuck-at-1
- router output data wire: tile 3 port N type bit 36 stuck-at-1
- router output data wire: tile 3 port N poison bit 38 stuck-at-0
- router output data wire: tile 3 port N parity bit 39 stuck-at-0
- router output data wire: tile 3 port N parity bit 40 stuck-at-0
- router output data wire: tile 3 port N parity bit 41 stuck-at-1
- router output data wire: tile 3 port N parity bit 42 stuck-at-0
- router output data wire: tile 3 port W dst x bit 32 stuck-at-0
- router output data wire: tile 3 port W dst y bit 33 stuck-at-1
- router output data wire: tile 3 port W src bit 34 stuck-at-1
- router output data wire: tile 3 port W src bit 35 stuck-at-1
- router output data wire: tile 3 port W type bit 36 stuck-at-1
- router output data wire: tile 3 port W poison bit 38 stuck-at-0
- router output data wire: tile 3 port W parity bit 39 stuck-at-0
- router output data wire: tile 3 port W parity bit 40 stuck-at-0
- router output data wire: tile 3 port W parity bit 41 stuck-at-1
- router output data wire: tile 3 port W parity bit 42 stuck-at-0
- router output data wire: tile 3 port L dst x bit 32 stuck-at-1
- router output data wire: tile 3 port L dst y bit 33 stuck-at-1
- router output data wire: tile 3 port L src bit 34 stuck-at-1
- router output data wire: tile 3 port L src bit 35 stuck-at-1
- router output data wire: tile 3 port L type bit 36 stuck-at-1
- router output data wire: tile 3 port L poison bit 38 stuck-at-0
- router output data wire: tile 3 port L parity bit 40 stuck-at-1
- router output data wire: tile 3 port L parity bit 41 stuck-at-1
- router output data wire: tile 3 port L parity bit 42 stuck-at-0

</details>
