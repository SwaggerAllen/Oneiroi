defmodule OneiroiWeb.ChatGPTImportTest do
  @moduledoc """
  sima-qian#47: a ChatGPT export's zip taken into the records: each
  conversation an imported session, the witness's words under the
  witness and the assistant's under `hands` named chatgpt with the model,
  the memories and gaps in a report filed in the library; an archive
  naming a path outside itself refused.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    witness = Actor.new(:witness, account.id)
    {:ok, token, _} = Oneiroi.Gaia.issue_token(account.id, "t", witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, id: resident.id, token: token}
  end

  defp zip(entries) do
    {:ok, {_name, bytes}} =
      :zip.create(
        ~c"export.zip",
        Enum.map(entries, fn {n, b} -> {String.to_charlist(n), b} end),
        [:memory]
      )

    bytes
  end

  defp upload(ctx, bytes) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> ctx.token)
    |> put_req_header("content-type", "application/zip")
    |> post("/v1/residents/#{ctx.id}/imports/chatgpt", bytes)
  end

  defp export do
    msg = fn id, parent, role, text, t, extra ->
      {id,
       %{
         "id" => id,
         "parent" => parent,
         "message" =>
           Map.merge(
             %{
               "author" => %{"role" => role},
               "create_time" => t,
               "content" => %{"content_type" => "text", "parts" => [text]},
               "metadata" => %{"model_slug" => if(role == "assistant", do: "gpt-4o")}
             },
             extra
           )
       }}
    end

    Jason.encode!([
      %{
        "id" => "c1",
        "title" => "Herons",
        "create_time" => 1_700_000_000.0,
        "current_node" => "u2",
        "mapping" =>
          Map.new([
            msg.("u1", nil, "user", "do herons sleep?", 1_700_000_000.0, %{}),
            msg.("m", "u1", "system", "", 1_700_000_000.5, %{
              "content" => %{
                "content_type" => "model_editable_context",
                "model_set_context" => "Likes herons."
              }
            }),
            msg.("a1", "m", "assistant", "Standing, mostly.", 1_700_000_001.0, %{}),
            msg.("u2", "a1", "user", "on one leg?", nil, %{})
          ])
      }
    ])
  end

  test "the conversations become imported sessions under the right speakers; the report names memories and gaps",
       ctx do
    bytes = zip([{"conversations.json", export()}, {"chat.html", "<html></html>"}])

    assert %{"conversations" => 1, "messages" => 3, "context" => 1, "report_path" => path} =
             upload(ctx, bytes) |> json_response(200)

    [session] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "imported"))
    {:ok, _s, messages} = Kumbukumbu.transcript({:resident, ctx.id}, session.key)

    assert [
             %{role: "user", content: "do herons sleep?", instant_inferred: false},
             %{role: "assistant", content: "Standing, mostly.", instant_inferred: false},
             %{role: "user", content: "on one leg?", instant_inferred: true}
           ] = Enum.map(messages, &Map.take(&1, [:role, :content, :instant_inferred]))

    # A time the export never carried reads as unknown, never as a clock (kumbukumbu#50).
    turn = %{
      resident_id: ctx.id,
      session_key: "k",
      turn_ref: "t",
      resident: Actor.new(:resident, ctx.id),
      started_at: Clock.now()
    }

    read =
      Tools.run("transcript_read", Jason.encode!(%{session: session.key}), turn)

    assert read =~ "user, time unknown: on one leg?"

    assert {:ok, %{content: report}} = Seshat.document(ctx.id, path)
    assert report =~ "Conversations: 1"
    assert report =~ "Likes herons."
    assert report =~ "gpt-4o (1)"
  end

  test "an archive naming a path outside itself is refused; so is a zip with no conversations",
       ctx do
    assert %{"error" => %{"kind" => "sima_qian_import_unreadable"}} =
             upload(ctx, zip([{"../evil/conversations.json", "[]"}])) |> json_response(422)

    assert %{"error" => %{"kind" => "sima_qian_import_unreadable"}} =
             upload(ctx, zip([{"user.json", "{}"}])) |> json_response(422)

    assert %{"error" => %{"kind" => "sima_qian_import_unreadable"}} =
             upload(ctx, "not a zip at all") |> json_response(422)
  end
end
