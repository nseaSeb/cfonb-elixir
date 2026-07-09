# CFONB 160 — ordre de virement (émission)

Reference for the fields this library emits when generating a transfer order.
Source of truth: the official CFONB brochure *"Remises informatisées d'ordres de
virements au format 160 caractères"* (Avril 2004). Positions are 1-indexed; each
record is exactly **160 characters**.

A remise (batch) is made of, in order:

  * one **émetteur** record (`03`) — the donneur d'ordre,
  * one **destinataire** record (`06`) per beneficiary,
  * one **total** record (`08`) — the summed amount.

Conventions (same as the 120 format):

- Numeric zones are right-aligned and zero-filled.
- Alphanumeric zones are left-aligned and blank-filled.
- Permitted characters (circulaire FBF 88/327): digits, uppercase letters, space,
  and `* - . / ( )`. `CFONB.Encode.sanitize/1` uppercases and strips accents.
- `S` status: **M**andatory, **O**ptional, **D**ependent, **N** reserved (blank).

This library emits the **ordinary transfer** (code opération `02`) in euros.

## Record 03 — émetteur (donneur d'ordre)

| Pos | Len | Field | Notes |
|----:|----:|-------|-------|
| 1 | 2 | Record code | `03` |
| 3 | 2 | Operation code | `02` (ordinary transfer) |
| 5 | 8 | Reserved | blank |
| 13 | 6 | Émetteur / identification number | |
| 19 | 1 | CCD code | échéance only; blank here |
| 20 | 6 | Reserved | blank |
| 26 | 5 | Date `JJMMA` | day, month, **single trailing year digit**; blank if absent |
| 31 | 24 | Donneur d'ordre name | from the émetteur RIB |
| 55 | 7 | Remise reference | optional |
| 62 | 19 | Reserved | blank |
| 81 | 1 | Currency | `E` (euro) |
| 82 | 5 | Reserved | blank |
| 87 | 5 | Émetteur branch code (guichet) | |
| 92 | 11 | Émetteur account number | |
| 103 | 16 | Donneur d'ordre identifier | optional; blank here |
| 119 | 31 | Reserved | blank |
| 150 | 5 | Émetteur bank code (établissement) | |
| 155 | 6 | Reserved | blank |

## Record 06 — destinataire (bénéficiaire)

| Pos | Len | Field | Notes |
|----:|----:|-------|-------|
| 1 | 2 | Record code | `06` |
| 3 | 2 | Operation code | same as the émetteur |
| 5 | 8 | Reserved | blank |
| 13 | 6 | Émetteur / identification number | same as the émetteur |
| 19 | 12 | Reference | at the donneur d'ordre's disposal |
| 31 | 24 | Bénéficiaire name | from the bénéficiaire RIB |
| 55 | 24 | Domiciliation | optional |
| 79 | 8 | Balance-of-payments declaration | dependent (non-resident); blank here |
| 87 | 5 | Bénéficiaire branch code (guichet) | |
| 92 | 11 | Bénéficiaire account number | |
| 103 | 16 | **Amount** | **cents, right-aligned, zero-filled, unsigned** |
| 119 | 31 | Label (libellé) | first ≥30 chars carried to the beneficiary |
| 150 | 5 | Bénéficiaire bank code (établissement) | |
| 155 | 6 | Reserved | blank |

An optional second destinataire record (`07`, complementary label) is defined by
the spec but not emitted by this version.

## Record 08 — total

All zones reserved (blank) except:

| Pos | Len | Field | Notes |
|----:|----:|-------|-------|
| 1 | 2 | Record code | `08` |
| 3 | 2 | Operation code | same as the émetteur |
| 13 | 6 | Émetteur / identification number | same as the émetteur |
| 103 | 16 | **Total amount** | sum of the `06` amounts, cents, right-aligned, zero-filled |

There is **no line counter** in the `08` record — only the total amount.

## Amount encoding

Expressed in **centimes** (cents), right-aligned, zero-filled, **unsigned**.
Value = `amount × 100`. Example: `1250.00 €` → `0000000000125000`. This is a
*different* encoding from the signed "montant" of the 120 statement format.

## Bank coordinates

The RIB **key** is never written in the 160 format. Coordinates may be supplied
as an IBAN (decomposed and key-checked via `CFONB.Rib.from_iban/1`) or as split
RIB components (`etablissement` / `guichet` / `compte`).
