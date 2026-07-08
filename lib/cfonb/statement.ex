defmodule CFONB.Statement do
  @moduledoc """
  A parsed CFONB account statement (relevé de compte).

  A statement is delimited by a previous-balance record (`01`) and a
  new-balance record (`07`), and holds every operation (`04`, with its `05`
  details) that occurred in between.

  Field names mirror the [Ruby `cfonb` gem](https://github.com/pennylane-hq/cfonb)
  for cross-compatibility.
  """

  alias CFONB.Operation

  @type t :: %__MODULE__{
          bank: String.t(),
          branch: String.t(),
          currency: String.t(),
          account: String.t(),
          from: Date.t() | nil,
          from_balance: Decimal.t() | nil,
          to: Date.t() | nil,
          to_balance: Decimal.t() | nil,
          operations: [Operation.t()]
        }

  defstruct [
    :bank,
    :branch,
    :currency,
    :account,
    :from,
    :from_balance,
    :to,
    :to_balance,
    operations: []
  ]

  @doc false
  @spec new(map) :: t
  def new(fields) do
    %__MODULE__{
      bank: fields.bank,
      branch: fields.branch,
      currency: fields.currency,
      account: fields.account,
      from: fields.date,
      from_balance: fields.amount,
      operations: []
    }
  end

  @doc false
  @spec close(t, map) :: t
  def close(%__MODULE__{} = statement, fields) do
    %{statement | to: fields.date, to_balance: fields.amount}
  end
end
