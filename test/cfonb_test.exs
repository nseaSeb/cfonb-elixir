defmodule CFONBTest do
  use ExUnit.Case, async: true

  doctest CFONB

  @example File.read!(Path.join(__DIR__, "fixtures/example.txt"))

  describe "parse/1 on the reference CFONB 120 file" do
    setup do
      {:ok, statements} = CFONB.parse(@example)
      %{statements: statements}
    end

    test "returns the two statements", %{statements: statements} do
      assert length(statements) == 2
    end

    test "parses the first statement header", %{statements: [statement | _]} do
      assert statement.bank == "15589"
      assert statement.branch == "00000"
      assert statement.currency == "EUR"
      assert statement.account == "98765432100"
      assert statement.from == ~D[2019-05-15]
      assert statement.to == ~D[2019-05-16]
      assert Decimal.equal?(statement.from_balance, Decimal.new("-190.40"))
      assert Decimal.equal?(statement.to_balance, Decimal.new("-241.21"))
    end

    test "new balance = old balance + sum of operations", %{statements: [statement | _]} do
      total =
        Enum.reduce(statement.operations, statement.from_balance, fn op, acc ->
          Decimal.add(acc, op.amount)
        end)

      assert Decimal.equal?(total, statement.to_balance)
    end

    test "parses the first operation", %{statements: [statement | _]} do
      assert length(statement.operations) == 3
      [operation | _] = statement.operations

      assert Decimal.equal?(operation.amount, Decimal.new("-32.21"))
      assert operation.currency == "EUR"
      assert operation.date == ~D[2019-05-16]
      assert operation.value_date == ~D[2019-05-16]
      assert operation.label == "PRLV SEPA TEST CABINET"
      assert operation.interbank_code == "B1"
      assert operation.internal_code == "9162"
    end

    test "decodes 05 detail lines into structured fields", %{statements: [statement | _]} do
      [operation | _] = statement.operations
      details = operation.details

      # LIB repeated twice -> concatenated
      assert details.free_label == "MENSUEAUHTR13133\nMENSUEAUHTR13DUP"
      # REF -> operation_reference
      assert details.operation_reference == "REFERENCE"
      # RCN -> client_reference + purpose
      assert details.client_reference == "OTHER REFERENCE"
      assert details.purpose == "PURPOSE"
      # NPY -> debtor
      assert details.debtor == "INTERNET SFR"
    end

    test "keeps unrecognized qualifiers under :unknown (concatenating repeats)",
         %{statements: [statement | _]} do
      details = statement.operations |> hd() |> Map.fetch!(:details)

      assert details.unknown["AAA"] == "INTERNETA AAA\nINTERNETA ABB"
      assert details.unknown["BBB"] == "INTERNETE BBB"
      assert Map.has_key?(details.unknown, "N Y")
    end
  end

  describe "rich 05 decoding (synthetic records)" do
    alias CFONB.Operation.Details

    test "FEE decodes currency and a scaled decimal amount" do
      # currency "EUR" | scale "2" | 14-digit amount "00000000000079"
      info = pad70("EUR200000000000079")
      details = Details.merge(%Details{}, "FEE", info)

      assert details.fee_currency == "EUR"
      assert Decimal.equal?(details.fee, Decimal.new("0.79"))
    end

    test "MMO decodes original amount and optional exchange rate" do
      # currency "USD" | scale "2" | amount(14) "00000000012345" |
      # rate scale "4" at pos 18 | rate(4) "1082" at pos 26
      info = pad70("USD200000000012345" <> "4" <> String.duplicate(" ", 7) <> "1082")
      details = Details.merge(%Details{}, "MMO", info)

      assert details.original_currency == "USD"
      assert Decimal.equal?(details.original_amount, Decimal.new("123.45"))
      assert Decimal.equal?(details.exchange_rate, Decimal.new("0.1082"))
    end
  end

  describe "120-char padding" do
    test "a record whose trailing padding was stripped is still parsed" do
      lines = String.split(@example, "\n")
      previous_balance = lines |> Enum.at(0) |> String.trim_trailing()
      new_balance = lines |> Enum.at(20) |> String.trim_trailing()

      # trailing spaces really were stripped
      assert byte_size(previous_balance) < 120

      input = previous_balance <> "\n" <> new_balance
      assert {:ok, [statement]} = CFONB.parse(input)
      assert statement.operations == []
      assert Decimal.equal?(statement.from_balance, Decimal.new("-190.40"))
      assert Decimal.equal?(statement.to_balance, Decimal.new("-241.21"))
    end
  end

  describe "structural errors" do
    test "an operation before any statement is an error" do
      operation_line = @example |> String.split("\n") |> Enum.at(2)
      assert {:error, :operation_outside_statement} = CFONB.parse(operation_line)
    end

    test "an unknown record code is an error" do
      assert {:error, {:invalid_record_code, "99"}} = CFONB.parse(String.duplicate("9", 120))
    end

    test "empty input parses to no statements" do
      assert {:ok, []} = CFONB.parse("")
    end
  end

  # Pads a detail info zone to its fixed 70-char width.
  defp pad70(string), do: string <> String.duplicate(" ", 70 - byte_size(string))
end
