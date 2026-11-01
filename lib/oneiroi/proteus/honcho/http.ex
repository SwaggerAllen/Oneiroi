defmodule Oneiroi.Proteus.Honcho.HTTP do
  @moduledoc """
  Honcho over its HTTP API, v3, on the admin key that never leaves the
  core (spec §6.9). Every request is `Honcho.Wire`'s, in the names the
  deployed server declares: plastic-labs/honcho at commit `6f91136`,
  its routers and pydantic schemas read field by field into
  `test/fixtures/proteus/honcho-server.json` (proteus #9). The in-memory
  Honcho checks the same requests against that record, and the HTTP
  boundary's tests hold the bodies sent here and the answers parsed here
  to it.

  The bodies before were claims from the docs (`name`, `peer_names`,
  `messages[].peer_name`, `filters.observer`/`observed`, a `tokens`
  query): the server takes the first two by name, ignores the last, and
  refuses `peer_name` with a 422, which was every sync of a turn from
  the resident's first live one.
  """
  @behaviour Oneiroi.Proteus.Honcho

  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.Proteus.Error
  alias Oneiroi.Proteus.Honcho.Wire

  @impl true
  def ensure_workspace(ws), do: ws |> Wire.workspace() |> call() |> ok()

  # Get-or-create leaves an existing peer's configuration as it was, so
  # the configuration is set again on a peer that was there.
  @impl true
  def ensure_peer(ws, peer, config) do
    with {:ok, _} <- call(Wire.peer(ws, peer, config)),
         {:ok, _} <- call(Wire.peer_configuration(ws, peer, config)) do
      :ok
    end
  end

  @impl true
  def ensure_session(ws, session, peers), do: ws |> Wire.session(session, peers) |> call() |> ok()

  @impl true
  def add_messages(_ws, _session, []), do: :ok

  def add_messages(ws, session, messages),
    do: ws |> Wire.messages(session, messages) |> call() |> ok()

  @impl true
  def turn_sent?(ws, session, turn_ref) do
    case call(Wire.turn_messages(ws, session, turn_ref)) do
      {:ok, %{"items" => items}} when is_list(items) ->
        {:ok, items != []}

      {:ok, _other} ->
        {:error,
         Error.new(:proteus_honcho_rejected, :proteus_http_turn_unreadable, answer: :unreadable)}

      error ->
        error
    end
  end

  @impl true
  def get_card(ws, peer) do
    case peer_card(ws, peer, peer) do
      {:ok, nil} -> {:ok, []}
      other -> other
    end
  end

  @impl true
  def set_card(ws, peer, card), do: ws |> Wire.set_card(peer, card) |> call() |> ok()

  # PeerContext: `representation` is text, or null when Honcho holds none.
  @impl true
  def context(ws, observer, target) do
    case call(Wire.context(ws, observer, target)) do
      {:ok, %{"representation" => text}} when is_binary(text) ->
        {:ok, text}

      {:ok, %{"representation" => nil}} ->
        {:ok, ""}

      {:ok, _other} ->
        {:error,
         Error.new(:proteus_honcho_rejected, :proteus_http_context_unreadable,
           answer: :unreadable
         )}

      error ->
        error
    end
  end

  # At most `limit`, walked page by page: the server answers at most 100
  # a page, and the memory audit reads 150 (EUNOMIA_AUDIT_CONCLUSIONS),
  # which was a 422 as one page.
  @impl true
  def conclusions(ws, observer, target, limit) do
    filters = %{observer_id: observer, observed_id: target}
    size = min(limit, Wire.page_size())

    with {:ok, items} <- every_page(&Wire.conclusions(ws, filters, &1, size), limit) do
      {:ok, Enum.map(items, &%{id: to_string(&1["id"]), content: to_string(&1["content"])})}
    end
  end

  @impl true
  def delete_conclusion(ws, id), do: ws |> Wire.delete_conclusion(id) |> call() |> ok()

  @impl true
  def mint_key(ws, peer, expires_at) do
    case call(Wire.key(ws, peer, expires_at)) do
      {:ok, %{"key" => key}} when is_binary(key) ->
        {:ok, key}

      {:ok, _other} ->
        {:error, Error.new(:proteus_honcho_rejected, :proteus_http_mint_key_unanswered)}

      error ->
        error
    end
  end

  # ---- the reads the records export takes (proteus #18) ----
  #
  # A list is `POST .../list?page=N&size=M`, with no body when nothing is
  # filtered, answering a Page (`items`, `page`, `size`, `total`,
  # `pages`); the server's page is at most 100.

  @impl true
  def peers(ws) do
    with {:ok, items} <- every_page(&Wire.list(ws, "peers", &1)) do
      {:ok, items |> Enum.map(&to_string(&1["id"])) |> Enum.uniq() |> Enum.sort()}
    end
  end

  # PeerCardResponse: `peer_card` is the lines, or null when the observer
  # holds no card of the target.
  @impl true
  def peer_card(ws, observer, target) do
    case call(Wire.card(ws, observer, target)) do
      {:ok, %{"peer_card" => lines}} when is_list(lines) ->
        {:ok, Enum.map(lines, &to_string/1)}

      {:ok, %{"peer_card" => nil}} ->
        {:ok, nil}

      {:ok, _other} ->
        {:error,
         Error.new(:proteus_honcho_rejected, :proteus_http_card_unreadable, answer: :unreadable)}

      error ->
        error
    end
  end

  @impl true
  def all_conclusions(ws) do
    with {:ok, items} <- every_page(&Wire.conclusions(ws, nil, &1, Wire.page_size())) do
      {:ok, items |> Enum.map(&held_conclusion/1) |> Enum.uniq_by(& &1.id)}
    end
  end

  @impl true
  def sessions(ws) do
    with {:ok, items} <- every_page(&Wire.list(ws, "sessions", &1)) do
      {:ok, items |> Enum.map(&to_string(&1["id"])) |> Enum.uniq() |> Enum.sort()}
    end
  end

  @impl true
  def summaries(ws, session) do
    case call(Wire.summaries(ws, session)) do
      {:ok, %{} = body} ->
        {:ok, %{short: summary(body["short_summary"]), long: summary(body["long_summary"])}}

      {:ok, _other} ->
        {:error,
         Error.new(:proteus_honcho_rejected, :proteus_http_summaries_unreadable,
           answer: :unreadable
         )}

      error ->
        error
    end
  end

  defp held_conclusion(item) do
    %{
      id: to_string(item["id"]),
      content: to_string(item["content"]),
      observer: to_string(item["observer_id"]),
      observed: to_string(item["observed_id"]),
      session: item["session_id"],
      level: to_string(item["level"] || "explicit"),
      sources: Enum.map(item["source_ids"] || [], &to_string/1),
      created_at: item["created_at"]
    }
  end

  # Summary: `message_id` is the public id of the message it runs through.
  defp summary(%{"content" => content} = s) when is_binary(content),
    do: %{content: content, through: s["message_id"]}

  defp summary(_none), do: nil

  # Every page of a list, from the first to the last the server counts,
  # or until `limit` items are read. A page past what it said there
  # would be ends the walk too, so a list that shrinks while it is read
  # cannot loop.
  defp every_page(build, limit \\ :infinity, page \\ 1, acc \\ []) do
    case call(build.(page)) do
      {:ok, %{"items" => items} = body} when is_list(items) ->
        more? = is_integer(body["pages"]) and page < body["pages"] and items != []
        next_page(build, limit, page, acc ++ items, more?)

      {:ok, _other} ->
        {:error,
         Error.new(:proteus_honcho_rejected, :proteus_http_page_unreadable, answer: :unreadable)}

      error ->
        error
    end
  end

  defp next_page(_build, limit, _page, acc, _more?)
       when is_integer(limit) and length(acc) >= limit,
       do: {:ok, Enum.take(acc, limit)}

  defp next_page(build, limit, page, acc, true), do: every_page(build, limit, page + 1, acc)
  defp next_page(_build, _limit, _page, acc, false), do: {:ok, acc}

  # ---- transport ----

  defp call(%{method: method, path: path, params: params, body: body}) do
    opts = if body, do: [params: params, json: body], else: [params: params]

    with {:ok, url, key} <- endpoint() do
      request(method, url, path, key, opts)
    end
  end

  @doc """
  Where Honcho answers and the key it takes, or the bridge's sited
  error naming the setting that is missing. Unset, the transport used to
  raise inside Req on a nil URL or bearer; a Honcho not yet deployed
  beside an instance is a refusal the bridge records, never a crash.
  """
  @spec configured(String.t() | nil, Secret.t() | nil, Secret.t() | nil) ::
          {:ok, String.t(), String.t()} | {:error, Error.t()}
  def configured(url, admin_key, jwt_secret) do
    key = admin_key(admin_key, jwt_secret)

    cond do
      not is_binary(url) or url == "" ->
        {:error,
         Error.new(:proteus_honcho_unconfigured, :proteus_http_url_unset,
           setting: "PROTEUS_HONCHO_URL"
         )}

      not is_binary(key) ->
        {:error,
         Error.new(:proteus_honcho_unconfigured, :proteus_http_key_unset,
           setting: "PROTEUS_HONCHO_ADMIN_KEY or PROTEUS_HONCHO_JWT_SECRET"
         )}

      true ->
        {:ok, url, key}
    end
  end

  defp endpoint do
    configured(
      Config.fetch!(:proteus, :honcho_url),
      Config.fetch!(:proteus, :honcho_admin_key),
      Config.fetch!(:proteus, :honcho_jwt_secret)
    )
  end

  # The one place the host is spelled outside the port: the setting the
  # port reads it from.
  defp request(method, url, path, key, opts) do
    opts =
      Keyword.merge(opts,
        method: method,
        url: Path.join([url, "v3" | path]),
        auth: {:bearer, key},
        receive_timeout: Config.fetch!(:proteus, :request_timeout_ms),
        retry: false
      )

    # Not a model call: Honcho is its own external, behind its own port
    # (`Oneiroi.Proteus.Honcho`, registered in `externals/0`), and the
    # `model_port` check reads every Req call as the ledger's. This is
    # the one HTTP call outside the provider port, and it is this file.
    #
    # A refusal keeps Honcho's status and never its body: a body can echo
    # what was sent, which is a tenant's words, and the bridge records
    # the reason it is given on the resident's stream.
    # oneiroi:allow model_port
    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, Error.new(:proteus_honcho_rejected, :proteus_http_rejected, status: status)}

      {:error, reason} ->
        {:error, Error.caught(:proteus_honcho_unreachable, :proteus_http_unreachable, reason)}
    end
  end

  # The admin key as set, or minted from Honcho's own signing secret
  # (proteus #16): Honcho's admin JWT is HS256 over `{"t": "", "ad": true}`,
  # as its `create_admin_jwt` writes it (src/security.py, unchanged at the
  # pinned commit), so a core holding the secret holds the key without
  # anyone minting it by hand and typing it into a dashboard.
  defp admin_key(%Secret{value: key}, _secret) when is_binary(key) and key != "", do: key
  defp admin_key(_unset, secret), do: mint(secret)

  @doc false
  def mint(%Secret{value: secret}) when is_binary(secret) and secret != "" do
    header = encode(%{"alg" => "HS256", "typ" => "JWT"})
    payload = encode(%{"ad" => true, "t" => ""})
    signature = :crypto.mac(:hmac, :sha256, secret, header <> "." <> payload)
    header <> "." <> payload <> "." <> Base.url_encode64(signature, padding: false)
  end

  def mint(_unset), do: nil

  defp encode(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp ok({:ok, _body}), do: :ok
  defp ok(error), do: error
end
