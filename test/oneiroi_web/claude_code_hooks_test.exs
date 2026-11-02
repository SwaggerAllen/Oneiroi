defmodule OneiroiWeb.ClaudeCodeHooksTest do
  @moduledoc """
  The Claude Code plugin as a witness's machine runs it (spec §8, brain
  #42): each hook command exactly as the plugin's `hooks/hooks.json`
  holds it, run by a shell with what Claude Code gives a plugin hook (the
  plugin's root and data directories, its options as
  `CLAUDE_PLUGIN_OPTION_<KEY>`) and Claude Code's payloads on stdin (the
  docs' examples under `sdk/claude-code/fixtures/`), against the real
  endpoint on a loopback port. Asserted on what the platform
  stored, not on the calls: the witness's words and the reply are in the
  transcript, the turn's context is its `ContextAssembled`, and the token
  is in no output, no state file and no recorded payload.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model

  @sdk Path.expand("../../sdk/claude-code", __DIR__)

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    id = resident.id
    actor = Actor.new(:witness, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul\n\nCurious about herons.", %{}, actor)
    {:ok, token} = AgathosDaimon.register_adapter(id, "laptop", "brain", actor)
    Model.clear()
    on_exit(fn -> Model.clear(for: id) end)

    # A bookmark from an earlier conversation, so the index has a line.
    {:ok, main} = Kumbukumbu.main_session(id, account.id, actor)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        id,
        main,
        "t-earlier",
        at,
        [%{role: :user, content: "look, a heron", sent_at: at, actor: actor}],
        actor
      )

    {:ok, 1} =
      Kumbukumbu.add_bookmark(
        id,
        %{session_key: main, anchor_ref: "t-earlier", line: "the heron at the weir"},
        Actor.new(:resident, id, "fake/model")
      )

    server =
      start_supervised!({Bandit, plug: OneiroiWeb.Endpoint, ip: {127, 0, 0, 1}, port: 0})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    root = Path.join(System.tmp_dir!(), "oneiroi-hooks-#{System.unique_integer([:positive])}")
    project = Path.join(root, "project")
    File.mkdir_p!(project)
    on_exit(fn -> File.rm_rf!(root) end)

    url = "http://127.0.0.1:#{port}"

    # curl as the hooks find it on PATH, recording its arguments first,
    # so the test reads the command line the process list would show.
    shim = Path.join(root, "bin")
    File.mkdir_p!(shim)

    File.write!(Path.join(shim, "curl"), """
    #!/usr/bin/env bash
    printf '%s\\n' "$*" >> "$ONEIROI_TEST_ARGV"
    exec #{System.find_executable("curl")} "$@"
    """)

    File.chmod!(Path.join(shim, "curl"), 0o755)

    {:ok,
     id: id,
     account: account,
     token: token,
     url: url,
     project: project,
     data: Path.join(root, "data"),
     shim: shim,
     argv: Path.join(root, "argv.log"),
     recorded: Path.join(root, "recorded"),
     outputs: []}
  end

  defp fixture(name, changes) do
    [@sdk, "fixtures", name <> ".json"]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
    |> Map.merge(changes)
  end

  # The plugin's options as Claude Code exports them to a hook.
  defp options(ctx),
    do: [
      {"CLAUDE_PLUGIN_OPTION_URL", ctx.url},
      {"CLAUDE_PLUGIN_OPTION_RESIDENT", ctx.id},
      {"CLAUDE_PLUGIN_OPTION_TOKEN", ctx.token},
      {"CLAUDE_PLUGIN_OPTION_RECORD_FIXTURES", ctx.recorded}
    ]

  # Each command for the event exactly as the plugin's hooks file holds
  # it, run as Claude Code runs a shell-form plugin hook: by a shell, with
  # the payload on stdin and the plugin's variables in the environment.
  # Returns each command's output.
  defp hook(ctx, event, payload, env \\ nil) do
    hooks = @sdk |> Path.join("hooks/hooks.json") |> File.read!() |> Jason.decode!()
    stdin = Path.join(ctx.project, "payload-#{System.unique_integer([:positive])}.json")
    File.write!(stdin, Jason.encode!(payload))

    for %{"hooks" => hooks} <- hooks["hooks"][event], %{"command" => command} <- hooks do
      {out, status} =
        System.cmd("bash", ["-c", command <> ~s( < "$ONEIROI_TEST_STDIN")],
          env:
            [
              {"CLAUDE_PROJECT_DIR", ctx.project},
              {"CLAUDE_PLUGIN_ROOT", @sdk},
              {"CLAUDE_PLUGIN_DATA", ctx.data},
              {"ONEIROI_TEST_STDIN", stdin},
              {"ONEIROI_TEST_ARGV", ctx.argv},
              {"PATH", ctx.shim <> ":" <> System.get_env("PATH")},
              {"ONEIROI_RECORD_FIXTURES", nil},
              {"http_proxy", nil},
              {"HTTP_PROXY", nil},
              {"https_proxy", nil},
              {"HTTPS_PROXY", nil},
              {"ALL_PROXY", nil}
            ] ++ (env || options(ctx)),
          stderr_to_stdout: true
        )

      # Exit 2 would block the witness's prompt or keep Claude going.
      assert status == 0, "#{command} exited #{status}: #{out}"
      refute out =~ ctx.token, "#{command} printed the token"
      out
    end
  end

  defp session_key(ctx, session),
    do: ctx.data |> Path.join("#{session}/key") |> File.read!()

  defp transcript(ctx, key) do
    {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.account.id}, key)
    Enum.map(messages, &{&1.role, &1.content, &1.actor_kind})
  end

  defp files_under(dir),
    do: dir |> Path.join("**") |> Path.wildcard(match_dot: true) |> Enum.filter(&File.regular?/1)

  test "a session from the docs' payloads: the prefix at the start, the turn's context on the prompt, and both parties' words captured",
       ctx do
    session = "s-#{System.unique_integer([:positive])}"
    start = fixture("session_start", %{"session_id" => session, "source" => "startup"})

    prefix = ctx |> hook("SessionStart", start) |> Enum.join("\n")
    assert prefix =~ "You are Lily"
    assert prefix =~ "Curious about herons."
    assert prefix =~ "mcp__plugin_oneiroi_oneiroi__bookmark_add"
    refute prefix =~ "the heron at the weir"

    prompt =
      fixture("user_prompt_submit", %{
        "session_id" => session,
        "prompt" => "Did you see the heron again?"
      })

    [context] = hook(ctx, "UserPromptSubmit", prompt)
    assert context =~ "the heron at the weir"
    # The session holds the prefix, so the turn does not repeat it.
    refute context =~ "Curious about herons."

    key = session_key(ctx, session)
    assert {^key, ref} = Kumbukumbu.open_turn(ctx.id, "laptop")

    labels =
      {:account, ctx.account.id} |> Kumbukumbu.injections(ref) |> Enum.map(& &1.label)

    for label <- ~w(prompt SOUL.md runtime index),
        do: assert(label in labels, "#{label} missing from #{inspect(labels)}")

    stop =
      fixture("stop", %{
        "session_id" => session,
        "last_assistant_message" => "I did, standing in the shallows."
      })

    hook(ctx, "Stop", stop)

    assert transcript(ctx, key) == [
             {"user", "Did you see the heron again?", "witness"},
             {"assistant", "I did, standing in the shallows.", "resident"}
           ]

    assert nil == Kumbukumbu.open_turn(ctx.id, "laptop")

    # Recorded payloads, one for each event, and the token in no file
    # the hooks wrote.
    assert ctx.recorded
           |> files_under()
           |> Enum.map(&(&1 |> Path.basename() |> hd_word()))
           |> Enum.sort() ==
             ["SessionStart", "Stop", "UserPromptSubmit"]

    for file <- files_under(ctx.recorded) ++ files_under(ctx.data),
        do: refute(File.read!(file) =~ ctx.token, "#{file} holds the token")

    # Nor on any curl command line: it reads the header from its stdin.
    argv = File.read!(ctx.argv)
    assert argv =~ "/v1/residents/#{ctx.id}/turn-start"
    refute argv =~ ctx.token
  end

  defp hd_word(name), do: name |> String.split("-") |> hd()

  test "a turn that cannot be delivered is spooled and the next stop delivers it once; a repeated stop captures nothing twice",
       ctx do
    session = "s-#{System.unique_integer([:positive])}"

    hook(
      ctx,
      "SessionStart",
      fixture("session_start", %{"session_id" => session, "source" => "startup"})
    )

    say = fn words ->
      hook(
        ctx,
        "UserPromptSubmit",
        fixture("user_prompt_submit", %{"session_id" => session, "prompt" => words})
      )
    end

    stop = fn reply, env ->
      hook(
        ctx,
        "Stop",
        fixture("stop", %{
          "session_id" => session,
          "stop_hook_active" => false,
          "last_assistant_message" => reply
        }),
        env
      )
    end

    say.("first words")
    key = session_key(ctx, session)
    # Nothing answers on port 1: the environment's value wins over the file's.
    stop.(
      "first reply",
      List.keystore(
        options(ctx),
        "CLAUDE_PLUGIN_OPTION_URL",
        0,
        {"CLAUDE_PLUGIN_OPTION_URL", "http://127.0.0.1:1"}
      )
    )

    assert transcript(ctx, key) == []
    assert [_spooled] = Path.wildcard(Path.join(ctx.data, "#{session}/spool/*.json"))

    say.("second words")
    stop.("second reply", nil)

    assert transcript(ctx, key) == [
             {"user", "first words", "witness"},
             {"assistant", "first reply", "resident"},
             {"user", "second words", "witness"},
             {"assistant", "second reply", "resident"}
           ]

    assert [] = Path.wildcard(Path.join(ctx.data, "**/spool/*.json"))

    # Stop again with nothing pending, and with another hook's
    # continuation repeating the same reply: nothing is sent at all. Read
    # off what curl was asked, not the transcript: its unique key is the
    # message's instant and content, so a repeat within the same second
    # would be dropped there whether or not the hook sent it.
    posts = fn ->
      ctx.argv |> File.read!() |> String.split("\n") |> Enum.count(&(&1 =~ "/turns"))
    end

    sent = posts.()
    stop.("second reply", nil)

    hook(
      ctx,
      "Stop",
      fixture("stop", %{"session_id" => session, "last_assistant_message" => "second reply"})
    )

    assert posts.() == sent
    assert length(transcript(ctx, key)) == 4

    # A continuation with further words is taken, once.
    hook(
      ctx,
      "Stop",
      fixture("stop", %{"session_id" => session, "last_assistant_message" => "and more"})
    )

    hook(
      ctx,
      "Stop",
      fixture("stop", %{"session_id" => session, "last_assistant_message" => "and more"})
    )

    assert posts.() == sent + 1
    assert {"assistant", "and more", "resident"} == List.last(transcript(ctx, key))

    # A Stop with nothing pending that no other hook continued is no turn.
    stop.("words of no turn", nil)
    assert posts.() == sent + 1

    # A prompt whose Stop never came (an interrupt) keeps the witness's
    # words: the next prompt captures them alone.
    say.("interrupted words")
    say.("after the interrupt")
    stop.("answer", nil)

    assert Enum.take(transcript(ctx, key), -3) == [
             {"user", "interrupted words", "witness"},
             {"user", "after the interrupt", "witness"},
             {"assistant", "answer", "resident"}
           ]
  end

  test "sessions open at once, two in one folder and one in another, interleaved: each its own conversation, state, spool and turn, called by its folder's base name",
       ctx do
    n = System.unique_integer([:positive])
    here = "/Users/allen/src/Oneiroi"
    there = "/Users/allen/src/catapult"
    sessions = [{"s1-#{n}", here}, {"s2-#{n}", here}, {"s3-#{n}", there}]
    [{s1, _}, {s2, _}, {s3, _}] = sessions
    cwd = Map.new(sessions)

    payload = fn name, session, changes ->
      fixture(name, Map.merge(%{"session_id" => session, "cwd" => cwd[session]}, changes))
    end

    say = fn session, words ->
      [out] =
        hook(
          ctx,
          "UserPromptSubmit",
          payload.("user_prompt_submit", session, %{"prompt" => words})
        )

      out
    end

    stop = fn session, reply, env ->
      hook(
        ctx,
        "Stop",
        payload.("stop", session, %{
          "stop_hook_active" => false,
          "last_assistant_message" => reply
        }),
        env
      )
    end

    for {session, _cwd} <- sessions,
        do:
          hook(ctx, "SessionStart", payload.("session_start", session, %{"source" => "startup"}))

    one = say.(s1, "one: the tests")
    three = say.(s3, "three: the build")
    two = say.(s2, "two: the docs")

    [k1, k2, k3] = Enum.map([s1, s2, s3], &session_key(ctx, &1))
    assert Enum.uniq([k1, k2, k3]) == [k1, k2, k3]
    ref = fn session -> ctx.data |> Path.join("#{session}/turn") |> File.read!() end

    # Each is told where it is, which others are open, and its own turn.
    for {out, session} <- [{one, s1}, {two, s2}, {three, s3}],
        do: assert(out =~ "This turn is `#{ref.(session)}`.")

    assert two =~ "This conversation is in Claude Code, in the folder Oneiroi."

    assert two =~
             "Claude Code in the folder Oneiroi, another conversation in this same folder (a turn in flight)"

    assert two =~ "Claude Code in the folder catapult (a turn in flight)"
    assert three =~ "This conversation is in Claude Code, in the folder catapult."
    refute Enum.any?([one, two, three], &(&1 =~ "/Users/allen"))

    for {key, label} <- [{k1, "Oneiroi"}, {k2, "Oneiroi"}, {k3, "catapult"}],
        do:
          assert(
            {:ok, %{kind: "adapter", label: ^label, runtime: "claude-code"}, _} =
              Kumbukumbu.transcript({:resident, ctx.id}, key)
          )

    # Her memory tools, called from session one while three's and two's
    # turns are newer, land on one's turn when they name it.
    %{"result" => %{"content" => [%{"text" => "Bookmarked as #2."}]}} =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> ctx.token)
      |> post("/mcp", %{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: %{name: "bookmark_add", arguments: %{line: "the tests", turn: ref.(s1)}}
      })
      |> json_response(200)

    one_ref = ref.(s1)

    assert {:ok, %{session_key: ^k1, anchor_ref: ^one_ref}, _span} =
             Kumbukumbu.bookmark(ctx.id, 2)

    # Three stops while the platform is away: its turn waits in its own
    # spool. One's stop delivers its own, then three's, whose conversation
    # is open; two's spool is never touched by either.
    down =
      List.keystore(
        options(ctx),
        "CLAUDE_PLUGIN_OPTION_URL",
        0,
        {"CLAUDE_PLUGIN_OPTION_URL", "http://127.0.0.1:1"}
      )

    stop.(s3, "three: green", down)
    assert [_] = Path.wildcard(Path.join(ctx.data, "#{s3}/spool/*.json"))
    assert [] = Path.wildcard(Path.join(ctx.data, "#{s1}/spool/*.json"))
    assert transcript(ctx, k3) == []

    stop.(s1, "one: passing", nil)
    stop.(s2, "two: written", nil)

    assert transcript(ctx, k1) == [
             {"user", "one: the tests", "witness"},
             {"assistant", "one: passing", "resident"}
           ]

    assert transcript(ctx, k2) == [
             {"user", "two: the docs", "witness"},
             {"assistant", "two: written", "resident"}
           ]

    assert transcript(ctx, k3) == [
             {"user", "three: the build", "witness"},
             {"assistant", "three: green", "resident"}
           ]

    assert [] = Path.wildcard(Path.join(ctx.data, "**/spool/*.json"))

    # The folder's path stays on the machine: no state file holds it.
    for file <- files_under(ctx.data),
        do: refute(File.read!(file) =~ "/Users/allen", "#{file} holds the path")
  end

  test "a spool an earlier build left at the data directory's root is delivered to the session it names",
       ctx do
    session = "s-#{System.unique_integer([:positive])}"

    hook(
      ctx,
      "SessionStart",
      fixture("session_start", %{"session_id" => session, "source" => "startup"})
    )

    hook(
      ctx,
      "UserPromptSubmit",
      fixture("user_prompt_submit", %{"session_id" => session, "prompt" => "now"})
    )

    key = session_key(ctx, session)

    legacy = Path.join(ctx.data, "spool")
    File.mkdir_p!(legacy)

    File.write!(
      Path.join(legacy, "20261101T000000Z-1-1.json"),
      Jason.encode!(%{
        claude_session: session,
        body: %{
          session_key: key,
          started_at: "2026-10-26T11:00:00Z",
          messages: [%{role: "user", content: "left behind", sent_at: "2026-10-26T11:00:00Z"}]
        }
      })
    )

    hook(
      ctx,
      "Stop",
      fixture("stop", %{
        "session_id" => session,
        "stop_hook_active" => false,
        "last_assistant_message" => "then"
      })
    )

    assert {"user", "left behind", "witness"} in transcript(ctx, key)
    assert [] = Path.wildcard(Path.join(ctx.data, "**/*.json"))
  end

  test "with the plugin's options unset a hook does nothing at all: no output, no state, no recording",
       ctx do
    session = "s-#{System.unique_integer([:positive])}"
    payload = fixture("user_prompt_submit", %{"session_id" => session})

    assert [""] = hook(ctx, "UserPromptSubmit", payload, [])

    assert ["", "", "", "", "", "", "", ""] =
             hook(ctx, "SessionStart", fixture("session_start", %{"session_id" => session}), [])

    assert [""] = hook(ctx, "Stop", fixture("stop", %{"session_id" => session}), [])
    assert files_under(ctx.data) == []
    assert files_under(ctx.recorded) == []
  end
end
