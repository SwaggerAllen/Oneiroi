defmodule Oneiroi.SimaQian.Gitea do
  @moduledoc """
  The repositories' server (sima-qian#55; the witness, 2026-11-16: "a
  separate render service with its own disk … we need it for mvp"):
  Gitea, holding every household's repository and every resident's.

  Each household is an organization (`h-<twelve hex of its id>`), private,
  holding `house` (the household's repository, sima-qian#51) and one
  repository per resident by the resident's slug. Each witness is a
  Gitea user (`w-<twelve hex of the account>`) with read access to the
  household's repository and to their own residents', no one else's; the
  password is the witness's to set from the client (`set_password/2`).

  A household's commit reaches Gitea within seconds of its write
  (`later/2`, one job per repository however many writes, sima-qian#56);
  a resident's at each backup, when its records are committed. Unset
  (`SIMA_QIAN_GITEA_TOKEN`), nothing is sent and nothing fails: the
  repositories stay on the records disk as before.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.Gaia
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.GiteaQueue
  alias Oneiroi.SimaQian.Household

  @callback ensure_org(org :: String.t()) :: :ok | {:error, term()}
  @callback ensure_repo(org :: String.t(), repo :: String.t()) :: :ok | {:error, term()}
  @callback ensure_user(login :: String.t(), email :: String.t()) :: :ok | {:error, term()}
  @callback grant_read(org :: String.t(), repo :: String.t(), login :: String.t()) ::
              :ok | {:error, term()}
  @callback set_password(login :: String.t(), password :: String.t()) :: :ok | {:error, term()}
  @callback remote(org :: String.t(), repo :: String.t()) :: String.t() | Secret.t()

  @house "house"

  @doc "Whether the server is set up here."
  defdelegate configured?(), to: GiteaQueue

  @doc "The organization a household's repositories live under."
  def org(household_id), do: "h-" <> short(household_id)

  @doc "A witness's Gitea user."
  def login(account_id), do: "w-" <> short(account_id)

  defp short(uuid), do: uuid |> String.replace("-", "") |> String.slice(0, 12)

  @doc "Asks for a repository to be sent (sima-qian#56)."
  defdelegate later(kind, id), to: GiteaQueue

  @doc """
  Where a repository lives on Gitea: `{org, name}` (sima-qian#57). A
  household's is its organization's `house`; a resident's is her
  household's organization, under her slug.
  """
  def locate({:household, household_id}), do: {:ok, {org(household_id), @house}}

  def locate({:resident, resident_id}) do
    with {:ok, resident} <- AgathosDaimon.fetch(resident_id),
         household_id when is_binary(household_id) <-
           Gaia.resident_household(resident_id) |> id_of() do
      {:ok, {org(household_id), resident.slug}}
    else
      _none -> {:error, Error.new(:sima_qian_gitea_failed, :sima_qian_gitea_unlocated)}
    end
  end

  @doc "Makes a repository on Gitea if it is missing: its organization, the repository, its readers."
  def ensure({:household, household_id}) do
    org = org(household_id)

    with :ok <- client().ensure_org(org),
         :ok <- client().ensure_repo(org, @house),
         do: grant_witnesses(org, @house, household_id)
  end

  def ensure({:resident, resident_id} = repo) do
    with {:ok, {org, name}} <- locate(repo),
         {:ok, resident} <- AgathosDaimon.fetch(resident_id),
         :ok <- client().ensure_org(org),
         :ok <- client().ensure_repo(org, name),
         do: grant(org, name, resident.account_id)
  end

  @doc "Sends the household's repository: its organization, its `house`, its witnesses' read, then the push."
  def sync_household(household_id) do
    org = org(household_id)

    with :ok <- client().ensure_org(org),
         :ok <- client().ensure_repo(org, @house),
         :ok <- grant_witnesses(org, @house, household_id),
         {:ok, dir} <- Household.repository_dir(household_id) do
      push(dir, client().remote(org, @house))
    end
  end

  @doc "Sends a resident's repository, under its household's organization, read by its witness alone."
  def sync_resident(resident_id) do
    with {:ok, resident} <- AgathosDaimon.fetch(resident_id),
         household_id when is_binary(household_id) <-
           Gaia.resident_household(resident_id) |> id_of(),
         org = org(household_id),
         :ok <- client().ensure_org(org),
         :ok <- client().ensure_repo(org, resident.slug),
         :ok <- grant(org, resident.slug, resident.account_id),
         {:ok, dir} <- Backup.repository_dir(resident_id) do
      push(dir, client().remote(org, resident.slug))
    else
      :error -> {:ok, :gone}
      nil -> {:ok, :no_household}
      other -> other
    end
  end

  @doc "Where a witness reaches Gitea: the server, the user and the repositories they read; nil when it is not set up."
  def access(account_id) do
    with true <- configured?(),
         household_id when is_binary(household_id) <- Gaia.household_id(account_id) do
      org = org(household_id)
      residents = for r <- AgathosDaimon.for_witness(account_id), do: "#{org}/#{r.slug}"

      %{
        url: public_url(),
        login: login(account_id),
        repositories: ["#{org}/#{@house}" | residents]
      }
    else
      _off -> nil
    end
  end

  @doc "Sets the witness's Gitea password, making the user if there is none."
  def set_password(account_id, email, password) do
    cond do
      not configured?() ->
        {:error, Error.new(:sima_qian_gitea_off, :sima_qian_gitea_password_off)}

      not (is_binary(password) and String.length(password) >= 12) ->
        {:error, Error.new(:sima_qian_gitea_invalid, :sima_qian_gitea_password_short)}

      true ->
        login = login(account_id)

        with :ok <- client().ensure_user(login, email),
             do: client().set_password(login, password)
    end
  end

  # ---- the parts ----

  defp grant_witnesses(org, repo, household_id) do
    household_id
    |> Gaia.household_members()
    |> Enum.filter(&(&1.kind == "witness"))
    |> Enum.reduce_while(:ok, fn m, :ok ->
      case grant(org, repo, m.id) do
        :ok -> {:cont, :ok}
        failed -> {:halt, failed}
      end
    end)
  end

  defp grant(_org, _repo, nil), do: :ok

  defp grant(org, repo, account_id) do
    login = login(account_id)

    with :ok <- client().ensure_user(login, email_of(account_id)),
         do: client().grant_read(org, repo, login)
  end

  # Gitea wants an address; the witness's own never leaves the platform
  # for it, so the user carries one under the platform's name.
  defp email_of(account_id), do: login(account_id) <> "@users.oneiroi.invalid"

  defp push(dir, remote) do
    if Git.head?(dir),
      do: with(:ok <- Git.push(dir, remote), do: {:ok, :sent}),
      else: {:ok, :empty}
  end

  defp id_of(%{id: id}), do: id
  defp id_of(_none), do: nil

  @doc false
  def secret_token, do: GiteaQueue.token()

  defp public_url, do: Config.fetch!(:sima_qian, :gitea_url)

  defp client, do: Config.fetch!(:sima_qian, :gitea_client)
end
