defmodule CFONB.Virement do
  @moduledoc """
  Emits a CFONB **160-character transfer order** (ordre de virement) — a file
  *sent to* the bank, the counterpart of the 120 statement this library parses.

  A remise (batch) is made of one émetteur record (`03`, the donneur d'ordre),
  one destinataire record (`06`) per beneficiary, and one total record (`08`)
  carrying the summed amount. Build a `%CFONB.Virement{}` with its list of
  `%CFONB.Virement.Beneficiaire{}` and call `encode/1`.

  This first version supports the **ordinary transfer** (code opération `02`),
  in euros. Bank coordinates are given either as an IBAN (decomposed and
  key-checked) **or** as split RIB components (établissement / guichet /
  compte) — setting both on the same struct is rejected as ambiguous.

  ## Example

      order = %CFONB.Virement{
        numero_emetteur: "123456",
        nom_emetteur: "ACME SARL",
        iban: "FR1420041010050500013M02606",
        beneficiaires: [
          %CFONB.Virement.Beneficiaire{
            nom: "JEAN DUPONT",
            iban: "FR7630004000031234567890143",
            montant: Decimal.new("1250.00"),
            libelle: "SALAIRE JUILLET"
          }
        ]
      }

      {:ok, %{file: file, total: total}} = CFONB.Virement.encode(order)

  See `FORMAT-VIREMENT.md` for the exact 160-character field layout.
  """

  alias CFONB.{Encode, Rib}
  alias CFONB.Virement.Beneficiaire

  defmodule Beneficiaire do
    @moduledoc """
    One beneficiary of a `CFONB.Virement` (a `06` destinataire record).

    Provide bank coordinates as `iban`, or as split RIB components
    (`etablissement` / `guichet` / `compte`). `montant` is a euro `Decimal`.
    """

    @type t :: %__MODULE__{
            nom: String.t(),
            iban: String.t() | nil,
            etablissement: String.t() | nil,
            guichet: String.t() | nil,
            compte: String.t() | nil,
            montant: Decimal.t(),
            libelle: String.t() | nil,
            reference: String.t() | nil,
            domiciliation: String.t() | nil
          }

    defstruct [
      :nom,
      :iban,
      :etablissement,
      :guichet,
      :compte,
      :montant,
      :libelle,
      :reference,
      :domiciliation
    ]
  end

  @type t :: %__MODULE__{
          numero_emetteur: String.t() | nil,
          nom_emetteur: String.t(),
          iban: String.t() | nil,
          etablissement: String.t() | nil,
          guichet: String.t() | nil,
          compte: String.t() | nil,
          code_operation: String.t(),
          date: Date.t() | nil,
          reference: String.t() | nil,
          beneficiaires: [Beneficiaire.t()]
        }

  defstruct [
    :numero_emetteur,
    :nom_emetteur,
    :iban,
    :etablissement,
    :guichet,
    :compte,
    :date,
    :reference,
    code_operation: "02",
    beneficiaires: []
  ]

  @currency "E"
  @separator "\r\n"

  # Beyond this, the amount in cents no longer fits the 16-digit zone.
  @max_amount Decimal.new(100_000_000_000_000)

  @doc """
  Encodes a `%CFONB.Virement{}` into a CFONB 160 file.

  Returns `{:ok, %{file: binary, total: Decimal.t()}}` where `file` is the
  `03`/`06`.../`08` records joined by CRLF, or `{:error, reason}`.

  ## Options

    * `:separator` — line separator, default `"\\r\\n"` (CRLF, the usual banking
      convention). Pass `"\\n"` for LF.
  """
  @spec encode(t, keyword) :: {:ok, %{file: binary, total: Decimal.t()}} | {:error, term}
  def encode(%__MODULE__{} = order, opts \\ []) do
    separator = Keyword.get(opts, :separator, @separator)

    with :ok <- validate_operation(order.code_operation),
         :ok <- validate_emetteur(order),
         {:ok, emetteur_rib} <- resolve_rib(order),
         {:ok, beneficiaires} <- validate_beneficiaires(order.beneficiaires),
         total = Enum.reduce(beneficiaires, Decimal.new(0), &Decimal.add(&2, elem(&1, 1).montant)),
         :ok <- validate_total(total) do
      # Operation code and émetteur number are common to every record
      # (positions 3-18): encode them once for the whole remise.
      header =
        Encode.numeric(order.code_operation, 2) <>
          Encode.blank(8) <> Encode.alpha(order.numero_emetteur, 6)

      lines =
        [emetteur_record(order, header, emetteur_rib)] ++
          Enum.map(beneficiaires, fn {rib, b} -> beneficiaire_record(header, rib, b) end) ++
          [total_record(header, total)]

      {:ok, %{file: Enum.join(lines, separator), total: total}}
    end
  end

  @doc """
  Same as `encode/2` but returns the file binary directly and raises
  `ArgumentError` on invalid input.
  """
  @spec encode!(t, keyword) :: binary
  def encode!(%__MODULE__{} = order, opts \\ []) do
    case encode(order, opts) do
      {:ok, %{file: file}} -> file
      {:error, reason} -> raise ArgumentError, "invalid virement: #{inspect(reason)}"
    end
  end

  ## ----------------------------------------------------------------------------
  ## Validation
  ## ----------------------------------------------------------------------------

  # v0.2 only supports the ordinary transfer.
  defp validate_operation("02"), do: :ok
  defp validate_operation(code), do: {:error, {:unsupported_operation, code}}

  defp validate_emetteur(order) do
    with :ok <- validate_name(order.nom_emetteur, :nom_emetteur),
         :ok <- validate_numero_emetteur(order.numero_emetteur),
         :ok <- validate_date(order.date) do
      validate_optional_text(order.reference, :reference)
    end
  end

  defp validate_beneficiaires([]), do: {:error, :no_beneficiaire}

  defp validate_beneficiaires(beneficiaires) do
    Enum.reduce_while(beneficiaires, {:ok, []}, fn beneficiaire, {:ok, acc} ->
      with :ok <- validate_name(beneficiaire.nom, :beneficiaire),
           :ok <- validate_optional_text(beneficiaire.libelle, :libelle),
           :ok <- validate_optional_text(beneficiaire.reference, :reference),
           :ok <- validate_optional_text(beneficiaire.domiciliation, :domiciliation),
           {:ok, rib} <- resolve_rib(beneficiaire),
           :ok <- validate_amount(beneficiaire.montant) do
        {:cont, {:ok, [{rib, beneficiaire} | acc]}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  # Names (zone C2) are mandatory in both the 03 and 06 records: a blank name
  # would produce a structurally valid file the bank then rejects.
  defp validate_name(value, field) do
    if is_binary(value) and String.trim(value) != "",
      do: :ok,
      else: {:error, {:missing_name, field}}
  end

  # Optional, but a 7-char émetteur number must not be silently truncated to 6
  # (it is an identifier), and a non-string must not crash mid-encode.
  defp validate_numero_emetteur(nil), do: :ok

  defp validate_numero_emetteur(value) when is_binary(value) do
    if String.length(value) <= 6,
      do: :ok,
      else: {:error, {:numero_emetteur_too_long, value}}
  end

  defp validate_numero_emetteur(_value), do: {:error, {:invalid_field, :numero_emetteur}}

  defp validate_date(nil), do: :ok
  defp validate_date(%Date{}), do: :ok
  defp validate_date(_value), do: {:error, {:invalid_field, :date}}

  defp validate_optional_text(nil, _field), do: :ok
  defp validate_optional_text(value, _field) when is_binary(value), do: :ok
  defp validate_optional_text(_value, field), do: {:error, {:invalid_field, field}}

  defp validate_amount(%Decimal{} = amount) do
    cond do
      not Decimal.positive?(amount) -> {:error, {:non_positive_amount, amount}}
      not Encode.whole_cents?(amount) -> {:error, {:too_many_decimals, amount}}
      Decimal.compare(amount, @max_amount) != :lt -> {:error, {:amount_too_large, amount}}
      true -> :ok
    end
  end

  defp validate_amount(other), do: {:error, {:invalid_amount, other}}

  # Each amount fits the 16-digit zone, but their sum in the 08 record must too.
  defp validate_total(total) do
    if Decimal.compare(total, @max_amount) == :lt,
      do: :ok,
      else: {:error, {:total_too_large, total}}
  end

  # Resolves bank coordinates from either an IBAN (key-checked) or split RIB
  # components, returning `{:ok, {etablissement, guichet, compte}}`.

  # Contradictory coordinates: refusing beats silently picking one — a stale
  # split RIB left behind an IBAN migration could point at another account.
  defp resolve_rib(%{iban: iban, etablissement: etab, guichet: guichet, compte: compte})
       when is_binary(iban) and (is_binary(etab) or is_binary(guichet) or is_binary(compte)) do
    {:error, :ambiguous_bank_coordinates}
  end

  defp resolve_rib(%{iban: iban}) when is_binary(iban) do
    case Rib.from_iban(iban) do
      {:ok, %{bank: bank, branch: branch, account: account}} -> {:ok, {bank, branch, account}}
      {:error, _} = error -> error
    end
  end

  defp resolve_rib(%{etablissement: etab, guichet: guichet, compte: compte})
       when is_binary(etab) and is_binary(guichet) and is_binary(compte) do
    cond do
      not (etab =~ ~r/^\d{1,5}$/ and guichet =~ ~r/^\d{1,5}$/) ->
        {:error, {:invalid_rib, etab, guichet, compte}}

      # An over-length account would be silently truncated in the 11-char zone,
      # misrouting the payment — reject it instead.
      String.length(compte) > 11 ->
        {:error, {:account_too_long, compte}}

      # Likewise, an empty account or one carrying characters `sanitize/1`
      # would swap for spaces must never reach the account zone.
      not (compte =~ ~r/^[0-9A-Za-z]{1,11}$/) ->
        {:error, {:invalid_account, compte}}

      true ->
        {:ok, {etab, guichet, compte}}
    end
  end

  defp resolve_rib(_), do: {:error, :missing_bank_coordinates}

  ## ----------------------------------------------------------------------------
  ## Record building (positional concatenation, each record is exactly 160 chars)
  ## ----------------------------------------------------------------------------

  # `header` carries the shared positions 3-18 (operation code, reserved zone,
  # émetteur number), pre-encoded once per remise.
  defp emetteur_record(order, header, {etab, guichet, compte}) do
    record([
      "03",
      header,
      Encode.blank(1),
      Encode.blank(6),
      Encode.date_jjmma(order.date),
      Encode.alpha(order.nom_emetteur, 24),
      Encode.alpha(order.reference, 7),
      Encode.blank(19),
      @currency,
      Encode.blank(5),
      Encode.numeric(guichet, 5),
      Encode.alpha(compte, 11),
      Encode.blank(16),
      Encode.blank(31),
      Encode.numeric(etab, 5),
      Encode.blank(6)
    ])
  end

  defp beneficiaire_record(header, {etab, guichet, compte}, %Beneficiaire{} = b) do
    record([
      "06",
      header,
      Encode.alpha(b.reference, 12),
      Encode.alpha(b.nom, 24),
      Encode.alpha(b.domiciliation, 24),
      Encode.blank(8),
      Encode.numeric(guichet, 5),
      Encode.alpha(compte, 11),
      Encode.centimes(b.montant, 16),
      Encode.alpha(b.libelle, 31),
      Encode.numeric(etab, 5),
      Encode.blank(6)
    ])
  end

  defp total_record(header, total) do
    record([
      "08",
      header,
      Encode.blank(84),
      Encode.centimes(total, 16),
      Encode.blank(31),
      Encode.blank(5),
      Encode.blank(6)
    ])
  end

  defp record(zones) do
    line = IO.iodata_to_binary(zones)

    if byte_size(line) != 160 do
      raise "internal error: CFONB record is #{byte_size(line)} chars, expected 160"
    end

    line
  end
end
