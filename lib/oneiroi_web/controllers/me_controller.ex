defmodule OneiroiWeb.MeController do
  use OneiroiWeb, :controller

  alias Oneiroi.Config.Secret
  alias OpenApiSpex.Schema

  tags(["identity"])

  operation(:show,
    summary: "The account behind this session or token",
    responses: [ok: {"the principal", "application/json", %Schema{type: :object}}]
  )

  def show(%{assigns: %{principal: p}} = conn, _params) do
    json(conn, %{
      account_id: p.account_id,
      email: p.email,
      via: Atom.to_string(p.via),
      residents: Oneiroi.Gaia.witnessed_residents(p.account_id),
      key: Oneiroi.Gaia.key_status(p.account_id),
      github: Oneiroi.Gaia.github_token_status(p.account_id),
      roles: Oneiroi.Gaia.roles_of(p.account_id),
      household: Oneiroi.Gaia.household(p.account_id)
    })
  end

  operation(:socket_token,
    summary: "A short-lived token the client opens the socket with",
    responses: [created: {"the token", "application/json", %Schema{type: :object}}]
  )

  def socket_token(%{assigns: %{principal: p}} = conn, _params) do
    conn |> put_status(201) |> json(%{token: OneiroiWeb.UserSocket.token(conn, p.account_id)})
  end

  operation(:store_key,
    summary:
      "Store the OpenRouter key every model call for this account's residents spends; storing again rotates it",
    request_body:
      {"the key", "application/json",
       %Schema{type: :object, required: [:key], properties: %{key: %Schema{type: :string}}}},
    responses: [no_content: "stored"]
  )

  def store_key(%{assigns: %{principal: p}} = conn, %{"key" => raw}) do
    key = Secret.wrap(raw)

    case Oneiroi.Gaia.store_key(p.account_id, key, actor(conn)) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  def store_key(conn, _params),
    do: problem(conn, 422, :key_required, :web_me_store_key_key_required, "key is required")

  operation(:revoke_key, summary: "Revoke the stored key", responses: [no_content: "revoked"])

  def revoke_key(%{assigns: %{principal: p}} = conn, _params) do
    case Oneiroi.Gaia.revoke_key(p.account_id, actor(conn)) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, %{kind: :gaia_no_key} = e} ->
        error(conn, 404, e)

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  # ---- the GitHub read token (gaia#24) ----

  operation(:store_github_token,
    summary:
      "Store the GitHub read token the resident's pull request reads use (gaia#24); storing again rotates it",
    request_body:
      {"the token", "application/json",
       %Schema{type: :object, required: [:token], properties: %{token: %Schema{type: :string}}}},
    responses: [no_content: "stored"]
  )

  def store_github_token(%{assigns: %{principal: p}} = conn, %{"token" => raw}) do
    case Oneiroi.Gaia.store_github_token(p.account_id, Secret.wrap(raw), actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  def store_github_token(conn, _params),
    do:
      problem(
        conn,
        422,
        :github_token_required,
        :web_me_store_github_token_required,
        "token is required"
      )

  operation(:revoke_github_token,
    summary: "Revoke the stored GitHub read token; reads go anonymous",
    responses: [no_content: "revoked"]
  )

  def revoke_github_token(%{assigns: %{principal: p}} = conn, _params) do
    case Oneiroi.Gaia.revoke_github_token(p.account_id, actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, %{kind: :gaia_no_github_token} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  # ---- pushes (gaia#15) ----

  @endpoint_body {"the device", "application/json",
                  %Schema{
                    type: :object,
                    required: [:endpoint],
                    properties: %{endpoint: %Schema{type: :string}}
                  }}

  operation(:push,
    summary:
      "Whether pushes are set up, the VAPID key a device subscribes with, how many of this account's devices are subscribed, and the account's answer to the notifications question (gaia#25): `answered` is `subscribed`, `declined` or null, with `answered_at`",
    responses: [ok: {"push", "application/json", %Schema{type: :object}}]
  )

  def push(%{assigns: %{principal: p}} = conn, _params) do
    config = Oneiroi.Gaia.push_config()

    json(
      conn,
      %{
        enabled: config.enabled,
        public_key: config.public_key,
        devices: length(Oneiroi.Gaia.push_subscriptions(p.account_id))
      }
      |> Map.merge(answered(p.account_id))
    )
  end

  defp answered(account_id) do
    case Oneiroi.Gaia.push_answer(account_id) do
      nil -> %{answered: nil, answered_at: nil}
      %{answer: answer, answered_at: at} -> %{answered: answer, answered_at: at}
    end
  end

  operation(:decline_push,
    summary:
      "No thanks to notifications (gaia#25): the account's answer, which takes the question off the needs-you list on every device; subscribing a device later answers it the other way",
    responses: [ok: {"the answer", "application/json", %Schema{type: :object}}]
  )

  def decline_push(%{assigns: %{principal: p}} = conn, _params) do
    case Oneiroi.Gaia.decline_push(p.account_id, actor(conn)) do
      :ok -> json(conn, answered(p.account_id))
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:subscribe_push,
    summary:
      "Subscribe a device to content-free pushes: told when the resident writes unprompted, never what she said",
    request_body: @endpoint_body,
    responses: [no_content: "subscribed"]
  )

  def subscribe_push(%{assigns: %{principal: p}} = conn, %{"endpoint" => endpoint}) do
    case Oneiroi.Gaia.subscribe_push(p.account_id, endpoint, actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  def subscribe_push(conn, _params),
    do:
      problem(
        conn,
        422,
        :endpoint_required,
        :web_me_push_endpoint_required,
        "endpoint is required"
      )

  operation(:redeem_invite,
    summary:
      "Redeem an invite code onto the caller's household (gaia#18): its terms become the household's",
    request_body:
      {"the code", "application/json",
       %Schema{type: :object, required: [:code], properties: %{code: %Schema{type: :string}}}},
    responses: [ok: {"what the code granted", "application/json", %Schema{type: :object}}]
  )

  def redeem_invite(%{assigns: %{principal: p}} = conn, %{"code" => code}) when is_binary(code) do
    household = Oneiroi.Gaia.household_id(p.account_id)

    case Oneiroi.Gaia.redeem_invite(code, household, actor(conn)) do
      {:ok, granted} ->
        json(conn, %{granted: granted, household: Oneiroi.Gaia.household(p.account_id)})

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  def redeem_invite(conn, _params),
    do: problem(conn, 422, :code_required, :web_me_invite_code_required, "code is required")

  operation(:unsubscribe_push,
    summary: "Unsubscribe a device",
    request_body: @endpoint_body,
    responses: [no_content: "unsubscribed"]
  )

  def unsubscribe_push(%{assigns: %{principal: p}} = conn, %{"endpoint" => endpoint}) do
    case Oneiroi.Gaia.unsubscribe_push(p.account_id, endpoint, actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  def unsubscribe_push(conn, params), do: subscribe_push(conn, params)

  operation(:test_push,
    summary: "Push to every device of this account's now, and say how each went",
    responses: [ok: {"how each went", "application/json", %Schema{type: :object}}]
  )

  def test_push(%{assigns: %{principal: p}} = conn, _params) do
    results =
      for {endpoint, result} <- Oneiroi.Gaia.push_now(p.account_id) do
        %{device: URI.parse(endpoint).host, result: push_result(result)}
      end

    json(conn, %{sent: results})
  end

  defp push_result(:ok), do: "delivered"
  defp push_result(:gone), do: "gone, unsubscribed"

  defp push_result({:error, %{site: :gaia_push_refused, details: details}}),
    do: "refused: #{details[:status]}"

  defp push_result({:error, %{meaning: meaning}}), do: "failed: #{meaning}"
  defp push_result({:error, _other}), do: "failed"
end
