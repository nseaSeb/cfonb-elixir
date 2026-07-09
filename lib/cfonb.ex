defmodule CFONB do
  @moduledoc """
  Parser for CFONB bank files (French banking standard, *Comité Français
  d'Organisation et de Normalisation Bancaires*).

  This first version handles the **120-character account statement** (relevé de
  compte), made of four fixed-width record types:

    * `01` — previous balance (ancien solde)
    * `04` — operation / movement (mouvement)
    * `05` — operation detail (complément), optional and repeatable
    * `07` — new balance (nouveau solde)

  See `FORMAT.md` for the exact field layout, and `CFONB.Statement` /
  `CFONB.Operation` for the returned structs.

  ## Example

      {:ok, [statement | _]} = CFONB.parse(File.read!("releve.txt"))
      statement.from_balance
      #=> #Decimal<-190.40>

  Inspired by the [Ruby `cfonb` gem](https://github.com/pennylane-hq/cfonb)
  (MIT). Reimplemented from the official CFONB specification, with a
  compatible data model.
  """

  alias CFONB.{Operation, Statement}

  @record_size 120

  # Last character of a 14-char amount field carries the units digit and the
  # sign (CFONB/AFB "montant signé" encoding).
  @amount_specifiers %{
    "{" => {1, 0},
    "A" => {1, 1},
    "B" => {1, 2},
    "C" => {1, 3},
    "D" => {1, 4},
    "E" => {1, 5},
    "F" => {1, 6},
    "G" => {1, 7},
    "H" => {1, 8},
    "I" => {1, 9},
    "}" => {-1, 0},
    "J" => {-1, 1},
    "K" => {-1, 2},
    "L" => {-1, 3},
    "M" => {-1, 4},
    "N" => {-1, 5},
    "O" => {-1, 6},
    "P" => {-1, 7},
    "Q" => {-1, 8},
    "R" => {-1, 9}
  }

  @doc """
  Parses the content of a CFONB 120 file into a list of `CFONB.Statement`.

  Returns `{:ok, statements}` or `{:error, reason}`.

  ## Options

    * `:optimistic` (default `false`) — when `true`, invalid records are skipped
      instead of aborting, and whatever statements could be built are returned.
  """
  @spec parse(binary, keyword) :: {:ok, [Statement.t()]} | {:error, term}
  def parse(input, opts \\ []) when is_binary(input) do
    input
    |> records()
    |> reduce(%{statements: [], statement: nil, operation: nil}, optimistic?(opts))
  end

  @doc """
  Parses a standalone operation (`04` and its `05` details, without a
  surrounding statement) into a single `CFONB.Operation`.

  Returns `{:ok, operation}` (or `{:ok, nil}` if the input has none), or
  `{:error, reason}`. Accepts the same `:optimistic` option as `parse/2`.
  """
  @spec parse_operation(binary, keyword) :: {:ok, Operation.t() | nil} | {:error, term}
  def parse_operation(input, opts \\ []) when is_binary(input) do
    input
    |> records()
    |> reduce_operation(nil, optimistic?(opts))
  end

  @doc """
  Same as `parse/2` but raises `ArgumentError` on invalid input.
  """
  @spec parse!(binary, keyword) :: [Statement.t()]
  def parse!(input, opts \\ []) do
    case parse(input, opts) do
      {:ok, statements} -> statements
      {:error, reason} -> raise ArgumentError, "invalid CFONB input: #{inspect(reason)}"
    end
  end

  @doc """
  Same as `parse_operation/2` but raises `ArgumentError` on invalid input.
  """
  @spec parse_operation!(binary, keyword) :: Operation.t() | nil
  def parse_operation!(input, opts \\ []) do
    case parse_operation(input, opts) do
      {:ok, operation} -> operation
      {:error, reason} -> raise ArgumentError, "invalid CFONB operation: #{inspect(reason)}"
    end
  end

  defp optimistic?(opts), do: Keyword.get(opts, :optimistic, false)

  ## ----------------------------------------------------------------------------
  ## Splitting into 120-char records (padding-tolerant)
  ## ----------------------------------------------------------------------------

  defp records(input) do
    input
    |> String.split(["\r\n", "\n", "\r"])
    |> Enum.flat_map(&to_records/1)
  end

  # Blank lines are ignored. A single record shorter than 120 chars (trailing
  # padding spaces stripped by some producers) is right-padded back to 120.
  # A line that concatenates several records is split every 120 chars.
  defp to_records(line) do
    cond do
      String.trim(line) == "" -> []
      byte_size(line) <= @record_size -> [pad(line)]
      true -> chunk_records(line)
    end
  end

  defp chunk_records(<<record::binary-size(@record_size), rest::binary>>) do
    [record | chunk_records(rest)]
  end

  # A trailing partial chunk is producer padding when blank; otherwise it is
  # kept (padded) so strict parsing surfaces it as an invalid record instead
  # of silently dropping data.
  defp chunk_records(rest) do
    if String.trim(rest) == "", do: [], else: [pad(rest)]
  end

  defp pad(line) when byte_size(line) < @record_size do
    line <> String.duplicate(" ", @record_size - byte_size(line))
  end

  defp pad(line), do: line

  ## ----------------------------------------------------------------------------
  ## Stateful reduction over records
  ## ----------------------------------------------------------------------------

  # End of input: return completed statements. Any statement left open (no `07`)
  # is dropped, matching the reference implementation.
  defp reduce([], %{statements: acc}, _optimistic), do: {:ok, Enum.reverse(acc)}

  defp reduce([record | rest], state, optimistic) do
    result =
      with {:ok, parsed} <- parse_record(record) do
        step(parsed, state)
      end

    case result do
      {:ok, state} -> reduce(rest, state, optimistic)
      {:error, _reason} when optimistic -> reduce(rest, state, optimistic)
      {:error, _reason} = error -> error
    end
  end

  defp reduce_operation([], operation, _optimistic), do: {:ok, operation}

  defp reduce_operation([record | rest], operation, optimistic) do
    result =
      with {:ok, parsed} <- parse_record(record) do
        operation_step(parsed, operation)
      end

    case result do
      {:ok, operation} -> reduce_operation(rest, operation, optimistic)
      {:error, _reason} when optimistic -> reduce_operation(rest, operation, optimistic)
      {:error, _reason} = error -> error
    end
  end

  defp operation_step({:operation, _}, %Operation{}), do: {:error, :operation_already_defined}
  defp operation_step({:operation, fields}, nil), do: {:ok, Operation.new(fields)}
  defp operation_step({:detail, _}, nil), do: {:error, :detail_outside_operation}

  defp operation_step({:detail, detail}, operation),
    do: {:ok, Operation.add_detail(operation, detail)}

  defp operation_step({_kind, _}, _operation), do: {:error, :unhandled_line_code}

  defp step({:previous_balance, fields}, %{statement: nil} = state) do
    {:ok, %{state | statement: Statement.new(fields), operation: nil}}
  end

  defp step({:previous_balance, _}, _state), do: {:error, :unterminated_statement}

  defp step({:operation, _}, %{statement: nil}), do: {:error, :operation_outside_statement}

  defp step({:operation, fields}, state) do
    statement = push_operation(state.statement, state.operation)
    {:ok, %{state | statement: statement, operation: Operation.new(fields)}}
  end

  defp step({:detail, _}, %{operation: nil}), do: {:error, :detail_outside_operation}

  defp step({:detail, detail}, state) do
    {:ok, %{state | operation: Operation.add_detail(state.operation, detail)}}
  end

  defp step({:new_balance, _}, %{statement: nil}), do: {:error, :new_balance_outside_statement}

  defp step({:new_balance, fields}, state) do
    statement =
      state.statement
      |> push_operation(state.operation)
      |> Statement.close(fields)

    {:ok, %{state | statements: [statement | state.statements], statement: nil, operation: nil}}
  end

  defp push_operation(statement, nil), do: statement

  defp push_operation(statement, %Operation{} = operation) do
    %{statement | operations: statement.operations ++ [operation]}
  end

  ## ----------------------------------------------------------------------------
  ## Record parsing (binary pattern matching on the fixed 120-char layout)
  ## ----------------------------------------------------------------------------

  defp parse_record(<<code::binary-size(2), _::binary>> = record) do
    parse_record(code, record)
  end

  defp parse_record("01", record), do: balance(:previous_balance, record)
  defp parse_record("07", record), do: balance(:new_balance, record)
  defp parse_record("04", record), do: operation(record)
  defp parse_record("05", record), do: detail(record)
  defp parse_record(code, _record), do: {:error, {:invalid_record_code, code}}

  # Records 01 and 07 share the same layout.
  defp balance(kind, record) do
    <<_code::binary-size(2), bank::binary-size(5), _internal::binary-size(4),
      branch::binary-size(5), currency::binary-size(3), scale::binary-size(1),
      _reserved::binary-size(1), account::binary-size(11), _reserved2::binary-size(2),
      date::binary-size(6), _reserved3::binary-size(50), amount::binary-size(14),
      _reserved4::binary-size(16)>> = record

    with {:ok, scale} <- decode_int(scale, {:invalid_scale, scale}),
         {:ok, date} <- decode_date(date),
         {:ok, amount} <- decode_amount(amount, scale) do
      {:ok,
       {kind,
        %{
          bank: trim(bank),
          branch: trim(branch),
          currency: trim(currency),
          account: trim(account),
          date: date,
          amount: amount,
          raw: record
        }}}
    end
  end

  defp operation(record) do
    <<_code::binary-size(2), bank::binary-size(5), internal::binary-size(4),
      branch::binary-size(5), currency::binary-size(3), scale::binary-size(1),
      _reserved::binary-size(1), account::binary-size(11), interbank::binary-size(2),
      date::binary-size(6), rejection::binary-size(2), value_date::binary-size(6),
      label::binary-size(32), _reserved2::binary-size(1), number::binary-size(7),
      exoneration::binary-size(1), unavailability::binary-size(1), amount::binary-size(14),
      reference::binary-size(16)>> = record

    with {:ok, scale} <- decode_int(scale, {:invalid_scale, scale}),
         {:ok, number} <- decode_int(number, {:invalid_number, number}),
         {:ok, date} <- decode_date(date),
         {:ok, value_date} <- decode_date(value_date),
         {:ok, amount} <- decode_amount(amount, scale) do
      {:ok,
       {:operation,
        %{
          bank: trim(bank),
          branch: trim(branch),
          currency: trim(currency),
          account: trim(account),
          internal_code: trim(internal),
          interbank_code: trim(interbank),
          rejection_code: trim(rejection),
          date: date,
          value_date: value_date,
          label: trim(label),
          number: number,
          exoneration_code: trim(exoneration),
          unavailability_code: trim(unavailability),
          amount: amount,
          reference: trim(reference),
          raw: record
        }}}
    end
  end

  defp detail(record) do
    <<_code::binary-size(2), _bank::binary-size(5), _internal::binary-size(4),
      _branch::binary-size(5), _currency::binary-size(3), _scale::binary-size(1),
      _reserved::binary-size(1), _account::binary-size(11), _interbank::binary-size(2),
      _date::binary-size(6), _reserved2::binary-size(5), qualifier::binary-size(3),
      info::binary-size(70), _reserved3::binary-size(2)>> = record

    # `info` is kept raw (70 chars): qualifier-specific decoders slice it by
    # position. See `CFONB.Operation.Details`.
    {:ok, {:detail, %{qualifier: trim(qualifier), info: info, raw: record}}}
  end

  ## ----------------------------------------------------------------------------
  ## Field decoding
  ## ----------------------------------------------------------------------------

  # Amount: 13 digits + 1 sign/units specifier, scaled by the record's decimals.
  defp decode_amount(<<digits::binary-size(13), specifier::binary-size(1)>>, scale) do
    case @amount_specifiers do
      %{^specifier => {sign, last_digit}} ->
        with {:ok, units} <- decode_int(digits, {:invalid_amount, digits}) do
          {:ok, %Decimal{sign: sign, coef: units * 10 + last_digit, exp: -scale}}
        end

      _ ->
        {:error, {:invalid_amount_specifier, specifier}}
    end
  end

  # Date: JJMMAA. Two-digit year pivots at 60 (>60 => 19xx, else 20xx), matching
  # the reference implementation. A blank field is a valid absence (`nil`).
  defp decode_date(<<_::binary-size(6)>> = raw) do
    case String.trim(raw) do
      "" ->
        {:ok, nil}

      _ ->
        <<day::binary-size(2), month::binary-size(2), year::binary-size(2)>> = raw

        with {:ok, day} <- decode_int(day, {:invalid_date, raw}),
             {:ok, month} <- decode_int(month, {:invalid_date, raw}),
             {:ok, year} <- decode_int(year, {:invalid_date, raw}) do
          full_year = if year > 60, do: 1900 + year, else: 2000 + year

          case Date.new(full_year, month, day) do
            {:ok, date} -> {:ok, date}
            {:error, _} -> {:error, {:invalid_date, raw}}
          end
        end
    end
  end

  defp trim(binary), do: String.trim(binary)

  # Numeric zones: blank counts as 0 (zero-filled by producers, sometimes left
  # blank); anything else must be all digits — a raise here would escape the
  # {:ok, _} | {:error, _} contract and defeat `optimistic` parsing.
  defp decode_int(binary, error) do
    case String.trim(binary) do
      "" ->
        {:ok, 0}

      digits ->
        if digits =~ ~r/^\d+$/, do: {:ok, String.to_integer(digits)}, else: {:error, error}
    end
  end
end
