defmodule CFONB.Encode do
  @moduledoc """
  Low-level fixed-width field formatting for emitting CFONB records — the
  symmetric counterpart of the decoders in `CFONB`.

  Two alignment rules, per the CFONB brochure:

    * **numeric** zones are right-aligned and zero-filled (`numeric/2`),
    * **alphanumeric** zones are left-aligned and space-filled (`alpha/2`),
      restricted to the permitted character set (`sanitize/1`).

  Amounts are encoded as unsigned integer cents (`centimes/2`) — note this is a
  *different* encoding from the signed "montant" of the 120 statement format.
  Functions raise `ArgumentError` on data that cannot be represented (negative
  amount, more than two decimals, numeric overflow); callers are expected to
  validate user input first.
  """

  # Characters admitted by the CFONB 160 format (circulaire FBF 88/327):
  # digits, uppercase letters, space, and * - . / ( )
  @allowed ~r/[^0-9A-Z*\-.\/() ]/u
  @diacritics ~r/[\x{0300}-\x{036f}]/u

  @doc """
  Formats a numeric zone: right-aligned, zero-filled to `len`. Accepts an
  integer or a digit string. Raises if the value does not fit in `len`.
  """
  @spec numeric(integer | String.t(), pos_integer) :: String.t()
  def numeric(value, len) when is_integer(value) and value >= 0 do
    numeric(Integer.to_string(value), len)
  end

  def numeric(value, len) when is_binary(value) do
    digits = String.trim(value)

    cond do
      digits == "" ->
        String.duplicate("0", len)

      not (digits =~ ~r/^\d+$/) ->
        raise ArgumentError, "non-numeric value: #{inspect(value)}"

      String.length(digits) > len ->
        raise ArgumentError, "numeric overflow: #{inspect(value)} in #{len}"

      true ->
        String.pad_leading(digits, len, "0")
    end
  end

  @doc """
  Formats an alphanumeric zone: sanitized, left-aligned, space-filled, and
  truncated to `len`.
  """
  @spec alpha(String.t() | nil, pos_integer) :: String.t()
  def alpha(value, len) do
    value
    |> sanitize()
    |> String.slice(0, len)
    |> String.pad_trailing(len, " ")
  end

  @doc """
  Encodes a euro `%Decimal{}` amount as unsigned integer cents, right-aligned
  and zero-filled to `len` (default 16). Raises on a negative amount or on more
  than two decimal places.
  """
  @spec centimes(Decimal.t(), pos_integer) :: String.t()
  def centimes(%Decimal{} = amount, len \\ 16) do
    if Decimal.negative?(amount) do
      raise ArgumentError, "amount must not be negative: #{Decimal.to_string(amount)}"
    end

    cents = Decimal.mult(amount, 100)

    if Decimal.equal?(cents, Decimal.round(cents, 0)) do
      numeric(Decimal.to_integer(Decimal.round(cents, 0)), len)
    else
      raise ArgumentError, "amount has more than two decimals: #{Decimal.to_string(amount)}"
    end
  end

  @doc """
  Formats a settlement date as `JJMMA` — day, month, and the **single trailing
  digit of the year**, per the CFONB 160 spec. A `nil` date yields five spaces.
  """
  @spec date_jjmma(Date.t() | nil) :: String.t()
  def date_jjmma(nil), do: String.duplicate(" ", 5)

  def date_jjmma(%Date{year: year, month: month, day: day}) do
    pad2(day) <> pad2(month) <> Integer.to_string(rem(year, 10))
  end

  @doc """
  Uppercases, strips accents, and replaces any character outside the permitted
  CFONB set with a space. `nil` becomes an empty string.
  """
  @spec sanitize(String.t() | nil) :: String.t()
  def sanitize(nil), do: ""

  def sanitize(value) when is_binary(value) do
    value
    |> String.upcase()
    |> String.normalize(:nfd)
    |> String.replace(@diacritics, "")
    |> String.replace(@allowed, " ")
  end

  @doc """
  A reserved zone of `len` spaces.
  """
  @spec blank(non_neg_integer) :: String.t()
  def blank(len), do: String.duplicate(" ", len)

  defp pad2(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
