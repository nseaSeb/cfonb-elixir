defmodule CFONB.Operation.Details do
  @moduledoc """
  Structured content gathered from the `05` (complément) records that follow a
  `04` operation.

  Each `05` record carries a 3-character qualifier (positions 46-48) and a
  70-character information zone (positions 49-118). `merge/3` decodes that zone
  according to the qualifier and folds it into this struct, so an operation
  exposes ready-to-use fields such as `debtor`, `operation_reference` or `fee`
  instead of raw lines.

  Repeated `LIB` lines are concatenated (newline-separated). Unrecognized
  qualifiers are preserved verbatim under `unknown`, keyed by qualifier.

  Field names and semantics mirror the
  [Ruby `cfonb` gem](https://github.com/pennylane-hq/cfonb).
  """

  @type t :: %__MODULE__{
          free_label: String.t() | nil,
          operation_reference: String.t() | nil,
          client_reference: String.t() | nil,
          purpose: String.t() | nil,
          debtor: String.t() | nil,
          ultimate_debtor: String.t() | nil,
          creditor: String.t() | nil,
          ultimate_creditor: String.t() | nil,
          creditor_identifier: String.t() | nil,
          creditor_identifier_type: String.t() | nil,
          debtor_identifier: String.t() | nil,
          debtor_identifier_type: String.t() | nil,
          original_currency: String.t() | nil,
          original_amount: Decimal.t() | nil,
          exchange_rate: Decimal.t() | nil,
          unstructured_label: String.t() | nil,
          structured_label: String.t() | nil,
          unstructured_label_2: String.t() | nil,
          fee_currency: String.t() | nil,
          fee: Decimal.t() | nil,
          unknown: %{optional(String.t()) => String.t()}
        }

  defstruct free_label: nil,
            operation_reference: nil,
            client_reference: nil,
            purpose: nil,
            debtor: nil,
            ultimate_debtor: nil,
            creditor: nil,
            ultimate_creditor: nil,
            creditor_identifier: nil,
            creditor_identifier_type: nil,
            debtor_identifier: nil,
            debtor_identifier_type: nil,
            original_currency: nil,
            original_amount: nil,
            exchange_rate: nil,
            unstructured_label: nil,
            structured_label: nil,
            unstructured_label_2: nil,
            fee_currency: nil,
            fee: nil,
            unknown: %{}

  @doc """
  Folds one `05` record — its `qualifier` and raw 70-char `info` zone — into the
  given details struct.
  """
  @spec merge(t, String.t(), binary) :: t
  def merge(details, qualifier, info)

  # A blank qualifier carries no detail.
  def merge(%__MODULE__{} = details, "", _info), do: details

  def merge(%__MODULE__{} = details, qualifier, info) do
    detail = String.trim(info)

    case qualifier do
      "LIB" ->
        %{details | free_label: append(details.free_label, detail)}

      "REF" ->
        %{details | operation_reference: presence(detail)}

      "NPY" ->
        %{details | debtor: presence(detail)}

      "NPO" ->
        %{details | ultimate_debtor: presence(detail)}

      "NBE" ->
        %{details | creditor: presence(detail)}

      "NBU" ->
        %{details | ultimate_creditor: presence(detail)}

      "LCC" ->
        %{details | unstructured_label: presence(detail)}

      "LC2" ->
        %{details | unstructured_label_2: presence(detail)}

      "LCS" ->
        %{details | structured_label: part(detail, 0, 36)}

      "RCN" ->
        %{details | client_reference: part(detail, 0, 35), purpose: part(detail, 35, 70)}

      "IBE" ->
        %{
          details
          | creditor_identifier: part(detail, 0, 35),
            creditor_identifier_type: part(detail, 35, 70)
        }

      "IPY" ->
        %{
          details
          | debtor_identifier: part(detail, 0, 35),
            debtor_identifier_type: part(detail, 35, 70)
        }

      "FEE" ->
        fee(details, detail)

      "MMO" ->
        exchange(details, detail)

      other ->
        %{details | unknown: put_unknown(details.unknown, other, detail)}
    end
  end

  # FEE: currency (3) + scale (1) + amount (14 digits).
  defp fee(details, detail) do
    scale = detail |> String.slice(3, 1) |> to_int()

    %{
      details
      | fee_currency: String.slice(detail, 0, 3),
        fee: to_decimal(String.slice(detail, 4, 14), scale)
    }
  end

  # MMO: original currency (3) + scale (1) + amount (14), plus an optional
  # exchange rate: value (4) at offset 26 with its own scale (1) at offset 18.
  defp exchange(details, detail) do
    scale = detail |> String.slice(3, 1) |> to_int()

    details = %{
      details
      | original_currency: String.slice(detail, 0, 3),
        original_amount: to_decimal(String.slice(detail, 4, 14), scale)
    }

    case detail |> String.slice(26, 4) |> String.trim() do
      "" ->
        details

      rate ->
        rate_scale = detail |> String.slice(18, 1) |> to_int()
        %{details | exchange_rate: to_decimal(rate, rate_scale)}
    end
  end

  defp append(nil, value), do: presence(value)
  defp append(existing, value), do: existing <> "\n" <> value

  defp put_unknown(unknown, key, value) do
    case unknown do
      %{^key => existing} -> Map.put(unknown, key, existing <> "\n" <> value)
      _ -> Map.put(unknown, key, value)
    end
  end

  defp part(detail, start, length), do: presence(String.slice(detail, start, length))

  defp presence(string) do
    case String.trim(string) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp to_decimal(digits, scale), do: %Decimal{sign: 1, coef: to_int(digits), exp: -scale}

  defp to_int(binary) do
    case String.trim(binary) do
      "" -> 0
      digits -> String.to_integer(digits)
    end
  end
end
