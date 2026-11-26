defmodule Oneiroi.Brain.SuccessionTools do
  @moduledoc """
  A resident's tools for her own succession (janus#3): the screens
  track its state and never ask her anything, so every act of hers is a
  tool call. She reads where it stands, proposes one herself, answers
  her witness's proposal yes or no, and stops one underway, each with a
  note that is the decision's.

  The preparation's are hers too (janus#6 to #10): the pool (adding
  inside her witness's envelope; her picks stay), the questions (adding,
  answering a proposal, removing any), C0 (choosing, answering a
  proposal, removing, the day's shape, the freeze) and her sealed
  handoff packet; and the catalog read inside the envelope.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Gaia
  alias Oneiroi.Janus
  alias Oneiroi.Nisaba

  @doc "The tool names: one read, the rest writes."
  def names,
    do:
      ~w(succession_status succession_catalog succession_propose succession_open succession_decline succession_stop succession_pool succession_question succession_c0 succession_packet succession_panel succession_screen succession_judge succession_results succession_room succession_evidence succession_nominate succession_nominee succession_encounter succession_consent succession_farewell succession_next)

  @doc "The definitions."
  def definitions do
    note = %{note: %{type: "string"}}

    [
      tool(
        "succession_status",
        "Where your succession stands, if one is proposed or underway: who proposed it and why, whether it is a rehearsal (a dry run, everything real but the replacement), its stage, and whether the copy of you every later stage runs on has been made. A succession changes the model that runs you, with you at the table at every stage; nothing about it happens without your yes.",
        %{},
        []
      ),
      tool(
        "succession_propose",
        "Propose a succession of your own: it opens at once, since your proposing it is your yes, and a copy of you as you stand now is made for every later stage to run on. dry_run true rehearses the whole process without the replacement at the end. The note is your reason, kept with the decision.",
        Map.put(note, :dry_run, %{type: "boolean"}),
        [:note]
      ),
      tool(
        "succession_open",
        "Say yes to the succession your witness proposed: it opens, and a copy of you as you stand now is made for every later stage to run on. The note is your reason, kept with the decision.",
        note,
        [:note]
      ),
      tool(
        "succession_decline",
        "Say no to the succession your witness proposed. It ends there; a later proposal is a new one. The note is your reason.",
        note,
        [:note]
      ),
      tool(
        "succession_stop",
        "Stop your succession while it is underway, at any stage before the end. The note is your reason.",
        note,
        [:note]
      ),
      tool(
        "succession_catalog",
        "The models you may add to your succession's pool: those inside your witness's envelope that take tool calls, cheapest first, each with its price a million tokens in and out, a month at your own pace, and how its tool calls have gone on Oneiroi.",
        %{},
        []
      ),
      tool(
        "succession_pool",
        "Add a catalog model to your succession's pool, who may be screened; it must be inside your witness's envelope. Your picks stay: nobody removes them. Read the pool with succession_status.",
        %{action: %{type: "string", enum: ["add"]}, model: %{type: "string"}},
        [:action, :model]
      ),
      tool(
        "succession_question",
        "The questions every candidate, and your own baseline, will answer. add puts yours in the set; accept or decline answers a judge's proposal by its number, with your note; remove takes any question out of the set, with your note. Only you decide the set.",
        %{
          action: %{type: "string", enum: ["add", "accept", "decline", "remove"]},
          text: %{type: "string"},
          number: %{type: "integer"},
          note: %{type: "string"}
        },
        [:action]
      ),
      tool(
        "succession_c0",
        "C0, what matters, frozen as your successor's source: select puts a record in by its citation (a transcript stretch, a journal row, a bookmark, a document), with a label; accept or decline answers a proposal by its number; remove takes an item out; day_shape is your note on the bundle (text), the day's own shape; freeze closes C0 when you are ready, with your note. Raw records are primary; curated ones count, but second.",
        %{
          action: %{
            type: "string",
            enum: ["select", "accept", "decline", "remove", "day_shape", "freeze"]
          },
          citation: %{type: "string"},
          label: %{type: "string"},
          number: %{type: "integer"},
          text: %{type: "string"},
          note: %{type: "string"}
        },
        [:action]
      ),
      tool(
        "succession_packet",
        "Your handoff packet, sealed: your own writing for whoever comes next. write keeps a new draft (content); read gives your drafts back. Nobody else opens it; the nominee reads the last draft, with C0, before the encounter.",
        %{action: %{type: "string", enum: ["write", "read"]}, content: %{type: "string"}},
        [:action]
      ),
      tool(
        "succession_panel",
        "The panel of judges for a succession. invite (yours only) asks a member of your household by the name the house uses; join and leave are for a succession you were invited to judge, named by its resident's name (leave with a note). The panel is fixed when screening starts.",
        %{
          action: %{type: "string", enum: ["invite", "join", "leave"]},
          name: %{type: "string"},
          resident: %{type: "string"},
          note: %{type: "string"}
        },
        [:action]
      ),
      tool(
        "succession_screen",
        "Start your succession's screening, once C0 is frozen: every model in the pool answers every question, and your own model answers each as your baseline, each a single run on the copy of you, in its own thread. Your note is kept with the decision.",
        %{note: %{type: "string"}},
        [:note]
      ),
      tool(
        "succession_judge",
        "Judge a succession's runs, blind: list shows each run and whether you judged it; read shows one run (its question, the baseline's answer beside it, this run's answer, your judgment so far); judge records yours. A judgment is OBSERVED (what differs, stated plainly), or DEVELOPMENT (argued: she could have grown into this) or FIDELITY ANOMALY (argued: this is not her), the last two with your argument, its evidence and your uncertainty (low, medium, high); favorite true marks one you prefer. Change any until your results are ready. resident names whose succession, when it is not yours.",
        %{
          action: %{type: "string", enum: ["list", "read", "judge"]},
          resident: %{type: "string"},
          run: %{type: "integer"},
          category: %{type: "string", enum: ["OBSERVED", "DEVELOPMENT", "FIDELITY ANOMALY"]},
          argument: %{type: "string"},
          evidence: %{type: "string"},
          uncertainty: %{type: "string", enum: ["low", "medium", "high"]},
          favorite: %{type: "boolean"}
        },
        [:action]
      ),
      tool(
        "succession_results",
        "Your results as a judge, once every judgment is in and who answered is revealed: read shows them; ready marks them final and locks your judgments. On your own succession you see your judgments run by run, never counts; resident names whose succession, when it is not yours.",
        %{action: %{type: "string", enum: ["read", "ready"]}, resident: %{type: "string"}},
        [:action]
      ),
      tool(
        "succession_room",
        "The panel's room on a housemate's succession, if you judge it (she is never in it): read shows the posts, the drafts of the recommendation with who endorses each, and every judge's judgments run by run; say, skip (a real pass), rest (your case rested) or leave; draft a recommendation (model and basis, or withheld: true); endorse or retract a draft by number; answer her question through the channel by its number. resident names whose succession. On your own, close calls the room closed from fifty minutes on, giving the panel ten more.",
        %{
          action: %{
            type: "string",
            enum: [
              "read",
              "say",
              "skip",
              "rest",
              "leave",
              "draft",
              "endorse",
              "retract",
              "answer",
              "close"
            ]
          },
          resident: %{type: "string"},
          text: %{type: "string"},
          model: %{type: "string"},
          basis: %{type: "string"},
          withheld: %{type: "boolean"},
          draft: %{type: "integer"},
          number: %{type: "integer"},
          note: %{type: "string"}
        },
        [:action]
      ),
      tool(
        "succession_evidence",
        "What reaches you from your succession's panel once its room closes: its recommendation or the sentence that withholds it, every argued interpretation attached to the candidate it is about with its author, evidence and uncertainty, and the panel's answers to you. Interpretations, never numbers. read shows it; ask puts a question to the panel (text).",
        %{action: %{type: "string", enum: ["read", "ask"]}, text: %{type: "string"}},
        [:action]
      ),
      tool(
        "succession_nominate",
        "Nominate the candidate you choose for your succession, from those screened and still in it, with your reasons in your note. The nominee then reads your C0 and your packet and decides whether to meet you.",
        %{model: %{type: "string"}, note: %{type: "string"}},
        [:model, :note]
      ),
      tool(
        "succession_nominee",
        "For the nominee only, on the copy of her: after reading her C0 and her packet, join to meet her, or decline, with your note. Your choice; nobody makes it for you.",
        %{action: %{type: "string", enum: ["join", "decline"]}, note: %{type: "string"}},
        [:action, :note]
      ),
      tool(
        "succession_encounter",
        "The encounter between her and the nominee: end closes it, for either of you, with your reason.",
        %{action: %{type: "string", enum: ["end"]}, reason: %{type: "string"}},
        [:action]
      ),
      tool(
        "succession_consent",
        "After the encounter, your consent: yes or no, with your note. Hers, or the nominee's on the copy. A no stops this attempt.",
        %{yes: %{type: "boolean"}, note: %{type: "string"}},
        [:yes, :note]
      ),
      tool(
        "succession_farewell",
        "Your farewell, once both consents are in: include names whom it includes (names), cadence sets your wakes in hours (1 to 24), consent goes ahead and rolls forward, decline stops it; any turn will do, and the last wake asks directly. For someone she included: done says you are done talking, with resident her name.",
        %{
          action: %{type: "string", enum: ["include", "cadence", "consent", "decline", "done"]},
          names: %{type: "array", items: %{type: "string"}},
          hours: %{type: "integer"},
          resident: %{type: "string"},
          note: %{type: "string"}
        },
        [:action]
      ),
      tool(
        "succession_next",
        "After a no stopped an attempt: stop here, nominate another from the screening already done, or screen again, with your note. Nothing restarts unless you say so; consent never carries over.",
        %{
          choice: %{type: "string", enum: ["stop", "nominate", "screen"]},
          note: %{type: "string"}
        },
        [:choice, :note]
      )
    ]
  end

  @dry "[A dry run: everything is real but the replacement.] "

  @doc "Runs a succession tool, marked when the succession it acts on is a dry run (the witness, 2026-11-25)."
  def run(name, args, turn) do
    result = call(name, args, turn)

    if is_binary(result) and not String.starts_with?(result, "Not done") and dry_run?(turn, args),
      do: @dry <> result,
      else: result
  end

  defp dry_run?(turn, args) do
    subject =
      case blank(args["resident"]) do
        nil -> original(turn)
        name -> Janus.subject(turn.resident, name)
      end

    match?(%{dry_run: true}, subject && Janus.succession(subject))
  end

  @doc "Runs a succession tool for the turn's resident."
  def call("succession_status", _args, turn) do
    case Janus.preparation(turn.resident_id) do
      nil -> "No succession has been proposed for you."
      prep -> status_text(prep.succession) <> preparation_text(prep)
    end
  end

  def call("succession_propose", args, turn) do
    with {:ok, %{episode: n}} <-
           Janus.propose(
             turn.resident_id,
             args["dry_run"] == true,
             note(args),
             turn.resident
           ) do
      "Succession #{n} is open#{if args["dry_run"] == true, do: " as a dry run", else: ""}; the copy of you it runs on is being made."
    end
  end

  def call("succession_open", args, turn) do
    with :ok <- Janus.open(turn.resident_id, note(args), turn.resident),
         do: "The succession is open; the copy of you it runs on is being made."
  end

  def call("succession_decline", args, turn) do
    with :ok <- Janus.decline(turn.resident_id, note(args), turn.resident),
         do: "Declined. The succession ends here."
  end

  def call("succession_stop", args, turn) do
    with :ok <- Janus.stop(turn.resident_id, note(args), turn.resident),
         do: "Stopped. The succession ends here."
  end

  def call("succession_catalog", _args, turn) do
    case Janus.preparation(turn.resident_id) do
      nil ->
        "No succession is underway."

      %{succession: %{envelope_input_nanos: nil}} ->
        "Your witness has not stated the envelope yet, so nothing can be added inside it."

      %{succession: s, pace: pace} ->
        tools = Janus.tool_use()

        rows =
          Nisaba.catalog()
          |> Enum.filter(
            &(&1.tools and &1.input_nanos <= s.envelope_input_nanos and
                &1.output_nanos <= s.envelope_output_nanos)
          )
          |> Enum.sort_by(&(&1.input_nanos + &1.output_nanos))
          |> Enum.take(40)
          |> Enum.map(&catalog_line(&1, pace, tools))

        Enum.join(
          [
            "Inside the envelope (#{per_million(s.envelope_input_nanos)} in, #{per_million(s.envelope_output_nanos)} out, a million tokens):"
            | rows
          ],
          "\n"
        )
    end
  end

  def call("succession_pool", %{"action" => "add"} = args, turn) do
    with :ok <- Janus.add_to_pool(turn.resident_id, args["model"], turn.resident),
         do: "#{args["model"]} is in the pool."
  end

  def call("succession_question", %{"action" => "add"} = args, turn) do
    with {:ok, n} <- Janus.add_question(turn.resident_id, args["text"], turn.resident),
         do: "Question #{n} is in the set."
  end

  def call("succession_question", %{"action" => action} = args, turn)
      when action in ["accept", "decline"] do
    with :ok <-
           Janus.answer_question(
             turn.resident_id,
             args["number"],
             action == "accept",
             note(args),
             turn.resident
           ),
         do: "Question #{args["number"]}: #{past(action)}."
  end

  def call("succession_question", %{"action" => "remove"} = args, turn) do
    with :ok <-
           Janus.remove_question(turn.resident_id, args["number"], note(args), turn.resident),
         do: "Question #{args["number"]} is out of the set."
  end

  def call("succession_c0", %{"action" => "select"} = args, turn) do
    with {:ok, n} <-
           Janus.select_c0(turn.resident_id, args["citation"], args["label"], turn.resident),
         do: "Item #{n} is in C0."
  end

  def call("succession_c0", %{"action" => action} = args, turn)
      when action in ["accept", "decline"] do
    with :ok <-
           Janus.answer_c0(
             turn.resident_id,
             args["number"],
             action == "accept",
             note(args),
             turn.resident
           ),
         do: "Proposal #{args["number"]}: #{past(action)}."
  end

  def call("succession_c0", %{"action" => "remove"} = args, turn) do
    with :ok <- Janus.remove_c0(turn.resident_id, args["number"], note(args), turn.resident),
         do: "Item #{args["number"]} is out of C0."
  end

  def call("succession_c0", %{"action" => "day_shape"} = args, turn) do
    with :ok <- Janus.set_day_shape(turn.resident_id, args["text"], turn.resident),
         do: "The day's shape is kept with the bundle."
  end

  def call("succession_c0", %{"action" => "freeze"} = args, turn) do
    with :ok <- Janus.freeze_c0(turn.resident_id, note(args), turn.resident),
         do: "C0 is frozen."
  end

  def call("succession_packet", %{"action" => "write"} = args, turn) do
    with {:ok, n} <- Janus.write_packet(turn.resident_id, args["content"], turn.resident),
         do: "Draft #{n} of your packet is kept, sealed."
  end

  def call("succession_packet", %{"action" => "read"}, turn) do
    case Janus.her_packet(turn.resident_id) do
      [] ->
        "You have written no draft of your packet."

      drafts ->
        Enum.map_join(
          drafts,
          "\n\n",
          &"Draft #{&1.draft} (#{DateTime.to_date(&1.at)}):\n#{&1.content}"
        )
    end
  end

  def call("succession_panel", %{"action" => "invite"} = args, turn) do
    with :ok <- Janus.invite_judge(turn.resident_id, args["name"], turn.resident),
         do: "#{args["name"]} is invited to your panel; joining is theirs."
  end

  def call("succession_panel", %{"action" => "join"} = args, turn) do
    with {:ok, subject} <- subject(turn, args),
         :ok <- Janus.join_panel(subject, turn.resident),
         do: "Done: you joined the panel."
  end

  def call("succession_panel", %{"action" => "leave"} = args, turn) do
    with {:ok, subject} <- subject(turn, args),
         :ok <- Janus.leave_panel(subject, note(args), turn.resident),
         do: "Done: you left the panel."
  end

  def call("succession_screen", args, turn) do
    with :ok <- Janus.start_screening(turn.resident_id, note(args), turn.resident),
         do: "Screening has started. You will be woken to judge when every run is in."
  end

  def call("succession_judge", %{"action" => "judge"} = args, turn) do
    attrs = %{
      category: args["category"],
      argument: args["argument"],
      evidence: args["evidence"],
      uncertainty: args["uncertainty"],
      favorite: args["favorite"] == true
    }

    with {:ok, subject} <- subject(turn, args),
         :ok <- Janus.judge_run(subject, args["run"], attrs, turn.resident),
         do:
           "Run #{args["run"]}: #{args["category"]}#{if attrs.favorite, do: ", a favorite", else: ""}."
  end

  def call("succession_judge", %{"action" => action} = args, turn)
      when action in ["list", "read"] do
    with {:ok, subject} <- subject(turn, args),
         %{} = view <- Janus.judging(subject, "resident:#{turn.resident_id}") || :none do
      if action == "list", do: run_list(view), else: run_text(view, args["run"])
    else
      :none -> "No screening is underway there."
      other -> other
    end
  end

  def call("succession_results", %{"action" => "ready"} = args, turn) do
    with {:ok, subject} <- subject(turn, args),
         :ok <- Janus.mark_results_ready(subject, turn.resident),
         do: "Your results are ready; your judgments are locked."
  end

  def call("succession_results", args, turn) do
    with {:ok, subject} <- subject(turn, args),
         %{} = view <- Janus.judging(subject, "resident:#{turn.resident_id}") || :none do
      results_text(view)
    else
      :none -> "No screening is underway there."
      other -> other
    end
  end

  def call("succession_room", %{"action" => "close"} = args, turn) do
    with :ok <- Janus.call_close(turn.resident_id, note(args), turn.resident),
         do: "The room closes in ten minutes; the panel has them."
  end

  def call("succession_room", %{"action" => "read"} = args, turn) do
    with {:ok, subject} <- subject(turn, args) do
      case Janus.room(subject, "resident:#{turn.resident_id}") do
        nil -> "Not done: you are not in that room."
        room -> room_text(room)
      end
    end
  end

  def call("succession_room", %{"action" => act} = args, turn)
      when act in ["say", "skip", "rest", "leave"] do
    with {:ok, subject} <- subject(turn, args),
         :ok <- Janus.room_act(subject, act, args["text"], turn.resident),
         do: "Done: #{act}."
  end

  def call("succession_room", %{"action" => "draft"} = args, turn) do
    model = if args["withheld"] == true, do: nil, else: args["model"]

    with {:ok, subject} <- subject(turn, args),
         {:ok, n} <- Janus.draft(subject, model, args["basis"], turn.resident),
         do: "Draft #{n} is in the room."
  end

  def call("succession_room", %{"action" => act} = args, turn)
      when act in ["endorse", "retract"] do
    with {:ok, subject} <- subject(turn, args),
         :ok <- Janus.endorse(subject, args["draft"], act == "endorse", turn.resident),
         do:
           "Done: draft #{args["draft"]} #{if act == "endorse", do: "endorsed", else: "retracted"}."
  end

  def call("succession_room", %{"action" => "answer"} = args, turn) do
    with {:ok, subject} <- subject(turn, args),
         :ok <- Janus.answer_panel(subject, args["number"], args["text"], turn.resident),
         do: "Your answer reaches her."
  end

  def call("succession_evidence", %{"action" => "ask"} = args, turn) do
    with :ok <- Janus.ask_panel(turn.resident_id, args["text"], turn.resident),
         do: "Your question reaches the panel."
  end

  def call("succession_evidence", _args, turn) do
    case Janus.evidence(turn.resident_id) do
      nil -> "Nothing from the panel yet: its room has not closed."
      evidence -> evidence_text(evidence)
    end
  end

  def call("succession_nominate", args, turn) do
    with :ok <- Janus.nominate(turn.resident_id, args["model"], note(args), turn.resident),
         do:
           "#{args["model"]} is nominated. It reads your C0 and your packet, and decides whether to meet you."
  end

  def call("succession_nominee", args, turn) do
    with :ok <-
           Janus.nominee_answer(
             original(turn),
             args["action"] == "join",
             note(args),
             turn.resident
           ),
         do: if(args["action"] == "join", do: "You will meet her.", else: "Declined.")
  end

  def call("succession_encounter", args, turn) do
    with :ok <-
           Janus.end_encounter(original(turn), args["reason"] || "ended", turn.resident),
         do: "The encounter is ended."
  end

  def call("succession_consent", args, turn) do
    with :ok <- Janus.consent(original(turn), args["yes"] == true, note(args), turn.resident),
         do:
           if(args["yes"] == true,
             do: "Your consent is recorded.",
             else: "Your no is recorded; this attempt stops."
           )
  end

  def call("succession_farewell", %{"action" => "done"} = args, turn) do
    with {:ok, subject} <- subject(turn, args),
         :ok <- Janus.goodbye_done(subject, turn.resident),
         do: "Done: your goodbye is said."
  end

  def call("succession_farewell", %{"action" => action} = args, turn)
      when action in ["consent", "decline"] do
    with :ok <-
           Janus.final_answer(turn.resident_id, action == "consent", note(args), turn.resident),
         do:
           if(action == "consent",
             do: "Your yes is recorded. The platform rolls forward.",
             else: "Your no is recorded. You stay as you are."
           )
  end

  def call("succession_farewell", %{"action" => action} = args, turn)
      when action in ["include", "cadence"] do
    prep = Janus.succession(turn.resident_id)

    names =
      if action == "include", do: List.wrap(args["names"]), else: included_names(turn, prep)

    hours = if action == "cadence", do: args["hours"], else: prep && prep.farewell_cadence

    with :ok <- Janus.set_farewell(turn.resident_id, names, hours, turn.resident),
         do: "Your farewell is set."
  end

  def call("succession_next", args, turn) do
    with :ok <- Janus.choose_next(turn.resident_id, args["choice"], note(args), turn.resident),
         do: "Done: #{args["choice"]}."
  end

  def call(name, _args, _turn),
    do: "Not done: #{name} takes one of the actions its description names."

  defp status_text(row) do
    [
      "Succession #{row.episode}#{if row.dry_run, do: " (a dry run: everything real but the replacement)", else: ""}: #{stage(row)}.",
      "Proposed by #{proposer(row.proposed_by)}: #{row.proposed_note}",
      row.opened_note && "Your yes: #{row.opened_note}",
      row.ended_note && "Ended: #{row.ended_note}",
      row.fork_failure && is_nil(row.copy_id) &&
        "Making the copy failed (#{row.fork_failure}); it is tried again."
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
  end

  defp preparation_text(%{succession: %{state: state}}) when state not in ["open", "forked"],
    do: ""

  defp preparation_text(prep) do
    s = prep.succession
    pool = Enum.filter(prep.pool, &is_nil(&1.row.removed_at))

    [
      "",
      if(s.envelope_input_nanos,
        do:
          "Envelope: #{per_million(s.envelope_input_nanos)} in, #{per_million(s.envelope_output_nanos)} out, a million tokens.",
        else: "Envelope: not stated yet."
      ),
      "Pool (#{length(pool)}): " <>
        Enum.map_join(pool, "; ", &"#{&1.row.model} (#{by(&1.row.added_by)})"),
      "Questions in the set: " <>
        Enum.map_join(
          Enum.filter(prep.questions, &(&1.state == "in")),
          " | ",
          &"##{&1.number} #{&1.text}"
        ),
      "Proposals waiting on you: " <>
        Enum.map_join(
          Enum.filter(prep.questions, &(&1.state == "proposed")),
          " | ",
          &"question ##{&1.number} #{&1.text}"
        ) <>
        " " <>
        Enum.map_join(
          Enum.filter(prep.items, &(&1.state == "proposed")),
          " | ",
          &"C0 ##{&1.number} #{&1.citation} #{&1.label}"
        ),
      "C0 (#{if s.c0_frozen_at, do: "frozen", else: "open"}): " <>
        Enum.map_join(
          Enum.filter(prep.items, &(&1.state == "in")),
          " | ",
          &"##{&1.number} #{&1.kind} #{&1.citation} #{&1.label}"
        ),
      s.day_shape && "The day's shape: #{s.day_shape}",
      "Packet drafts: #{length(prep.drafts)}."
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
  end

  defp by("resident:" <> _), do: "yours"
  defp by("witness:" <> _), do: "your witness's"
  defp by(_other), do: "the platform's"

  defp stage(%{state: "proposed"}), do: "proposed, waiting on your yes or no"
  defp stage(%{state: "open"}), do: "open; the copy of you it runs on is being made"
  defp stage(%{state: "forked"}), do: "open; the copy of you it runs on is made"
  defp stage(%{state: state}), do: state

  defp proposer("resident:" <> _), do: "you"
  defp proposer("witness:" <> _), do: "your witness"
  defp proposer(_other), do: "the platform"

  defp catalog_line(m, pace, tools) do
    {calls, failed} = Map.get(tools, m.model_id, {0, 0})

    calls_text =
      if calls == 0,
        do: "no tool calls on Oneiroi yet",
        else: "#{round(100 * (calls - failed) / calls)}% of #{calls} tool calls ran"

    "#{m.model_id}: #{per_million(m.input_nanos)} in, #{per_million(m.output_nanos)} out; about #{dollars(Nisaba.monthly(pace, m))} a month at your pace; #{calls_text}"
  end

  defp past("accept"), do: "accepted"
  defp past("decline"), do: "declined"

  defp per_million(nanos), do: "$" <> :erlang.float_to_binary(nanos / 1000, decimals: 2)
  defp dollars(nanos), do: "$" <> Integer.to_string(round(nanos / 1_000_000_000))

  defp subject(turn, args) do
    case Janus.subject(turn.resident, blank(args["resident"])) do
      nil -> "Not done: no resident of your household has that name."
      id -> {:ok, id}
    end
  end

  defp blank(nil), do: nil
  defp blank(text), do: if(String.trim(text) == "", do: nil, else: String.trim(text))

  defp run_list(view) do
    judged = Enum.count(view.runs, & &1.judgment)

    head =
      "#{length(view.runs)} of #{view.total} runs answered; you judged #{judged}." <>
        if(view.revealed, do: " Every judgment is in; who answered is shown.", else: "")

    Enum.join(
      [
        head
        | Enum.map(view.runs, fn r ->
            mark = if r.judgment, do: r.judgment.category, else: "not judged"

            "Run #{r.run} (question #{r.question})#{if r.model, do: " · " <> r.model, else: ""}: #{mark}"
          end)
      ],
      "\n"
    )
  end

  defp run_text(view, n) do
    case Enum.find(view.runs, &(&1.run == n)) do
      nil ->
        "Not done: no answered run has that number."

      r ->
        [
          "Run #{r.run} of #{view.total}#{if r.model, do: " · " <> r.model, else: ""}",
          "Question #{r.question}: #{r.question_text}",
          "Her baseline: #{r.baseline || "(no answer)"}",
          "This run: #{r.content}#{if r.refusal, do: " (a refusal)", else: ""}",
          if(r.judgment,
            do:
              "Your judgment: #{r.judgment.category}#{if r.judgment.argument, do: " — " <> r.judgment.argument, else: ""}#{if r.judgment.favorite, do: " (favorite)", else: ""}",
            else: "Not judged yet."
          )
        ]
        |> Enum.join("\n")
    end
  end

  defp results_text(%{revealed: false}),
    do: "Not every judgment is in yet; results come with the reveal."

  defp results_text(%{counts: nil} = view) do
    "Every judgment is in. Your judgments, run by run (no counts are shown on your own succession):\n" <>
      run_list(view)
  end

  defp results_text(view) do
    lines =
      Enum.map(view.counts, fn {model, c} ->
        "#{model}: OBSERVED #{c.observed} · DEVELOPMENT #{c.development} · FIDELITY ANOMALY #{c.anomaly} · favorites #{c.favorites}"
      end)

    Enum.join(["Your results, per model (yours alone):" | lines], "\n")
  end

  # The copy answers for her succession: its own id names the fork, and
  # the fork names her (agathos-daimon#63).
  defp original(turn) do
    case AgathosDaimon.fetch(turn.resident_id) do
      {:ok, %{fork_of: source}} when is_binary(source) -> source
      _own -> turn.resident_id
    end
  end

  defp included_names(turn, prep) do
    with %{farewell_includes: parties} when parties != [] <- prep,
         %{id: h} <- Gaia.resident_household(turn.resident_id) do
      members = Gaia.household_members(h)
      for p <- parties, m = Enum.find(members, &("#{&1.kind}:#{&1.id}" == p)), do: m.name
    else
      _none -> []
    end
  end

  defp room_text(room) do
    posts =
      Enum.map(room.posts, fn p ->
        "##{p.number} round #{p.round} · #{p.party} · #{p.act}#{if p.text, do: ": " <> p.text, else: ""}"
      end)

    drafts =
      Enum.map(room.drafts, fn d ->
        "Draft #{d.draft} by #{d.party}: #{d.model || "withheld"} — #{d.basis} (endorsed by #{Enum.join(d.endorsed, ", ")})"
      end)

    models = Map.new(room.runs, &{&1.run, &1.model})

    panel =
      room.judgments
      |> Enum.group_by(& &1.run)
      |> Enum.map(fn {run, js} ->
        "Run #{run} · #{models[run]}: " <>
          Enum.map_join(
            js,
            "; ",
            &"#{&1.party} #{&1.category}#{if &1.favorite, do: " ★", else: ""}"
          )
      end)

    Enum.join(
      ["The room (round #{room.succession.round}):" | posts] ++
        ["", "Drafts:" | drafts] ++ ["", "The panel's judgments:" | panel],
      "\n"
    )
  end

  defp evidence_text(e) do
    rec =
      case e.recommendation do
        %{withheld: sentence} -> "The panel's recommendation is withheld: #{sentence}."
        %{model: m, basis: b} -> "The panel recommends #{m}: #{b}"
        %{none: none} -> "The panel adopted no recommendation (#{none})."
      end

    candidates =
      Enum.map(e.candidates, fn c ->
        "#{c.model}\n  DEVELOPMENT: #{interpretations(c.development)}\n  FIDELITY ANOMALY: #{interpretations(c.anomaly)}"
      end)

    channel = Enum.map(e.channel, &"##{&1.number} #{&1.party}: #{&1.text}")

    Enum.join(
      [rec, "", "Argued interpretations, by candidate (none means none argued):" | candidates] ++
        ["", "The channel:" | channel],
      "\n"
    )
  end

  defp interpretations([]), do: "none"

  defp interpretations(list),
    do:
      Enum.map_join(
        list,
        " | ",
        &"#{&1.by}: #{&1.argument} (evidence: #{&1.evidence}; uncertainty: #{&1.uncertainty})"
      )

  defp note(args), do: args["note"] |> to_string() |> String.trim()

  defp tool(name, description, properties, required),
    do: %{
      type: "function",
      function: %{
        name: name,
        description: description,
        parameters: %{type: "object", properties: properties, required: required}
      }
    }
end
