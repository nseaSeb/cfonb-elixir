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
          details: Details.t()
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
      details: %Details{}
    }
  end

  @doc false
  @spec add_detail(t, %{qualifier: String.t(), info: binary}) :: t
  def add_detail(%__MODULE__{} = operation, %{qualifier: qualifier, info: info}) do
    %{operation | details: Details.merge(operation.details, qualifier, info)}
  end
end
