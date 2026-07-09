defmodule CFONB.Virement do
  @moduledoc """
  Emits a CFONB **160-character transfer order** (ordre de virement) — a file
  *sent to* the bank, the counterpart of the 120 statement this library parses.

  A remise (batch) is made of one émetteur record (`03`, the donneur d'ordre),
  one destinataire record (`06`) per beneficiary, and one total record (`08`)
  carrying the summed amount. Build a `%CFONB.Virement{}` with its list of
  `%CFONB.Virement.Beneficiaire{}` and call `encode/1`.

  This first version supports the **ordinary transfer** (code opération `02`),
  in euros. Bank coordinates may be given either as an IBAN (decomposed and
  key-checked) or as split RIB components (établissement / guichet / compte).

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
         {:ok, emetteur_rib} <- resolve_rib(order),
         {:ok, beneficiaires} <- validate_beneficiaires(order.beneficiaires) do
      total = Enum.reduce(beneficiaires, Decimal.new(0), &Decimal.add(&2, elem(&1, 1).montant))

      lines =
        [emetteur_record(order, emetteur_rib)] ++
          Enum.map(beneficiaires, fn {rib, b} -> beneficiaire_record(order, rib, b) end) ++
          [total_record(order, total)]

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

  defp validate_beneficiaires([]), do: {:error, :no_beneficiaire}

  defp validate_beneficiaires(beneficiaires) do
    Enum.reduce_while(beneficiaires, {:ok, []}, fn beneficiaire, {:ok, acc} ->
      with {:ok, rib} <- resolve_rib(beneficiaire),
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

  defp validate_amount(%Decimal{} = amount) do
    cond do
      not Decimal.positive?(amount) -> {:error, {:non_positive_amount, amount}}
      more_than_two_decimals?(amount) -> {:error, {:too_many_decimals, amount}}
      true -> :ok
    end
  end

  defp validate_amount(other), do: {:error, {:invalid_amount, other}}

  defp more_than_two_decimals?(amount) do
    cents = Decimal.mult(amount, 100)
    not Decimal.equal?(cents, Decimal.round(cents, 0))
  end

  # Resolves bank coordinates from either an IBAN (key-checked) or split RIB
  # components, returning `{:ok, {etablissement, guichet, compte}}`.
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

      true ->
        {:ok, {etab, guichet, compte}}
    end
  end

  defp resolve_rib(_), do: {:error, :missing_bank_coordinates}

  ## ----------------------------------------------------------------------------
  ## Record building (positional concatenation, each record is exactly 160 chars)
  ## ----------------------------------------------------------------------------

  defp emetteur_record(order, {etab, guichet, compte}) do
    record([
      "03",
      Encode.numeric(order.code_operation, 2),
      Encode.blank(8),
      Encode.alpha(order.numero_emetteur, 6),
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

  defp beneficiaire_record(order, {etab, guichet, compte}, %Beneficiaire{} = b) do
    record([
      "06",
      Encode.numeric(order.code_operation, 2),
      Encode.blank(8),
      Encode.alpha(order.numero_emetteur, 6),
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

  defp total_record(order, total) do
    record([
      "08",
      Encode.numeric(order.code_operation, 2),
      Encode.blank(8),
      Encode.alpha(order.numero_emetteur, 6),
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
