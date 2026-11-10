defmodule OneiroiWeb.ThemeRoutesTest do
  @moduledoc """
  seshat#56 (design/ui-server-work.md S7): the theme's three seeds are
  the witness's, kept as THEME.md at her root; he sets them with a note
  and an unreadable set is refused 422 with the checks. She proposes
  with `theme_propose`, checked before it is filed; a filed proposal
  waits on his list (brain#80) with the seeds a preview needs; he
  accepts (the file is written) or declines with a note, and she is
  told by a letter. Nobody writes THEME.md as a plain document.
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
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", witness)
    {:ok, token, _} = Oneiroi.Gaia.issue_token(account.id, "t", witness)
    {:ok, key} = Kumbukumbu.main_session(resident.id, account.id, witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    turn = %{
      resident_id: resident.id,
      session_key: key,
      turn_ref: "t-theme",
      started_at: Clock.now(),
      resident: Actor.new(:resident, resident.id, "fake/model")
    }

    {:ok,
     id: resident.id,
     token: token,
     me: witness,
     lily: Actor.new(:resident, resident.id),
     turn: turn,
     dir: dir}
  end

  defp as(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)
  defp path(ctx), do: "/v1/residents/#{ctx.id}/theme"
  defp tool(ctx, args), do: Tools.run("theme_propose", Jason.encode!(args), ctx.turn)

  @hers %{ground: "#0d0d0d", resident: "#7ee7f5", witness: "#d8b4fe"}

  test "the default until set; his set is checked, written as THEME.md, and read back", ctx do
    assert %{
             "seeds" => %{"ground" => "#0a0a10", "resident" => "#d8b4fe", "witness" => "#7ee7f5"},
             "source" => "default",
             "ok" => true,
             "file" => "THEME.md",
             "proposals" => []
           } = ctx.token |> as() |> get(path(ctx)) |> json_response(200)

    # Unreadable: refused with the checks, and nothing written.
    body =
      ctx.token
      |> as()
      |> put(path(ctx), %{
        ground: "#8a8a8a",
        resident: "#d8b4fe",
        witness: "#7ee7f5",
        note: "grey"
      })
      |> json_response(422)

    assert %{"kind" => "seshat_theme_unreadable", "checks" => checks} = body["error"]
    assert %{"name" => "text on ground", "passed" => false} = hd(checks)
    refute File.exists?(Path.join(ctx.dir, "THEME.md"))

    assert %{"error" => %{"kind" => "seshat_theme_invalid"}} =
             ctx.token
             |> as()
             |> put(path(ctx), %{ground: "black", resident: "#d8b4fe", witness: "#7ee7f5"})
             |> json_response(422)

    set = %{ground: "#000000", resident: "#FF5C8A", witness: "#5cff9d", note: "night"}

    assert %{
             "seeds" => %{"ground" => "#000000", "resident" => "#ff5c8a", "witness" => "#5cff9d"},
             "source" => "file",
             "ok" => true
           } = ctx.token |> as() |> put(path(ctx), set) |> json_response(200)

    file = File.read!(Path.join(ctx.dir, "THEME.md"))
    assert file =~ ~s(ground: "#000000")
    assert file =~ "Set by the witness"
    assert file =~ "night"
    assert {:ok, %{ground: "#000000"}} = Seshat.Theme.parse(file)

    # A plain document write of it is refused, his and hers.
    assert {:error, %{kind: :seshat_theme_file}} =
             Seshat.write(ctx.id, "THEME.md", "---\nground: \"#ffffff\"\n---\n", ctx.me)

    assert {:error, %{kind: :seshat_theme_file}} =
             Seshat.write(ctx.id, "THEME.md", "x", ctx.lily)
  end

  test "her proposal: refused in words when unreadable; filed, on his list with the seeds; accepted, written and told",
       ctx do
    refused =
      tool(ctx, %{ground: "#0a0a10", resident: "#d8b4fe", witness: "#d4b0fa", note: "twins"})

    assert refused =~ Tools.not_done()
    assert refused =~ "her colour apart from his"
    assert refused =~ "FAILS"
    assert [] = Seshat.theme_proposals(ctx.id)

    filed = tool(ctx, Map.put(@hers, :note, "warmer"))
    assert filed =~ "Proposed as theme proposal #1"
    assert filed =~ "text on ground"

    # One at a time.
    assert tool(ctx, Map.put(@hers, :note, "again")) =~ "one theme proposal waits"

    assert [
             %{
               "kind" => "theme_proposal",
               "ref" => 1,
               "screen" => "theme",
               "about" => %{
                 "seeds" => %{
                   "ground" => "#0d0d0d",
                   "resident" => "#7ee7f5",
                   "witness" => "#d8b4fe"
                 },
                 "note" => "warmer"
               }
             }
           ] =
             ctx.token
             |> as()
             |> get("/v1/residents/#{ctx.id}/needs_you")
             |> json_response(200)
             |> Enum.filter(&(&1["kind"] == "theme_proposal"))

    # Only he answers.
    assert {:error, %{kind: :seshat_theme_answer_invalid}} =
             Seshat.answer_theme(ctx.id, 1, true, "mine", ctx.lily)

    theme =
      ctx.token
      |> as()
      |> post("#{path(ctx)}/proposals/1/answer", %{agree: true, note: "lovely"})
      |> json_response(200)

    assert %{"seeds" => %{"ground" => "#0d0d0d"}, "source" => "file"} = theme
    assert [%{"number" => 1, "agree" => true, "answer_note" => "lovely"}] = theme["proposals"]
    assert File.read!(Path.join(ctx.dir, "THEME.md")) =~ "Proposed by the resident as #1: warmer"

    assert Enum.any?(
             Kumbukumbu.letters(ctx.id),
             &(&1.text =~ "Your witness accepted your theme proposal #1")
           )

    # Answered, it waits on nobody; answered again, refused.
    refute Enum.any?(Oneiroi.Brain.needs_you(ctx.id), &(&1.kind == "theme_proposal"))

    assert %{"error" => %{"kind" => "seshat_theme_answer_invalid"}} =
             ctx.token
             |> as()
             |> post("#{path(ctx)}/proposals/1/answer", %{agree: false, note: "no"})
             |> json_response(422)
  end

  test "declined, the theme stays and she is told why", ctx do
    assert tool(ctx, Map.put(@hers, :note, "warmer")) =~ "#1"

    assert %{"source" => "default"} =
             ctx.token
             |> as()
             |> post("#{path(ctx)}/proposals/1/answer", %{agree: false, note: "too bright"})
             |> json_response(200)

    refute File.exists?(Path.join(ctx.dir, "THEME.md"))

    assert Enum.any?(
             Kumbukumbu.letters(ctx.id),
             &(&1.text =~ "declined your theme proposal #1; the theme stays as it was: too bright")
           )

    # A note is required.
    assert tool(ctx, Map.put(@hers, :note, "")) =~ Tools.not_done()
  end

  test "a hand-edited THEME.md is read from the file; one without three seeds falls back", ctx do
    File.mkdir_p!(ctx.dir)

    File.write!(
      Path.join(ctx.dir, "THEME.md"),
      "---\nground: '#121212'\nresident: '#BB86FC'\nwitness: '#03dac6'\n---\n"
    )

    assert %{"seeds" => %{"resident" => "#bb86fc"}, "source" => "file", "ok" => false} =
             ctx.token |> as() |> get(path(ctx)) |> json_response(200)

    File.write!(Path.join(ctx.dir, "THEME.md"), "---\nground: '#121212'\n---\n")
    assert %{"source" => "default"} = ctx.token |> as() |> get(path(ctx)) |> json_response(200)
  end
end
