defmodule CFONB.Operation do
  @moduledoc """
  A single operation (movement) on a statement, built from a `04` record and
  enriched by any following `05` detail records.

  The `05` details are decoded into a `CFONB.Operation.Details` struct, so an
  operation exposes ready-to-use fields such as `details.debtor` or
  `details.operation_reference`.

  Field names mirror the [Ruby `cfonb` gem](https://github.com/pennylane-hq/cfonb).
  """

  alias CFONB.Operation.Details

  @type t :: %__MODULE__{
          amount: Decimal.t(),
          currency: String.t(),
          date: Date.t() | nil,
          value_date: Date.t() | nil,
          label: String.t(),
          number: integer | nil,
          reference: String.t(),
          internal_code: String.t(),
          interbank_code: String.t(),
          rejection_code: String.t(),
          exoneration_code: String.t(),
          unavailability_code: String.t(),
          details: Details.t(),
          raw: String.t() | nil
        }

  defstruct [
    :amount,
    :currency,
    :date,
    :value_date,
    :label,
    :number,
    :reference,
    :internal_code,
    :interbank_code,
    :rejection_code,
    :exoneration_code,
    :unavailability_code,
    :raw,
    details: %Details{}
  ]

  @doc false
  @spec new(map) :: t
  def new(fields) do
    %__MODULE__{
      amount: fields.amount,
      currency: fields.currency,
      date: fields.date,
      value_date: fields.value_date,
      label: fields.label,
      number: fields.number,
      reference: fields.reference,
      internal_code: fields.internal_code,
      interbank_code: fields.interbank_code,
      rejection_code: fields.rejection_code,
      exoneration_code: fields.exoneration_code,
      unavailability_code: fields.unavailability_code,
      raw: fields.raw,
      details: %Details{}
    }
  end

  @doc false
  @spec add_detail(t, %{qualifier: String.t(), info: binary, raw: binary}) :: t
  def add_detail(%__MODULE__{} = operation, %{qualifier: qualifier, info: info, raw: raw}) do
    %{
      operation
      | details: Details.merge(operation.details, qualifier, info),
        raw: operation.raw <> "\n" <> raw
    }
  end

  @doc """
  Returns the operation type code: the interbank operation code followed by its
  direction — `"C"` (credit) when the amount is positive, `"D"` (debit) otherwise.
  """
  @spec type_code(t) :: String.t()
  def type_code(%__MODULE__{interbank_code: code, amount: amount}) do
    direction = if Decimal.compare(amount, Decimal.new(0)) == :gt, do: "C", else: "D"
    code <> direction
  end
end
