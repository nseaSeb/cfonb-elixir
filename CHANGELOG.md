# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0]

### Added

- **Émission of transfer orders (CFONB 160).** `CFONB.Virement.encode/2` and
  `encode!/2` generate an ordinary transfer order (code opération `02`) as
  `03`/`06`/`08` records, 160 characters each. Bank coordinates are accepted as
  an IBAN (decomposed and key-checked) or as split RIB components — never both
  on the same struct (rejected as ambiguous).
- Payment-safety validation in `encode/2`: mandatory names, account charset
  and length, émetteur-number length and type, amount and 08-total bounded to
  the 16-digit cents zone — every invalid input returns `{:error, reason}`
  instead of silently truncating, emitting blank zones, or raising.
- `CFONB.Encode` — fixed-width field formatting helpers (numeric, alphanumeric,
  unsigned-cents amount, `JJMMA` date, character-set sanitization).
- `CFONB.Rib` — shared RIB key computation and IBAN derivation, including
  `from_iban/1` which verifies both the IBAN check digits and the RIB key.
- `FORMAT-VIREMENT.md` documenting the CFONB 160 field layout.

### Changed

- `CFONB.Statement.rib/1` and `iban/1` now delegate to `CFONB.Rib`
  (behavior-preserving refactor).

## [0.1.0]

### Added

- Initial CFONB 120 account-statement parser: `CFONB.parse/2`, `parse!/2`,
  `parse_operation/2`, with `01`/`04`/`05`/`07` record decoding, qualifier-specific
  `05` details, RIB/IBAN derivation, raw-record access, and optimistic parsing.
  At feature parity with the reference Ruby gem.
