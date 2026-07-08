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

    test "attaches 05 detail lines to their operation", %{statements: [statement | _]} do
      [operation | _] = statement.operations

      assert length(operation.details) > 0
      assert Enum.any?(operation.details, &(&1.qualifier == "LIB"))
      assert Enum.any?(operation.details, &(&1.qualifier == "REF"))
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
end
