defmodule CFONB.VirementTest do
  use ExUnit.Case, async: true

  alias CFONB.{Encode, Rib}
  alias CFONB.Virement
  alias CFONB.Virement.Beneficiaire

  describe "CFONB.Encode" do
    test "numeric right-aligns and zero-fills" do
      assert Encode.numeric(305, 5) == "00305"
      assert Encode.numeric("20041", 5) == "20041"
      assert Encode.numeric("", 4) == "0000"
    end

    test "numeric rejects overflow and non-digits" do
      assert_raise ArgumentError, fn -> Encode.numeric(123_456, 5) end
      assert_raise ArgumentError, fn -> Encode.numeric("12A", 5) end
    end

    test "alpha left-aligns, space-fills, truncates and sanitizes" do
      assert Encode.alpha("ACME", 8) == "ACME    "
      assert Encode.alpha("VERY LONG NAME HERE OK!!", 10) == "VERY LONG "
      assert Encode.alpha(nil, 3) == "   "
      assert Encode.alpha("Café", 5) == "CAFE "
    end

    test "centimes encodes euros as unsigned integer cents" do
      assert Encode.centimes(Decimal.new("12.34")) == "0000000000001234"
      assert Encode.centimes(Decimal.new("0")) == "0000000000000000"
      assert Encode.centimes(Decimal.new("1000000")) == "0000000100000000"
    end

    test "centimes rejects negative amounts and more than two decimals" do
      assert_raise ArgumentError, fn -> Encode.centimes(Decimal.new("-1")) end
      assert_raise ArgumentError, fn -> Encode.centimes(Decimal.new("1.234")) end
    end

    test "date_jjmma keeps only the trailing year digit, nil is blank" do
      assert Encode.date_jjmma(~D[2026-07-09]) == "09076"
      assert Encode.date_jjmma(~D[2004-12-31]) == "31124"
      assert Encode.date_jjmma(nil) == "     "
    end

    test "sanitize uppercases, strips accents and drops forbidden characters" do
      assert Encode.sanitize("Éléphant #1 (test)") == "ELEPHANT  1 (TEST)"
      assert Encode.sanitize(nil) == ""
    end
  end

  describe "CFONB.Rib.from_iban/1" do
    test "decomposes a valid French IBAN and verifies its key" do
      assert {:ok, %{bank: "20041", branch: "01005", account: "0500013M026", key: "06"}} =
               Rib.from_iban("FR1420041010050500013M02606")
    end

    test "ignores spaces" do
      assert {:ok, %{bank: "20041"}} = Rib.from_iban("FR14 2004 1010 0505 0001 3M02 606")
    end

    test "rejects a wrong IBAN check digit" do
      assert {:error, {:invalid_iban_check, _}} = Rib.from_iban("FR9920041010050500013M02606")
    end

    test "rejects a non-French or malformed IBAN" do
      assert {:error, {:invalid_iban, _}} = Rib.from_iban("DE89370400440532013000")
      assert {:error, {:invalid_iban, _}} = Rib.from_iban("FR14")
    end
  end

  describe "Virement.encode/2 — golden output" do
    setup do
      order = %Virement{
        numero_emetteur: "123456",
        nom_emetteur: "ACME",
        etablissement: "30004",
        guichet: "00003",
        compte: "12345678901",
        beneficiaires: [
          %Beneficiaire{
            nom: "JEAN DUPONT",
            etablissement: "20041",
            guichet: "01005",
            compte: "0500013M026",
            montant: Decimal.new("1250.00"),
            libelle: "SALAIRE",
            reference: "REF1"
          }
        ]
      }

      {:ok, order: order}
    end

    test "produces the exact 03/06/08 records", %{order: order} do
      assert {:ok, %{file: file, total: total}} = Virement.encode(order)

      assert Decimal.equal?(total, Decimal.new("1250.00"))

      expected =
        Enum.join(
          [
            "0302        123456            ACME                                              E     0000312345678901                                               30004      ",
            "0602        123456REF1        JEAN DUPONT                                             010050500013M0260000000000125000SALAIRE                        20041      ",
            "0802        123456                                                                                    0000000000125000                                          "
          ],
          "\r\n"
        )

      assert file == expected
    end

    test "every record is exactly 160 characters", %{order: order} do
      assert {:ok, %{file: file}} = Virement.encode(order)

      for line <- String.split(file, "\r\n") do
        assert byte_size(line) == 160
      end
    end

    test "fields land at their documented positions", %{order: order} do
      assert {:ok, %{file: file}} = Virement.encode(order)
      [emetteur, beneficiaire, total] = String.split(file, "\r\n")

      # Émetteur (03)
      assert String.slice(emetteur, 0, 2) == "03"
      assert String.slice(emetteur, 2, 2) == "02"
      assert String.slice(emetteur, 12, 6) == "123456"
      assert String.slice(emetteur, 80, 1) == "E"
      assert String.slice(emetteur, 86, 5) == "00003"
      assert String.slice(emetteur, 91, 11) == "12345678901"
      assert String.slice(emetteur, 149, 5) == "30004"

      # Destinataire (06)
      assert String.slice(beneficiaire, 0, 2) == "06"
      assert String.slice(beneficiaire, 86, 5) == "01005"
      assert String.slice(beneficiaire, 91, 11) == "0500013M026"
      assert String.slice(beneficiaire, 102, 16) == "0000000000125000"
      assert String.slice(beneficiaire, 149, 5) == "20041"

      # Total (08)
      assert String.slice(total, 0, 2) == "08"
      assert String.slice(total, 102, 16) == "0000000000125000"
    end

    test "accepts a custom line separator", %{order: order} do
      assert {:ok, %{file: file}} = Virement.encode(order, separator: "\n")
      refute String.contains?(file, "\r\n")
      assert length(String.split(file, "\n")) == 3
    end
  end

  describe "Virement.encode/2 — IBAN input and totals" do
    test "resolves IBANs and sums multiple beneficiaries in the 08 record" do
      order = %Virement{
        numero_emetteur: "999000",
        nom_emetteur: "PAYER SA",
        iban: "FR1420041010050500013M02606",
        beneficiaires: [
          %Beneficiaire{
            nom: "A",
            iban: "FR1420041010050500013M02606",
            montant: Decimal.new("100.00")
          },
          %Beneficiaire{
            nom: "B",
            iban: "FR1420041010050500013M02606",
            montant: Decimal.new("50.55")
          }
        ]
      }

      assert {:ok, %{file: file, total: total}} = Virement.encode(order)
      assert Decimal.equal?(total, Decimal.new("150.55"))

      total_line = file |> String.split("\r\n") |> List.last()
      assert String.slice(total_line, 102, 16) == "0000000000015055"
    end
  end

  describe "Virement.encode/2 — validation errors" do
    defp order_with(beneficiaires, overrides \\ %{}) do
      base = %Virement{
        nom_emetteur: "X",
        etablissement: "30004",
        guichet: "00003",
        compte: "12345678901",
        beneficiaires: beneficiaires
      }

      struct(base, overrides)
    end

    defp beneficiaire(montant) do
      %Beneficiaire{
        nom: "A",
        etablissement: "30004",
        guichet: "00003",
        compte: "12345678901",
        montant: montant
      }
    end

    test "rejects an empty beneficiary list" do
      assert {:error, :no_beneficiaire} = Virement.encode(order_with([]))
    end

    test "rejects an unsupported operation code" do
      order = order_with([beneficiaire(Decimal.new("1"))], %{code_operation: "76"})
      assert {:error, {:unsupported_operation, "76"}} = Virement.encode(order)
    end

    test "rejects a non-positive amount" do
      assert {:error, {:non_positive_amount, _}} =
               Virement.encode(order_with([beneficiaire(Decimal.new("0"))]))

      assert {:error, {:non_positive_amount, _}} =
               Virement.encode(order_with([beneficiaire(Decimal.new("-5"))]))
    end

    test "rejects an amount with more than two decimals" do
      assert {:error, {:too_many_decimals, _}} =
               Virement.encode(order_with([beneficiaire(Decimal.new("1.234"))]))
    end

    test "rejects an IBAN with an invalid check digit" do
      order = %Virement{
        nom_emetteur: "X",
        iban: "FR9920041010050500013M02606",
        beneficiaires: [beneficiaire(Decimal.new("1"))]
      }

      assert {:error, {:invalid_iban_check, _}} = Virement.encode(order)
    end

    test "rejects missing bank coordinates" do
      order = %Virement{nom_emetteur: "X", beneficiaires: [beneficiaire(Decimal.new("1"))]}
      assert {:error, :missing_bank_coordinates} = Virement.encode(order)
    end

    test "rejects an over-length account number instead of truncating it" do
      benef = %{beneficiaire(Decimal.new("1")) | compte: "123456789012"}

      assert {:error, {:account_too_long, "123456789012"}} = Virement.encode(order_with([benef]))
    end

    test "rejects an empty or charset-invalid account instead of emitting it blank/corrupted" do
      empty = %{beneficiaire(Decimal.new("1")) | compte: ""}
      assert {:error, {:invalid_account, ""}} = Virement.encode(order_with([empty]))

      corrupt = %{beneficiaire(Decimal.new("1")) | compte: "12345#789"}
      assert {:error, {:invalid_account, "12345#789"}} = Virement.encode(order_with([corrupt]))
    end

    test "rejects a missing or blank name (zone C2 is mandatory)" do
      assert {:error, {:missing_name, :nom_emetteur}} =
               Virement.encode(order_with([beneficiaire(Decimal.new("1"))], %{nom_emetteur: nil}))

      assert {:error, {:missing_name, :beneficiaire}} =
               Virement.encode(order_with([%{beneficiaire(Decimal.new("1")) | nom: "  "}]))
    end

    test "rejects an over-length or non-string numero_emetteur instead of truncating/crashing" do
      order = order_with([beneficiaire(Decimal.new("1"))], %{numero_emetteur: "1234567"})
      assert {:error, {:numero_emetteur_too_long, "1234567"}} = Virement.encode(order)

      order = order_with([beneficiaire(Decimal.new("1"))], %{numero_emetteur: 123_456})
      assert {:error, {:invalid_field, :numero_emetteur}} = Virement.encode(order)
    end

    test "rejects amounts whose cents overflow the 16-digit zone, and overflowing totals" do
      huge = beneficiaire(Decimal.new("100000000000000"))
      assert {:error, {:amount_too_large, _}} = Virement.encode(order_with([huge]))

      # Each fits the zone, but their 08-record sum does not.
      big = Decimal.new("60000000000000")
      order = order_with([beneficiaire(big), beneficiaire(big)])
      assert {:error, {:total_too_large, _}} = Virement.encode(order)
    end

    test "rejects contradictory bank coordinates (both IBAN and split RIB)" do
      order =
        order_with([beneficiaire(Decimal.new("1"))], %{iban: "FR1420041010050500013M02606"})

      assert {:error, :ambiguous_bank_coordinates} = Virement.encode(order)
    end

    test "rejects a non-string optional text field instead of crashing" do
      benef = %{beneficiaire(Decimal.new("1")) | libelle: 42}
      assert {:error, {:invalid_field, :libelle}} = Virement.encode(order_with([benef]))
    end
  end

  describe "Virement.encode!/2" do
    test "returns the file directly on success" do
      assert is_binary(Virement.encode!(order_with([beneficiaire(Decimal.new("1"))])))
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, fn ->
        Virement.encode!(%Virement{nom_emetteur: "X", beneficiaires: []})
      end
    end
  end
end
