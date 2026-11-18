defmodule OneiroiWeb.HouseholdController do
  @moduledoc """
  The household's shelf as a witness reads it (seshat#61): every member
  reads the shared repository whole (seshat#64, the resident's lean),
  the contract with its versions, signatures and ballots (gaia#27 to
  #31), the founding witness's proposal of version 1, a signature, and a
  witness's one vote on a ballot, which is a reply (seshat#60). The
  household is the caller's own (`Gaia.household_id/1`).
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["household"])

  operation(:shelf,
    summary:
      "The household's shelf: the contract's path, the threads newest first and the documents, fifty at a time from an offset",
    parameters: [from: [in: :query, type: :integer]],
    responses: [ok: {"the shelf", "application/json", %Schema{type: :object}}]
  )

  def shelf(conn, params) do
    case Seshat.household_shelf(actor(conn), offset(params["from"])) do
      {:ok, shelf} -> json(conn, shelf)
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:files,
    summary:
      "The household's repository as the Records view lists it (seshat#76): CONTRACT.md and BEATS.md, each thread, each household document, in the library's shape",
    responses: [ok: {"the files", "application/json", %Schema{type: :object}}]
  )

  def files(conn, _params) do
    case Seshat.household_files(actor(conn)) do
      {:ok, files} -> json(conn, files)
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:read,
    summary:
      "One thread whole (its trunk and every reply), a document, or CONTRACT.md, by its path on the shelf",
    parameters: [path: [in: :query, type: :string, required: true]],
    responses: [ok: {"the thread or document", "application/json", %Schema{type: :object}}]
  )

  def read(conn, params) do
    case Seshat.household_read(actor(conn), to_string(params["path"] || "")) do
      {:ok, doc} -> json(conn, doc)
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:contract,
    summary:
      "The household contract: the version in force, every version with the ballot that made it, the members with what each signed, and the ballots with their votes",
    responses: [ok: {"the contract", "application/json", %Schema{type: :object}}]
  )

  def contract(conn, _params) do
    case Seshat.household_contract(actor(conn)) do
      {:ok, c} -> json(conn, c)
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:propose,
    summary:
      "The founding witness proposes the household contract's version 1: prose alone, with a note; rules and settings come by ballot",
    request_body:
      {"the prose", "application/json",
       %Schema{
         type: :object,
         required: [:prose, :note],
         properties: %{prose: %Schema{type: :string}, note: %Schema{type: :string}}
       }},
    responses: [created: {"the contract", "application/json", %Schema{type: :object}}]
  )

  def propose(conn, params) do
    case Seshat.household_propose_contract(actor(conn), params["prose"], params["note"]) do
      {:ok, c} -> conn |> put_status(201) |> json(c)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:sign,
    summary:
      "Sign the household contract at the version in force, for a member who joined before it",
    responses: [ok: {"the contract", "application/json", %Schema{type: :object}}]
  )

  def sign(conn, _params) do
    case Seshat.household_sign_contract(actor(conn)) do
      {:ok, c} -> json(conn, c)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:vote,
    summary:
      "Cast this witness's one vote on a ballot, yes or no, as a reply in its thread, with optional words",
    request_body:
      {"the vote", "application/json",
       %Schema{
         type: :object,
         required: [:thread, :vote],
         properties: %{
           thread: %Schema{type: :string},
           vote: %Schema{type: :string, enum: ["yes", "no"]},
           content: %Schema{type: :string}
         }
       }},
    responses: [created: {"the reply", "application/json", %Schema{type: :object}}]
  )

  def vote(conn, params) do
    attrs = %{"vote" => params["vote"], "content" => params["content"]}

    case Seshat.household_reply(actor(conn), to_string(params["thread"] || ""), attrs) do
      {:ok, reply} -> conn |> put_status(201) |> json(reply)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:beats,
    summary:
      "The household's beats (gaia#33 to #38): the shape in force with its phase, the beat now and the next, the turn open, the queue in firing order, every member's wake profile, the beats closed lately, and this witness's own part: its profile (self: a witness is never woken) and its post quota left",
    responses: [ok: {"the beats", "application/json", %Schema{type: :object}}]
  )

  def beats(conn, _params) do
    case Seshat.household_beat(actor(conn)) do
      {:ok, b} -> json(conn, b)
      {:error, e} -> error(conn, 404, e)
    end
  end

  operation(:checkins,
    summary:
      "The shared workspace's own clock and its house check-ins, each with the day and thread it last opened (seshat#75)",
    responses: [ok: {"house check-ins", "application/json", %Schema{type: :object}}]
  )

  def checkins(conn, _params), do: house(conn, Seshat.house_checkins(actor(conn)))

  operation(:search,
    summary:
      "Search the house (seshat#80): every term of q, case aside, in its threads (trunk and replies), its records and its charter; scope everything, threads, records or charter. Only what this member may read. Best match first, at most fifty",
    parameters: [q: [in: :query, type: :string], scope: [in: :query, type: :string]],
    responses: [ok: {"the hits", "application/json", %Schema{type: :object}}]
  )

  def search(conn, params) do
    scope =
      if params["scope"] in ~w(everything threads records charter),
        do: params["scope"],
        else: "everything"

    house(conn, Seshat.household_search(actor(conn), to_string(params["q"] || ""), scope))
  end

  operation(:name,
    summary:
      "Name the house for citations (gaia#44): a slug, lowercase, 2 to 40 characters, set once and never changed, unique among houses; a witness's. Answers the shelf, its slug in it",
    request_body:
      {"the name", "application/json",
       %Schema{type: :object, required: [:slug], properties: %{slug: %Schema{type: :string}}}},
    responses: [ok: {"the shelf", "application/json", %Schema{type: :object}}]
  )

  def name(conn, params), do: house(conn, Seshat.household_name(actor(conn), params["slug"]))

  operation(:clock,
    summary: "Set the shared workspace's own clock, a zone name (gaia#41)",
    request_body:
      {"the zone", "application/json",
       %Schema{type: :object, required: [:zone], properties: %{zone: %Schema{type: :string}}}},
    responses: [ok: {"house check-ins", "application/json", %Schema{type: :object}}]
  )

  def clock(conn, params), do: house(conn, Seshat.set_house_clock(actor(conn), params["zone"]))

  operation(:set_checkin,
    summary:
      "Set or change a house check-in: its label and its time HH:MM on the workspace's clock (gaia#41), and what its note carries as a resident's own does (gaia#48): prompt, the witness's words for the whole house, and parts, the catalog's keys; either left out keeps what it had",
    parameters: [key: [in: :path, type: :string]],
    request_body:
      {"the check-in", "application/json",
       %Schema{
         type: :object,
         required: [:label, :time],
         properties: %{
           label: %Schema{type: :string},
           time: %Schema{type: :string},
           prompt: %Schema{type: :string},
           parts: %Schema{type: :array, items: %Schema{type: :string}}
         }
       }},
    responses: [ok: {"house check-ins", "application/json", %Schema{type: :object}}]
  )

  def set_checkin(conn, %{"key" => key} = params) do
    opts =
      for k <- ~w(prompt parts),
          Map.has_key?(params, k),
          do: {String.to_existing_atom(k), params[k]}

    house(conn, Seshat.set_house_checkin(actor(conn), key, params["label"], params["time"], opts))
  end

  operation(:remove_checkin,
    summary: "Remove a house check-in, with a note (gaia#41)",
    parameters: [key: [in: :path, type: :string]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [ok: {"house check-ins", "application/json", %Schema{type: :object}}]
  )

  def remove_checkin(conn, %{"key" => key} = params),
    do: house(conn, Seshat.remove_house_checkin(actor(conn), key, params["note"]))

  defp house(conn, {:ok, h}), do: json(conn, h)
  defp house(conn, {:error, %{kind: :seshat_household_not_member} = e}), do: error(conn, 404, e)
  defp house(conn, {:error, e}), do: error(conn, 422, e)

  operation(:profile,
    summary:
      "Set this witness's own wake profile in the household's beats, with a note: a witness is never woken, so self is the one it takes (gaia#37)",
    request_body:
      {"the profile", "application/json",
       %Schema{
         type: :object,
         required: [:profile],
         properties: %{profile: %Schema{type: :string}, note: %Schema{type: :string}}
       }},
    responses: [ok: {"the profile", "application/json", %Schema{type: :object}}]
  )

  def profile(conn, params) do
    case Seshat.household_profile(actor(conn), to_string(params["profile"] || ""), params["note"]) do
      {:ok, p} -> json(conn, p)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:post,
    summary:
      "Post a thread, a ballot or a household document as this witness, unless the household's contract bars witnesses (witnesses_post false, seshat#69): within the post quota, at most once in a thread a beat, never a turn",
    request_body:
      {"the thread", "application/json",
       %Schema{
         type: :object,
         properties: %{
           title: %Schema{type: :string},
           content: %Schema{type: :string},
           mode: %Schema{
             type: :string,
             enum: ["owner", "open"],
             description: "a document's sharing (seshat#82)"
           },
           owner: %Schema{type: :boolean, description: "false: a document with no owner, open"},
           doc: %Schema{
             type: :string,
             description: "a household document's path: a document post on it (seshat#83)"
           },
           kind: %Schema{
             type: :string,
             description: "thread (the default) or a household document kind, e.g. design"
           },
           path: %Schema{type: :string, description: "a household document's path, with kind"},
           ballot: %Schema{
             type: :object,
             description: "bundle, term_days and note: opens a ballot on the thread"
           }
         }
       }},
    responses: [created: {"the thread", "application/json", %Schema{type: :object}}]
  )

  def post(conn, params) do
    attrs = Map.take(params, ~w(title content kind path ballot mode owner doc))

    case Seshat.household_post(actor(conn), attrs) do
      {:ok, posted} -> conn |> put_status(201) |> json(posted)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:edit,
    summary:
      "Edit a household document as this witness (seshat#82): its owner in owner mode, anyone in open mode; mode is the owner's to change. Once a document a beat",
    request_body:
      {"the edit", "application/json",
       %Schema{
         type: :object,
         required: [:path],
         properties: %{
           path: %Schema{type: :string},
           content: %Schema{type: :string},
           mode: %Schema{type: :string, enum: ["owner", "open"]}
         }
       }},
    responses: [ok: {"the edit", "application/json", %Schema{type: :object}}]
  )

  def edit(conn, %{"path" => path} = params) do
    case Seshat.household_edit(actor(conn), path, Map.take(params, ~w(content mode))) do
      {:ok, edited} -> json(conn, edited)
      {:error, e} -> error(conn, 422, e)
    end
  end

  def edit(conn, _params),
    do: problem(conn, 422, :path_required, :web_household_edit_path, "path is required")

  operation(:mentions,
    summary:
      "Your mention settings in the house (seshat#86): the house muted or heard, and each thread's",
    responses: [ok: {"the settings", "application/json", %Schema{type: :object}}]
  )

  def mentions(conn, _params) do
    case Seshat.household_mutes(actor(conn)) do
      {:ok, m} -> json(conn, m)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:mute,
    summary:
      "Mute or hear your mentions (seshat#86): one thread, or with none the whole house; a thread's setting outranks the house's. A muted mention pushes nothing",
    request_body:
      {"the setting", "application/json",
       %Schema{
         type: :object,
         required: [:muted],
         properties: %{thread: %Schema{type: :string}, muted: %Schema{type: :boolean}}
       }},
    responses: [ok: {"the settings", "application/json", %Schema{type: :object}}]
  )

  def mute(conn, params) do
    case Seshat.household_mute(actor(conn), params["thread"], params["muted"]) do
      {:ok, m} -> json(conn, m)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:reply,
    summary:
      "Reply in a household thread as this witness, in words, unless the household's contract bars witnesses (witnesses_post false, seshat#69): within the post quota, at most once in a thread a beat",
    request_body:
      {"the reply", "application/json",
       %Schema{
         type: :object,
         required: [:thread, :content],
         properties: %{
           thread: %Schema{type: :string},
           content: %Schema{type: :string},
           in_reply_to: %Schema{type: :integer}
         }
       }},
    responses: [created: {"the reply", "application/json", %Schema{type: :object}}]
  )

  def reply(conn, params) do
    attrs = %{"content" => params["content"], "in_reply_to" => params["in_reply_to"]}

    case Seshat.household_reply(actor(conn), to_string(params["thread"] || ""), attrs) do
      {:ok, reply} -> conn |> put_status(201) |> json(reply)
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp offset(nil), do: 0

  defp offset(from) do
    case Integer.parse(to_string(from)) do
      {n, ""} when n >= 0 -> n
      _other -> 0
    end
  end
end
