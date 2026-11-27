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

  Every read and write goes to Gitea through the repositories' port
  (`Repos.Gitea`, sima-qian#57). `sync_household/1` and `sync_resident/1`
  send a working repository whole, history and all: the one move from
  the records disk (`GiteaMigration`, sima-qian#58) and an import's
  assembled repository. Unset (`SIMA_QIAN_GITEA_TOKEN`), nothing is
  sent.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.Gaia
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.GiteaQueue
  alias Oneiroi.SimaQian.Household

  # Each call names the instance it goes to (sima-qian#60).
  @callback ensure_org(inst :: String.t(), org :: String.t()) :: :ok | {:error, term()}
  @callback ensure_repo(inst :: String.t(), org :: String.t(), repo :: String.t()) ::
              :ok | {:error, term()}
  @callback ensure_user(inst :: String.t(), login :: String.t(), email :: String.t()) ::
              :ok | {:error, term()}
  @callback grant_read(
              inst :: String.t(),
              org :: String.t(),
              repo :: String.t(),
              login :: String.t()
            ) :: :ok | {:error, term()}
  @callback set_password(inst :: String.t(), login :: String.t(), password :: String.t()) ::
              :ok | {:error, term()}
  @callback remote(inst :: String.t(), org :: String.t(), repo :: String.t()) ::
              {:ok, String.t() | Secret.t()} | {:error, term()}
  # Waits until Gitea no longer counts a just-pushed repository as empty
  # (sima-qian#62): until then its API lists nothing for every path.
  @callback settled(inst :: String.t(), org :: String.t(), repo :: String.t()) ::
              :ok | {:error, term()}
  # Protects the main branch (sima-qian#64): no force-push, no deletion,
  # so history is only ever added to and every citation of it holds.
  @callback protect(inst :: String.t(), org :: String.t(), repo :: String.t()) ::
              :ok | {:error, term()}

  @house "house"
  # A succession's fork copies (sima-qian#73): the platform's own
  # organization, never a household's, and nobody granted.
  @forks "forks"

  @doc "Whether the server is set up here."
  defdelegate configured?(), to: GiteaQueue

  @doc "The organization a household's repositories live under."
  def org(household_id), do: "h-" <> short(household_id)

  @doc "A witness's Gitea user."
  def login(account_id), do: "w-" <> short(account_id)

  defp short(uuid), do: uuid |> String.replace("-", "") |> String.slice(0, 12)

  @doc """
  The instance a household's repositories are on (sima-qian#60): its own
  routing when it has one, else the primary. Sharded by household, so a
  household's repositories and its witnesses' users are on one server.
  """
  def instance(nil), do: GiteaQueue.primary()

  def instance(household_id),
    do: Gaia.household_gitea_instance(household_id) || GiteaQueue.primary()

  @doc """
  Where a repository lives on Gitea: `{instance, org, name}` (sima-qian#57,
  #60). A household's is its organization's `house`; a resident's is her
  household's organization, under her slug.
  """
  def locate({:household, household_id}),
    do: {:ok, {instance(household_id), org(household_id), @house}}

  def locate({:resident, resident_id}) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, %{state: "fork", slug: slug}} -> {:ok, {GiteaQueue.primary(), @forks, slug}}
      _housed -> locate_housed(resident_id)
    end
  end

  # A fork joins no household (sima-qian#67), so it is never located under
  # one: that left the first production fork with nowhere to put its
  # repository (2026-11-26).
  defp locate_housed(resident_id) do
    with {:ok, resident} <- AgathosDaimon.fetch(resident_id),
         household_id when is_binary(household_id) <-
           Gaia.resident_household(resident_id) |> id_of() do
      {:ok, {instance(household_id), org(household_id), resident.slug}}
    else
      _none -> {:error, Error.new(:sima_qian_gitea_failed, :sima_qian_gitea_unlocated)}
    end
  end

  @doc "Makes a repository on Gitea if it is missing: its organization, the repository, its readers."
  def ensure({:household, household_id}) do
    {inst, org} = {instance(household_id), org(household_id)}

    with :ok <- client().ensure_org(inst, org),
         :ok <- client().ensure_repo(inst, org, @house),
         :ok <- client().protect(inst, org, @house),
         do: grant_witnesses(inst, org, @house, household_id)
  end

  def ensure({:resident, resident_id} = repo) do
    case locate(repo) do
      {:ok, {inst, @forks, name}} -> ensure_fork(inst, name)
      _housed -> ensure_housed(resident_id, repo)
    end
  end

  # A fork's repository: made and protected, read by nobody but the
  # platform.
  defp ensure_fork(inst, name) do
    with :ok <- client().ensure_org(inst, @forks),
         :ok <- client().ensure_repo(inst, @forks, name),
         do: client().protect(inst, @forks, name)
  end

  defp ensure_housed(resident_id, repo) do
    with {:ok, {inst, org, name}} <- locate(repo),
         {:ok, resident} <- AgathosDaimon.fetch(resident_id),
         :ok <- client().ensure_org(inst, org),
         :ok <- client().ensure_repo(inst, org, name),
         :ok <- client().protect(inst, org, name),
         do: grant(inst, org, name, resident.account_id)
  end

  @doc """
  Protects every repository already on the server (sima-qian#64): each
  household's and each housed resident's. Safe to repeat; run at boot,
  so the repositories made before protection existed get it too.
  Answers the repositories it could not protect.
  """
  def protect_all do
    residents = for r <- AgathosDaimon.residents(), do: {:resident, r.id}

    houses =
      residents
      |> Enum.map(fn {:resident, id} -> Gaia.resident_household(id) |> id_of() end)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.map(&{:household, &1})

    for repo <- houses ++ residents,
        {:ok, {inst, org, name}} <- [locate(repo)],
        result = client().protect(inst, org, name),
        result != :ok,
        do: {repo, result}
  end

  @doc "Sends the household's repository: its organization, its `house`, its witnesses' read, then the push."
  def sync_household(household_id) do
    {inst, org} = {instance(household_id), org(household_id)}

    with :ok <- client().ensure_org(inst, org),
         :ok <- client().ensure_repo(inst, org, @house),
         :ok <- client().protect(inst, org, @house),
         :ok <- grant_witnesses(inst, org, @house, household_id),
         {:ok, dir} <- Household.repository_dir(household_id),
         {:ok, remote} <- client().remote(inst, org, @house),
         {:ok, pushed} <- push(dir, remote),
         :ok <- settled(pushed, inst, org, @house) do
      {:ok, pushed}
    end
  end

  @doc "Sends a resident's repository, under its household's organization, read by its witness alone."
  def sync_resident(resident_id) do
    with {:ok, resident} <- AgathosDaimon.fetch(resident_id),
         household_id when is_binary(household_id) <-
           Gaia.resident_household(resident_id) |> id_of(),
         {inst, org} = {instance(household_id), org(household_id)},
         :ok <- client().ensure_org(inst, org),
         :ok <- client().ensure_repo(inst, org, resident.slug),
         :ok <- client().protect(inst, org, resident.slug),
         :ok <- grant(inst, org, resident.slug, resident.account_id),
         {:ok, dir} <- working_dir(resident_id),
         {:ok, remote} <- client().remote(inst, org, resident.slug),
         {:ok, pushed} <- push(dir, remote),
         :ok <- settled(pushed, inst, org, resident.slug) do
      {:ok, pushed}
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
        url: public_url(instance(household_id)),
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
        {login, inst} = {login(account_id), instance(Gaia.household_id(account_id))}

        with :ok <- client().ensure_user(inst, login, email),
             do: client().set_password(inst, login, password)
    end
  end

  # ---- the parts ----

  defp grant_witnesses(inst, org, repo, household_id) do
    household_id
    |> Gaia.household_members()
    |> Enum.filter(&(&1.kind == "witness"))
    |> Enum.reduce_while(:ok, fn m, :ok ->
      case grant(inst, org, repo, m.id) do
        :ok -> {:cont, :ok}
        failed -> {:halt, failed}
      end
    end)
  end

  defp grant(_inst, _org, _repo, nil), do: :ok

  defp grant(inst, org, repo, account_id) do
    login = login(account_id)

    with :ok <- client().ensure_user(inst, login, email_of(account_id)),
         do: client().grant_read(inst, org, repo, login)
  end

  # Gitea wants an address; the witness's own never leaves the platform
  # for it, so the user carries one under the platform's name.
  defp email_of(account_id), do: login(account_id) <> "@users.oneiroi.invalid"

  defp settled(:sent, inst, org, name), do: client().settled(inst, org, name)
  defp settled(_empty, _inst, _org, _name), do: :ok

  defp push(dir, remote) do
    if Git.head?(dir),
      do: with(:ok <- Git.push(dir, remote), do: {:ok, :sent}),
      else: {:ok, :empty}
  end

  defp id_of(%{id: id}), do: id
  defp id_of(_none), do: nil

  @doc """
  A push Gitea's system webhook reports (sima-qian#59): checked against
  the secret (`X-Gitea-Signature`, hex HMAC-SHA256 of the body), then
  read for whose repository it was. The core's own writes come from its
  admin and are ignored, as are other branches and the household's
  repository, which no index reads.
  """
  def pushed(raw, signature) do
    with {:ok, secret} <- webhook_secret(),
         :ok <- signed(raw, signature, secret),
         {:ok, event} <- decode(raw) do
      {:ok, whose(event)}
    end
  end

  defp webhook_secret do
    case Config.fetch!(:sima_qian, :gitea_webhook_secret) do
      nil -> {:error, Error.new(:sima_qian_gitea_off, :sima_qian_gitea_webhook_off)}
      secret -> {:ok, Secret.unwrap(secret)}
    end
  end

  defp signed(raw, signature, secret) when is_binary(signature) and is_binary(secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, raw) |> Base.encode16(case: :lower)

    if byte_size(signature) == byte_size(expected) and
         :crypto.hash_equals(String.downcase(signature), expected),
       do: :ok,
       else: {:error, Error.new(:sima_qian_gitea_unsigned, :sima_qian_gitea_webhook_signature)}
  end

  defp signed(_raw, _signature, _secret),
    do: {:error, Error.new(:sima_qian_gitea_unsigned, :sima_qian_gitea_webhook_unsigned)}

  defp decode(raw) do
    case Jason.decode(raw) do
      {:ok, %{} = event} -> {:ok, event}
      _not_json -> {:error, Error.new(:sima_qian_gitea_unsigned, :sima_qian_gitea_webhook_body)}
    end
  end

  defp whose(
         %{"ref" => "refs/heads/main", "repository" => %{"name" => name, "owner" => owner}} = e
       ) do
    org = owner["login"] || owner["username"]

    cond do
      get_in(e, ["pusher", "login"]) == Config.fetch!(:sima_qian, :gitea_admin) -> :ignored
      name == @house -> :ignored
      true -> resident(org, name)
    end
  end

  defp whose(_other_branch_or_event), do: :ignored

  # The resident under that slug, if her household's organization is the
  # one pushed to: a slug is the platform's, the organization the check.
  defp resident(org, slug) do
    with %{id: id} <- Enum.find(AgathosDaimon.residents(), &(&1.slug == slug)),
         {:ok, {_inst, ^org, ^slug}} <- locate({:resident, id}) do
      {:resident, id}
    else
      _none -> :ignored
    end
  end

  # The resident's working directory: what the migration sends. Its own
  # path here, so the push never depends on the backup (a cycle).
  defp working_dir(resident_id) do
    dir = Path.join(Config.fetch!(:sima_qian, :root), resident_id)
    with :ok <- Git.ensure_repo(dir), do: {:ok, dir}
  end

  defp public_url(inst) do
    case GiteaQueue.endpoint(inst) do
      {:ok, %{url: url}} -> url
      _unrouted -> nil
    end
  end

  defp client, do: Config.fetch!(:sima_qian, :gitea_client)
end
