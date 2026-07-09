# CFONB

A parser for **CFONB** bank files — the French banking interchange standard
(*Comité Français d'Organisation et de Normalisation Bancaires*).

This first version parses the **120-character account statement** (relevé de
compte): previous balance (`01`), operations (`04`), operation details (`05`),
and new balance (`07`). Amounts are returned as [`Decimal`](https://hex.pm/packages/decimal)
so money is never represented as a float.

## Installation

```elixir
def deps do
  [
    {:cfonb, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
{:ok, statements} = CFONB.parse(File.read!("releve.txt"))

[statement | _] = statements
statement.account       #=> "98765432100"
statement.from_balance  #=> #Decimal<-190.40>
statement.to_balance    #=> #Decimal<-241.21>

[operation | _] = statement.operations
operation.label                    #=> "PRLV SEPA TEST CABINET"
operation.amount                   #=> #Decimal<-32.21>
operation.details.operation_reference #=> "REFERENCE"
operation.details.debtor           #=> "INTERNET SFR"
operation.details.fee              #=> #Decimal<0.79>  (when a FEE detail is present)
```

The `05` detail records are decoded into a `CFONB.Operation.Details` struct
(qualifiers such as `LIB`, `REF`, `RCN`, `NPY`, `FEE`, `MMO`, …). Unrecognized
qualifiers are preserved under `details.unknown`.

The library also derives banking identifiers and exposes the raw records:

```elixir
CFONB.Statement.rib(statement)          #=> "20041010050500013M02606"
CFONB.Statement.iban(statement)         #=> "FR1420041010050500013M02606"
CFONB.Operation.type_code(operation)    #=> "B1D"  (interbank code + credit/debit)
statement.begin_raw                     #=> the original "01" line
CFONB.Statement.raw(statement)          #=> the statement's records, rebuilt
```

Other entry points:

```elixir
CFONB.parse_operation(input)      # parse a standalone 04 (+ its 05s)
CFONB.parse(input, optimistic: true)   # skip invalid records, best effort
CFONB.parse!(input)               # raising variants
```

`CFONB.parse/1` returns `{:ok, [%CFONB.Statement{}]}` or `{:error, reason}`.
Use `CFONB.parse!/1` if you prefer raising on invalid input.

See [`FORMAT.md`](FORMAT.md) for the exact CFONB 120 field layout.

## Émission — transfer orders (CFONB 160)

The library also **generates** transfer orders (ordres de virement) in the
CFONB 160-character format — a file *sent to* the bank. Build a
`CFONB.Virement` with its beneficiaries and call `encode/1`:

```elixir
order = %CFONB.Virement{
  numero_emetteur: "123456",
  nom_emetteur: "ACME SARL",
  iban: "FR1420041010050500013M02606",
  beneficiaires: [
    %CFONB.Virement.Beneficiaire{
      nom: "JEAN DUPONT",
      iban: "FR7630004000031234567890143",
      montant: Decimal.new("1250.00"),
      libelle: "SALAIRE JUILLET"
    }
  ]
}

{:ok, %{file: file, total: total}} = CFONB.Virement.encode(order)
# file  -> the 03/06/08 records, 160 chars each, CRLF-joined
# total -> #Decimal<1250.00>
```

Bank coordinates are given as an IBAN (decomposed and key-checked) or as split
RIB components (`etablissement` / `guichet` / `compte`). Amounts are `Decimal`
euros, encoded as unsigned cents. This first version emits the **ordinary
transfer** (code opération `02`). Use `CFONB.Virement.encode!/1` for the raising
variant. See [`FORMAT-VIREMENT.md`](FORMAT-VIREMENT.md) for the field layout.

## Scope & roadmap

- **v0.1** — CFONB 120 account statement parsing (all record types),
  qualifier-specific `05` decoding, RIB/IBAN derivation, raw-record access,
  standalone-operation and optimistic parsing. At feature parity with the
  reference Ruby gem.
- **v0.2** — émission of ordinary transfer orders (CFONB 160, records
  `03`/`06`/`08`), IBAN/RIB input with key verification.
- Planned — direct debits (prélèvement CFONB 160), the optional second
  destinataire record (`07`) and other operation codes (22/27/28/29/76), the
  240-character format. SEPA ISO 20022 XML (pain.001/pain.008) is out of scope
  for this fixed-width CFONB library.

## Credits & license

Reimplemented from the official CFONB specification, with a data model
**inspired by** and **compatible with** the Ruby gem
[pennylane-hq/cfonb](https://github.com/pennylane-hq/cfonb) (MIT) — its test
files are reused as a parsing oracle. Released under the MIT license.
