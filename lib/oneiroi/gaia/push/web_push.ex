defmodule Oneiroi.Gaia.Push.WebPush do
  @moduledoc """
  A content-free Web Push (RFC 8030) with VAPID (RFC 8292): an empty POST
  to the device's push service, `TTL` a day, signed with an ES256 JWT for
  the push service's origin, the key the platform's. No payload, so no
  RFC 8291 encryption: the service worker shows the same words for every
  push (gaia#15).
  """
  @behaviour Oneiroi.Gaia.Push

  alias Oneiroi.Config
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Push

  @ttl_seconds 86_400
  @jwt_seconds 12 * 3600

  @impl true
  def deliver(endpoint) do
    with private when is_binary(private) <- Push.private_key(),
         %URI{scheme: scheme, host: host} = uri when is_binary(host) <- URI.parse(endpoint) do
      audience = "#{scheme}://#{host}" <> port(uri)

      request(endpoint, [
        {"ttl", Integer.to_string(@ttl_seconds)},
        {"urgency", "normal"},
        {"content-length", "0"},
        {"authorization",
         "vapid t=#{jwt(audience, private)}, k=#{Base.url_encode64(Push.public_of(private), padding: false)}"}
      ])
    else
      nil -> {:error, Error.new(:gaia_push_failed, :gaia_push_not_configured)}
      _bad -> {:error, Error.new(:gaia_push_failed, :gaia_push_endpoint_unparsed)}
    end
  end

  defp request(endpoint, headers) do
    # A push service, not a model provider: the push port's one call
    # (gaia#15), registered in Gaia's externals with its fake.
    # oneiroi:allow model_port
    case Req.post(endpoint, headers: headers, body: "", retry: false, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} when status in [404, 410] ->
        :gone

      {:ok, %Req.Response{status: status}} ->
        {:error, Error.new(:gaia_push_failed, :gaia_push_refused, status: status)}

      {:error, exception} ->
        {:error, Error.caught(:gaia_push_failed, :gaia_push_transport, exception)}
    end
  end

  defp port(%URI{scheme: "https", port: 443}), do: ""
  defp port(%URI{port: nil}), do: ""
  defp port(%URI{port: port}), do: ":#{port}"

  @doc false
  # The VAPID JWT: ES256 over the push service's origin, a day at most
  # (twelve hours here), and the subject the push service may write to.
  def jwt(audience, private) do
    header = encode(%{typ: "JWT", alg: "ES256"})

    claims =
      encode(%{
        aud: audience,
        exp: System.os_time(:second) + @jwt_seconds,
        sub: Config.fetch!(:gaia, :vapid_subject)
      })

    input = header <> "." <> claims
    der = :crypto.sign(:ecdsa, :sha256, input, [private, :prime256v1])
    {:"ECDSA-Sig-Value", r, s} = :public_key.der_decode(:"ECDSA-Sig-Value", der)
    input <> "." <> Base.url_encode64(pad32(r) <> pad32(s), padding: false)
  end

  defp encode(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp pad32(n) do
    bin = :binary.encode_unsigned(n)
    :binary.copy(<<0>>, 32 - byte_size(bin)) <> bin
  end
end
