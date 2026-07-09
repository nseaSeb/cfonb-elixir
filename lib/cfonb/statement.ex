defmodule CFONB.Statement do
  @moduledoc """
  A parsed CFONB account statement (relevé de compte).

  A statement is delimited by a previous-balance record (`01`) and a
  new-balance record (`07`), and holds every operation (`04`, with its `05`
  details) that occurred in between.

  Beyond the parsed fields, it can rebuild the raw lines (`raw/1`) and derive
  the account's `rib/1` and `iban/1`.

  Field names mirror the [Ruby `cfonb` gem](https://github.com/pennylane-hq/cfonb)
  for cross-compatibility.
  """

  alias CFONB.{Operation, Rib}

  @type t :: %__MODULE__{
          bank: String.t(),
          branch: String.t(),
          currency: String.t(),
          account: String.t(),
          from: Date.t() | nil,
          from_balance: Decimal.t() | nil,
          to: Date.t() | nil,
          to_balance: Decimal.t() | nil,
          operations: [Operation.t()],
          begin_raw: String.t() | nil,
          end_raw: String.t() | nil
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
    :begin_raw,
    :end_raw,
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
      begin_raw: fields.raw,
      operations: []
    }
  end

  @doc false
  @spec close(t, map) :: t
  def close(%__MODULE__{} = statement, fields) do
    %{statement | to: fields.date, to_balance: fields.amount, end_raw: fields.raw}
  end

  @doc """
  Rebuilds the raw record lines of the statement (previous balance, each
  operation with its details, new balance), newline-separated.
  """
  @spec raw(t) :: String.t()
  def raw(%__MODULE__{} = statement) do
    ([statement.begin_raw] ++ Enum.map(statement.operations, & &1.raw) ++ [statement.end_raw])
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @doc """
  Returns the 23-character French RIB (`bank ++ branch ++ account ++ key`).
  """
  @spec rib(t) :: String.t()
  def rib(%__MODULE__{bank: bank, branch: branch, account: account}) do
    Rib.rib(bank, branch, account)
  end

  @doc """
  Returns the French IBAN derived from the statement's `rib/1`.
  """
  @spec iban(t) :: String.t()
  def iban(%__MODULE__{bank: bank, branch: branch, account: account}) do
    Rib.iban(bank, branch, account)
  end
end
