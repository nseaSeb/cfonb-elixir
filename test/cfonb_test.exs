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

    test "FEE with a non-digit scale falls back to unknown instead of crashing" do
      details = Details.merge(%Details{}, "FEE", pad70("EURX0000000000079"))

      assert details.fee == nil
      assert details.fee_currency == nil
      assert details.unknown["FEE"] =~ "EURX"
    end

    test "FEE with a blank amount does not invent a 0.00 fee" do
      details = Details.merge(%Details{}, "FEE", pad70("EUR2"))

      assert details.fee == nil
      assert Map.has_key?(details.unknown, "FEE")
    end

    test "MMO with a non-digit amount falls back to unknown instead of crashing" do
      details = Details.merge(%Details{}, "MMO", pad70("USD20000000000Z345"))

      assert details.original_amount == nil
      assert Map.has_key?(details.unknown, "MMO")
    end
  end

  describe "Ruby-parity features" do
    setup do
      {:ok, [statement | _]} = CFONB.parse(@example)
      %{statement: statement}
    end

    test "rib/1 produces a valid 23-char French RIB", %{statement: statement} do
      rib = CFONB.Statement.rib(statement)
      assert String.length(rib) == 23

      <<bank::binary-size(5), branch::binary-size(5), account::binary-size(11),
        key::binary-size(2)>> = rib

      # RIB control key: (89*bank + 15*branch + 3*account + key) mod 97 == 0
      checksum =
        89 * String.to_integer(bank) + 15 * String.to_integer(branch) +
          3 * String.to_integer(account) + String.to_integer(key)

      assert rem(checksum, 97) == 0
    end

    test "iban/1 produces a valid French IBAN", %{statement: statement} do
      iban = CFONB.Statement.iban(statement)

      assert String.starts_with?(iban, "FR")
      assert String.ends_with?(iban, CFONB.Statement.rib(statement))

      # ISO 7064 mod-97-10: move the first 4 chars to the end, convert letters,
      # the whole number mod 97 must equal 1.
      <<head::binary-size(4), rest::binary>> = iban

      numeric =
        (rest <> head)
        |> String.to_charlist()
        |> Enum.map_join("", fn
          char when char in ?A..?Z -> Integer.to_string(char - 55)
          char -> <<char>>
        end)

      assert rem(String.to_integer(numeric), 97) == 1
    end

    test "type_code/1 is the interbank code plus C/D direction", %{statement: statement} do
      [operation | _] = statement.operations
      # interbank code "B1", debit (negative amount) -> "D"
      assert CFONB.Operation.type_code(operation) == "B1D"
    end

    test "raw fields preserve the original record lines", %{statement: statement} do
      assert String.starts_with?(statement.begin_raw, "01")
      assert String.length(statement.begin_raw) == 120
      assert String.starts_with?(statement.end_raw, "07")

      [operation | _] = statement.operations
      assert String.starts_with?(operation.raw, "04")
      # the 04 line plus its twelve 05 detail lines
      assert operation.raw |> String.split("\n") |> length() == 13

      # Statement.raw/1 rebuilds a bundle bounded by the balance lines
      bundle = CFONB.Statement.raw(statement)
      assert String.starts_with?(bundle, statement.begin_raw)
      assert String.ends_with?(bundle, statement.end_raw)
    end

    test "parse_operation/1 parses a standalone operation with its details" do
      op_input = @example |> String.split("\n") |> Enum.slice(2, 13) |> Enum.join("\n")

      assert {:ok, operation} = CFONB.parse_operation(op_input)
      assert Decimal.equal?(operation.amount, Decimal.new("-32.21"))
      assert operation.details.operation_reference == "REFERENCE"
    end

    test "optimistic: true skips invalid records instead of aborting" do
      stray = @example |> String.split("\n") |> Enum.at(2)
      input = stray <> "\n" <> @example

      assert {:error, :operation_outside_statement} = CFONB.parse(input)
      assert {:ok, statements} = CFONB.parse(input, optimistic: true)
      assert length(statements) == 2
    end
  end

  describe "RIB / IBAN on the canonical example (with a letter in the account)" do
    # Canonical French example: IBAN FR1420041010050500013M02606
    @canonical %CFONB.Statement{bank: "20041", branch: "01005", account: "0500013M026"}

    test "rib/1 matches the reference RIB" do
      assert CFONB.Statement.rib(@canonical) == "20041010050500013M02606"
    end

    test "iban/1 matches the reference IBAN" do
      assert CFONB.Statement.iban(@canonical) == "FR1420041010050500013M02606"
    end

    test "rib/1 and iban/1 raise a clear error when no RIB is derivable" do
      blank_bank = %CFONB.Statement{bank: "", branch: "01005", account: "0500013M026"}

      assert_raise ArgumentError, ~r/cannot derive a RIB key/, fn ->
        CFONB.Statement.rib(blank_bank)
      end

      dashed_account = %CFONB.Statement{bank: "20041", branch: "01005", account: "050-0013M02"}

      assert_raise ArgumentError, ~r/cannot derive a RIB key/, fn ->
        CFONB.Statement.iban(dashed_account)
      end
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

  describe "malformed numeric zones return errors (never raise)" do
    test "a non-digit date is an error, and optimistic parsing skips it" do
      record = balance_rec("01", date: "31XX26")

      assert {:error, {:invalid_date, "31XX26"}} = CFONB.parse(record)
      assert {:ok, []} = CFONB.parse(record, optimistic: true)
    end

    test "a non-digit scale is an error" do
      assert {:error, {:invalid_scale, "X"}} = CFONB.parse(balance_rec("01", scale: "X"))
    end

    test "non-digit amount digits are an error" do
      assert {:error, {:invalid_amount, _}} =
               CFONB.parse(balance_rec("01", amount: "000000000A904{"))
    end

    test "a non-digit entry number is an error" do
      assert {:error, {:invalid_number, "ABC1234"}} =
               CFONB.parse(operation_rec(number: "ABC1234"))
    end

    test "a malformed 05 FEE record no longer aborts an optimistic parse" do
      file =
        Enum.join(
          [
            balance_rec("01"),
            operation_rec(),
            detail_rec("FEE", "EURX0000000000079"),
            balance_rec("07")
          ],
          "\n"
        )

      assert {:ok, [statement]} = CFONB.parse(file, optimistic: true)
      assert [operation] = statement.operations
      assert operation.details.fee == nil
      assert Map.has_key?(operation.details.unknown, "FEE")
    end
  end

  describe "long physical lines" do
    test "a non-multiple-of-120 tail surfaces as an invalid record instead of vanishing" do
      line = balance_rec("01") <> balance_rec("07") <> String.duplicate("Z", 30)

      assert {:error, {:invalid_record_code, "ZZ"}} = CFONB.parse(line)
      assert {:ok, [%CFONB.Statement{}]} = CFONB.parse(line, optimistic: true)
    end

    test "an all-blank tail is treated as producer padding" do
      line = balance_rec("01") <> balance_rec("07") <> String.duplicate(" ", 30)

      assert {:ok, [%CFONB.Statement{}]} = CFONB.parse(line)
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

  # Synthetic 120-char records with malformed-zone overrides.
  defp balance_rec(code, opts \\ []) do
    scale = Keyword.get(opts, :scale, "2")
    date = Keyword.get(opts, :date, "090726")
    amount = Keyword.get(opts, :amount, "0000000001904{")

    code <>
      "20041" <>
      "    " <>
      "01005" <>
      "EUR" <>
      scale <>
      " " <>
      "0500013M026" <>
      "  " <>
      date <>
      String.duplicate(" ", 50) <>
      amount <>
      String.duplicate(" ", 16)
  end

  defp operation_rec(opts \\ []) do
    number = Keyword.get(opts, :number, "0000001")

    "04" <>
      "20041" <>
      "B1  " <>
      "01005" <>
      "EUR" <>
      "2" <>
      " " <>
      "0500013M026" <>
      "B1" <>
      "090726" <>
      "  " <>
      "090726" <>
      String.pad_trailing("TEST", 32) <>
      " " <> number <> " " <> " " <> "0000000001904{" <> String.duplicate(" ", 16)
  end

  defp detail_rec(qualifier, info) do
    "05" <>
      "20041" <>
      "B1  " <>
      "01005" <>
      "EUR" <>
      "2" <>
      " " <>
      "0500013M026" <>
      "B1" <>
      "090726" <>
      String.duplicate(" ", 5) <>
      qualifier <> (info <> String.duplicate(" ", 70 - byte_size(info))) <> "  "
  end
end
