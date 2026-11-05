defmodule Oneiroi.Gaia.PushTest do
  @moduledoc """
  gaia#15: the witness's devices are told, content-free, when the resident
  writes in the chat unprompted. A device subscribes by its push service
  endpoint, held to the known services; a push is an empty POST signed
  with the platform's VAPID key; a device the service says is gone is
  unsubscribed.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Push
  alias Oneiroi.Gaia.Push.{Fake, WebPush}
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Sunna

  @apple "https://web.push.apple.com/QGuQyavXutnMjhCkC"

  setup do
    Fake.clear()
    on_exit(&Fake.clear/0)
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)
    {:ok, account: witness.id, actor: actor}
  end

  test "a device subscribes once at a known push service, and nowhere else", ctx do
    assert %{enabled: true, public_key: key} = Gaia.push_config()
    assert {:ok, <<4, _::binary-size(64)>>} = Base.url_decode64(key, padding: false)

    assert :ok = Gaia.subscribe_push(ctx.account, @apple, ctx.actor)
    assert :ok = Gaia.subscribe_push(ctx.account, @apple, ctx.actor)
    assert Gaia.push_subscriptions(ctx.account) == [@apple]

    for bad <- [
          "http://web.push.apple.com/x",
          "https://evil.example/x",
          "https://push.apple.com.evil.example/x",
          nil
        ] do
      assert {:error, %{kind: :gaia_push_endpoint_invalid}} =
               Gaia.subscribe_push(ctx.account, bad, ctx.actor)
    end

    assert :ok = Gaia.unsubscribe_push(ctx.account, @apple, ctx.actor)
    assert Gaia.push_subscriptions(ctx.account) == []
  end

  test "a push goes to every device, and a device the service says is gone is unsubscribed",
       ctx do
    fcm = "https://fcm.googleapis.com/fcm/send/abc"
    :ok = Gaia.subscribe_push(ctx.account, @apple, ctx.actor)
    :ok = Gaia.subscribe_push(ctx.account, fcm, ctx.actor)
    Fake.gone(fcm)

    assert [{@apple, :ok}, {^fcm, :gone}] = Gaia.push_now(ctx.account)
    assert Gaia.push_subscriptions(ctx.account) == [@apple]
  end

  test "the VAPID token is ES256 over the push service's origin, verifiable with the public key" do
    private = Push.private_key()

    [header, claims, signature] =
      "https://web.push.apple.com" |> WebPush.jwt(private) |> String.split(".")

    assert %{"alg" => "ES256", "typ" => "JWT"} =
             header |> Base.url_decode64!(padding: false) |> Jason.decode!()

    assert %{"aud" => "https://web.push.apple.com", "sub" => "https://" <> _, "exp" => exp} =
             claims |> Base.url_decode64!(padding: false) |> Jason.decode!()

    assert exp > System.os_time(:second)

    <<r::binary-size(32), s::binary-size(32)>> = Base.url_decode64!(signature, padding: false)

    der =
      :public_key.der_encode(
        :"ECDSA-Sig-Value",
        {:"ECDSA-Sig-Value", :binary.decode_unsigned(r), :binary.decode_unsigned(s)}
      )

    assert :crypto.verify(:ecdsa, :sha256, header <> "." <> claims, der, [
             Push.public_of(private),
             :prime256v1
           ])
  end

  test "a check-in's reply pushes to the witness's devices; his own message does not", ctx do
    resident = Fixtures.resident!(%{id: ctx.account})
    :ok = Gaia.store_key(ctx.account, "sk-or-test", ctx.actor)
    :ok = Gaia.subscribe_push(ctx.account, @apple, ctx.actor)
    Model.reply("Good morning.", for: resident.id)
    on_exit(fn -> Model.clear(for: resident.id) end)

    {:ok, key} = Kumbukumbu.main_session(resident.id, ctx.account, ctx.actor)
    assert {:ok, _} = Oneiroi.Brain.turn(resident.id, key, "hello", ctx.actor)
    Process.sleep(100)
    assert Fake.sent() == []

    {:ok, _} = Sunna.set_checkin(resident.id, nil, "morning", "12:00", ctx.actor)
    assert :ok = Sunna.tick(resident.id)
    assert eventually(fn -> Fake.sent() end) == [@apple]
  end

  defp eventually(read, tries \\ 50) do
    case read.() do
      [] when tries > 0 ->
        Process.sleep(20)
        eventually(read, tries - 1)

      value ->
        value
    end
  end
end
