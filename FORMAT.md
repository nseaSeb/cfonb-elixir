# CFONB 120 — account statement format

Reference for the fields this library parses. Source of truth: the official
CFONB brochure *"Relevé de compte sur support informatique"* (Juillet 2004).
Positions are 1-indexed; each record is exactly **120 characters**.

Conventions:

- Numeric zones are right-aligned and zero-filled.
- Alphanumeric zones are left-aligned and blank-filled.
- `S` status: **M**andatory, **O**ptional, **D**ependent, **N** reserved (kept blank).

## Common header (positions 1–32)

| Pos | Len | Field | Notes |
|----:|----:|-------|-------|
| 1 | 2 | Record code | `01`, `04`, `05`, `07` |
| 3 | 5 | Bank code | |
| 8 | 4 | Internal operation code | operation/detail only; reserved on balances |
| 12 | 5 | Branch code (guichet) | |
| 17 | 3 | Currency (ISO 4217) | |
| 20 | 1 | Number of decimals (scale) | applies to the amount field |
| 22 | 11 | Account number | |

## Record 01 / 07 — previous / new balance

| Pos | Len | Field |
|----:|----:|-------|
| 35 | 6 | Date `JJMMAA` |
| 91 | 14 | Amount (signed, see below) |

## Record 04 — operation (mouvement)

| Pos | Len | Field |
|----:|----:|-------|
| 33 | 2 | Interbank operation code |
| 35 | 6 | Accounting date `JJMMAA` |
| 41 | 2 | Rejection reason code (dependent) |
| 43 | 6 | Value date `JJMMAA` |
| 49 | 32 | Label (libellé) |
| 82 | 7 | Entry number (numéro d'écriture) |
| 89 | 1 | Commission-exemption flag |
| 90 | 1 | Unavailability flag |
| 91 | 14 | Amount (signed) |
| 105 | 16 | Reference |

## Record 05 — operation detail (complément)

Optional, repeatable after a `04`. Adds qualifier-tagged extra information.

| Pos | Len | Field |
|----:|----:|-------|
| 46 | 3 | Qualifier (e.g. `LIB`, `REF`, `NPY`, `FEE`) |
| 49 | 70 | Complementary information |

## Amount encoding (signed)

The 14-character amount field is **13 digits + 1 specifier**. The specifier
encodes both the units digit and the sign:

| Sign | Units 0–9 |
|------|-----------|
| `+`  | `{` `A` `B` `C` `D` `E` `F` `G` `H` `I` |
| `-`  | `}` `J` `K` `L` `M` `N` `O` `P` `Q` `R` |

Value = `sign × (13 digits ++ units) / 10^scale`.

Example: `0000000001904}` with scale `2` → `−190.40`.

## Dates

`JJMMAA` (day, month, 2-digit year). The year pivots at 60: `> 60` → `19xx`,
otherwise `20xx`. A blank date field means "no date" (`nil`).
