defmodule CFONB.Operation do
  @moduledoc """
  A single operation (movement) on a statement, built from a `04` record and
  enriched by any following `05` detail records.

  In this first version, `05` details are exposed generically as a list of
  `%{qualifier: String.t(), info: String.t()}`. Richer, qualifier-specific
  decoding (fees, references, …) is planned for a later version.

  Field names mirror the [Ruby `cfonb` gem](https://github.com/pennylane-hq/cfonb).
  """

  @type detail :: %{qualifier: String.t(), info: String.t()}

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
          details: [detail]
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
    details: []
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
      details: []
    }
  end

  @doc false
  @spec add_detail(t, detail) :: t
  def add_detail(%__MODULE__{} = operation, detail) do
    %{operation | details: operation.details ++ [detail]}
  end
end
