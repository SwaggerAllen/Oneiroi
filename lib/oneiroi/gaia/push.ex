defmodule Oneiroi.Gaia.Push do
  @moduledoc """
  Push to the witness's devices (gaia#15): content-free. A push carries no
  payload at all, so nothing the resident said leaves the platform; the
  client's service worker shows "Lily wrote" and opens the chat when
  tapped. With no payload there is nothing to encrypt, and a push is a
  POST to the device's push service signed with the platform's VAPID key.

  A device subscribes from the client (on an iPhone, only from the Home
  Screen app, iOS 16.4 and later); its endpoint is held to the known push
  services, so the server never posts to an address a client invented. A
  push service answering 404 or 410 says the device is gone, and the
  subscription is removed with that reason.

  The port is `GAIA_PUSH_CLIENT`: `WebPush` in every real build, `Fake`
  in the suite (conventions §9).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Gaia.Router
  alias Oneiroi.Gaia.Store
  alias Oneiroi.Scope

  import Ecto.Query, only: [from: 2]

  @doc "Delivers one content-free push to `endpoint`: `:ok`, `:gone` when the device is no more, or `{:error, reason}`."
  @callback deliver(endpoint :: String.t()) :: :ok | :gone | {:error, term()}

  # The push services browsers subscribe through. A subscription to any
  # other host is refused: the server would otherwise POST wherever a
  # client said.
  @services ~w(push.apple.com fcm.googleapis.com push.services.mozilla.com notify.windows.com)

  @doc "Whether pushes can be sent: a VAPID key is set."
  @spec configured?() :: boolean()
  def configured?, do: private_key() != nil

  @doc "The platform's VAPID public key, base64url, for the client to subscribe with; nil when unset."
  @spec public_key() :: String.t() | nil
  def public_key do
    case private_key() do
      nil -> nil
      key -> key |> public_of() |> Base.url_encode64(padding: false)
    end
  end

  @doc false
  # The raw key pair: the private scalar and its uncompressed public point.
  def private_key do
    case Config.fetch!(:gaia, :vapid_private_key) do
      nil ->
        nil

      secret ->
        case secret
             |> Config.Secret.reveal()
             |> to_string()
             |> Base.url_decode64(padding: false) do
          {:ok, <<_::binary-size(32)>> = raw} -> raw
          _malformed -> nil
        end
    end
  end

  @doc false
  def public_of(private), do: :crypto.generate_key(:ecdh, :prime256v1, private) |> elem(0)

  @doc "Subscribes a device of the account's, by its push service endpoint."
  @spec subscribe(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def subscribe(account_id, endpoint, %Actor{} = actor) do
    with :ok <- endpoint_ok(endpoint),
         {:ok, _} <-
           dispatch(%Commands.SubscribePush{
             actor: actor,
             at: Clock.now(),
             id: account_id,
             endpoint: endpoint
           }),
         do: :ok
  end

  @doc "Unsubscribes a device; an endpoint not subscribed is already so."
  @spec unsubscribe(String.t(), String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def unsubscribe(account_id, endpoint, reason, %Actor{} = actor) do
    command = %Commands.UnsubscribePush{
      actor: actor,
      at: Clock.now(),
      id: account_id,
      endpoint: endpoint,
      reason: reason
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc """
  The witness's "No thanks" to the notifications question (gaia#25): the
  account's answer, so the question leaves his needs-you list on every
  device. Turning notifications on later from Settings is subscribing a
  device, which is the other answer.
  """
  @spec decline(String.t(), Actor.t()) :: :ok | {:error, term()}
  def decline(account_id, %Actor{} = actor) do
    with {:ok, _} <-
           dispatch(%Commands.DeclinePush{actor: actor, at: Clock.now(), id: account_id}),
         do: :ok
  end

  @doc """
  The account's answer to the notifications question (gaia#25), or nil
  while it has none: the latest of "No thanks" and a device subscribing.
  An account with a device subscribed before the answer was recorded
  answered by subscribing it.
  """
  @spec answer(String.t()) :: %{answer: String.t(), answered_at: DateTime.t() | nil} | nil
  def answer(account_id) do
    Scope.account(account_id, fn ->
      case Oneiroi.Repo.get_by(Store.PushAnswer, account_id: account_id) do
        %Store.PushAnswer{state: answer, answered_at: at} ->
          %{answer: answer, answered_at: at}

        nil ->
          first =
            Oneiroi.Repo.one(
              from(p in Store.PushSubscription,
                where: p.account_id == ^account_id,
                select: min(p.subscribed_at)
              )
            )

          first && %{answer: "subscribed", answered_at: first}
      end
    end)
  end

  @doc """
  A push for what waits on the witness (gaia#26, brain#77): of a
  resident's needs-you entries (`%{"kind" => _, "ref" => _}`), the ones
  never pushed for are recorded on the account and one content-free push
  goes to his devices for them all. An entry is pushed for once, ever.
  Nothing is recorded when nothing could be sent (no key, no device), so
  an entry is never marked told when no device heard of it.
  """
  @spec needs_you(String.t(), String.t(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def needs_you(account_id, resident_id, entries) do
    if entries == [] or not configured?() or subscriptions(account_id) == [] do
      {:ok, []}
    else
      command = %Commands.RecordNeedsYouPush{
        actor: Actor.platform(),
        at: Clock.now(),
        id: account_id,
        resident_id: resident_id,
        entries: entries
      }

      with {:ok, events} <- dispatch(command), do: told(account_id, events)
    end
  end

  # The entries the aggregate recorded as new, and the one push for them.
  defp told(account_id, events) do
    case for(%Events.NeedsYouPushed{entries: e} <- List.wrap(events), do: e) do
      [] ->
        {:ok, []}

      pushed ->
        :ok = notify(account_id)
        {:ok, List.flatten(pushed)}
    end
  end

  @doc "The account's subscribed endpoints."
  @spec subscriptions(String.t()) :: [String.t()]
  def subscriptions(account_id) do
    Scope.account(account_id, fn ->
      Oneiroi.Repo.all(
        from(p in Store.PushSubscription,
          where: p.account_id == ^account_id,
          order_by: p.subscribed_at,
          select: p.endpoint
        )
      )
    end)
  end

  @doc """
  Pushes to every device of the account's, in the background: the caller
  never waits on a push service. A device found gone is unsubscribed.
  Nothing happens when no key is set or nothing is subscribed.
  """
  @spec notify(String.t()) :: :ok
  def notify(account_id) do
    if configured?() do
      _ = Task.Supervisor.start_child(:gaia_push, fn -> deliver_all(account_id) end)
    end

    :ok
  end

  @doc "Pushes to every device now and says how each went: `[{endpoint, :ok | :gone | {:error, _}}]`."
  @spec deliver_all(String.t()) :: [{String.t(), term()}]
  def deliver_all(account_id) do
    client = Config.fetch!(:gaia, :push_client)

    for endpoint <- subscriptions(account_id) do
      result = client.deliver(endpoint)

      if result == :gone,
        do: unsubscribe(account_id, endpoint, "gone", Actor.platform())

      {endpoint, result}
    end
  end

  defp endpoint_ok(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        if Enum.any?(@services, &(host == &1 or String.ends_with?(host, "." <> &1))),
          do: :ok,
          else: invalid(endpoint)

      _other ->
        invalid(endpoint)
    end
  end

  defp endpoint_ok(endpoint), do: invalid(endpoint)

  defp invalid(_endpoint),
    do:
      {:error,
       Error.new(:gaia_push_endpoint_invalid, :gaia_push_subscribe_endpoint, services: @services)}

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:gaia_dispatch_failed, :gaia_push_dispatch_failed, reason)}
    end
  end
end
