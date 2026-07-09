defmodule CFONB.Rib do
  @moduledoc """
  French bank-account identifier helpers (RIB / IBAN).

  A *RIB* (Relevé d'Identité Bancaire) is `bank ++ branch ++ account ++ key`
  where `bank` (code établissement) is 5 digits, `branch` (code guichet) 5,
  `account` (numéro de compte) 11, and `key` (clé RIB) 2, for 23 characters
  total. Account numbers may contain letters, which are folded to digits before
  the key is computed.

  This module centralises the RIB key computation and IBAN derivation used both
  when reading statements (`CFONB.Statement.rib/1`, `iban/1`) and when emitting
  transfer orders (`CFONB.Virement`), where a supplied IBAN must be decomposed
  and its key verified before the account coordinates are written out.
  """

  # French RIB letter-to-digit table (A-I:1-9, J-R:1-9, S-Z:2-9).
  @rib_letters %{
    "A" => "1",
    "B" => "2",
    "C" => "3",
    "D" => "4",
    "E" => "5",
    "F" => "6",
    "G" => "7",
    "H" => "8",
    "I" => "9",
    "J" => "1",
    "K" => "2",
    "L" => "3",
    "M" => "4",
    "N" => "5",
    "O" => "6",
    "P" => "7",
    "Q" => "8",
    "R" => "9",
    "S" => "2",
    "T" => "3",
    "U" => "4",
    "V" => "5",
    "W" => "6",
    "X" => "7",
    "Y" => "8",
    "Z" => "9"
  }

  @doc """
  Computes the 2-digit French RIB key for the given `bank`, `branch` and
  `account` (returned as a zero-padded string).

  Raises `ArgumentError` when no key is derivable: blank or non-numeric
  `bank`/`branch`, or an `account` containing characters outside `[0-9A-Za-z]`.
  Statements parsed from files with blank or free-form account zones fall in
  that case — check the fields before calling.
  """
  @spec key(String.t(), String.t(), String.t()) :: String.t()
  def key(bank, branch, account) do
    unless bank =~ ~r/^\d+$/ and branch =~ ~r/^\d+$/ and account =~ ~r/^[0-9A-Za-z]+$/ do
      raise ArgumentError,
            "cannot derive a RIB key from bank #{inspect(bank)}, branch " <>
              "#{inspect(branch)}, account #{inspect(account)}"
    end

    numeric_account = account |> String.upcase() |> convert_letters() |> String.to_integer()

    key =
      97 -
        rem(
          String.to_integer(bank) * 89 + String.to_integer(branch) * 15 + numeric_account * 3,
          97
        )

    pad2(key)
  end

  @doc """
  Returns the 23-character RIB (`bank ++ branch ++ account ++ key`).
  """
  @spec rib(String.t(), String.t(), String.t()) :: String.t()
  def rib(bank, branch, account) do
    bank <> branch <> account <> key(bank, branch, account)
  end

  @doc """
  Returns the French IBAN derived from `bank`, `branch` and `account`.
  """
  @spec iban(String.t(), String.t(), String.t()) :: String.t()
  def iban(bank, branch, account) do
    bban = rib(bank, branch, account)
    normalized = (bban <> "FR00") |> String.upcase() |> iban_normalize()
    check = 98 - rem(String.to_integer(normalized), 97)

    "FR" <> pad2(check) <> bban
  end

  @doc """
  Decomposes a French IBAN into its RIB components, verifying both the IBAN
  check digits (ISO 7064 mod-97-10) and the embedded RIB key.

  Returns `{:ok, %{bank: ..., branch: ..., account: ..., key: ...}}` or
  `{:error, reason}`. Spaces in the input are ignored.
  """
  @spec from_iban(String.t()) ::
          {:ok, %{bank: String.t(), branch: String.t(), account: String.t(), key: String.t()}}
          | {:error, term}
  def from_iban(iban) when is_binary(iban) do
    normalized = iban |> String.upcase() |> String.replace(" ", "")

    with :ok <- validate_fr(normalized),
         :ok <- validate_iban_key(normalized),
         <<"FR", _check::binary-size(2), bank::binary-size(5), branch::binary-size(5),
           account::binary-size(11), key::binary-size(2)>> <- normalized,
         :ok <- validate_rib_key(bank, branch, account, key) do
      {:ok, %{bank: bank, branch: branch, account: account, key: key}}
    else
      {:error, _} = error -> error
      _ -> {:error, {:invalid_iban, iban}}
    end
  end

  # A French IBAN is FR + 2 check digits + the 23-char BBAN (5-digit bank,
  # 5-digit branch, 11-alphanumeric account, 2-digit RIB key). Validating the
  # structure up front keeps every later String.to_integer safe.
  defp validate_fr(iban) do
    if iban =~ ~r/^FR\d{2}\d{5}\d{5}[0-9A-Z]{11}\d{2}$/,
      do: :ok,
      else: {:error, {:invalid_iban, iban}}
  end

  # ISO 7064 mod-97-10: move the first 4 chars to the end, convert letters to
  # numbers, the whole thing must be ≡ 1 (mod 97).
  defp validate_iban_key(iban) do
    <<head::binary-size(4), rest::binary>> = iban
    number = (rest <> head) |> iban_normalize() |> String.to_integer()

    if rem(number, 97) == 1, do: :ok, else: {:error, {:invalid_iban_check, iban}}
  end

  defp validate_rib_key(bank, branch, account, key) do
    if key(bank, branch, account) == key,
      do: :ok,
      else: {:error, {:invalid_rib_key, bank <> branch <> account <> key}}
  end

  defp convert_letters(account) do
    account
    |> String.graphemes()
    |> Enum.map_join("", &Map.get(@rib_letters, &1, &1))
  end

  defp iban_normalize(string) do
    string
    |> String.to_charlist()
    |> Enum.map_join("", fn
      char when char in ?A..?Z -> Integer.to_string(char - 55)
      char -> <<char>>
    end)
  end

  defp pad2(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
