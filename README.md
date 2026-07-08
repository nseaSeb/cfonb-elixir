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
operation.label   #=> "PRLV SEPA TEST CABINET"
operation.amount  #=> #Decimal<-32.21>
operation.details #=> [%{qualifier: "LIB", info: "..."}, ...]
```

`CFONB.parse/1` returns `{:ok, [%CFONB.Statement{}]}` or `{:error, reason}`.
Use `CFONB.parse!/1` if you prefer raising on invalid input.

See [`FORMAT.md`](FORMAT.md) for the exact CFONB 120 field layout.

## Scope & roadmap

- **v0.1** — CFONB 120 account statement (all record types). `05` details are
  exposed generically as `%{qualifier, info}`.
- Planned — qualifier-specific detail decoding (fees, references, …), the
  240-character format, and CFONB generation (e.g. transfer orders).

## Credits & license

Reimplemented from the official CFONB specification, with a data model
**inspired by** and **compatible with** the Ruby gem
[pennylane-hq/cfonb](https://github.com/pennylane-hq/cfonb) (MIT) — its test
files are reused as a parsing oracle. Released under the MIT license.
