defmodule Oneiroi.Seshat.Library do
  @moduledoc """
  The library aggregate on `library-<resident_id>` (spec §6.5). Pure: it
  holds the registered documents by path with their kind, last hash and
  published URL, and the discussions opened. A write whose hash is the
  current one is no event; an adoption of a registered path is no event;
  only a kind with a status is published; a keepsake, once registered,
  is never written again (seshat#29).
  """

  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Kinds

  # `oracles`: number => :open | :answered | :failed (seshat#34).
  defstruct [
    :id,
    documents: %{},
    discussions: MapSet.new(),
    oracles: %{},
    researches: %{},
    # External sources (seshat#46): number => %{key, state}; keys => number.
    externals: %{},
    external_keys: %{},
    digests: %{}
  ]

  @url ~r/\Ahttps?:\/\/[^\s]+\z/

  def execute(%__MODULE__{documents: documents}, %Commands.WriteDocument{} = c) do
    case Map.get(documents, c.path) do
      %{hash: hash} when hash == c.hash ->
        []

      # A tombstone holds its path for the citations that point at it
      # (seshat#45): nothing is written over it.
      %{kind: "tombstone"} ->
        {:error, Error.new(:seshat_not_movable, :seshat_write_document_tombstone, path: c.path)}

      # A keepsake is written once (seshat#29): a registered keepsake is
      # never written again (#44), save a goals ledger registered as one
      # before the ledger was a kind (#43), written as what it is now.
      %{kind: "keepsake"} when c.kind != "goals" ->
        {:error,
         Error.new(:seshat_keepsake_kept, :seshat_write_document_keepsake_kept, path: c.path)}

      _new_or_changed ->
        %Events.DocumentWritten{
          actor: c.actor,
          at: c.at,
          id: c.id,
          path: c.path,
          kind: c.kind,
          hash: c.hash,
          bytes: c.bytes,
          note: c.note
        }
    end
  end

  # Seshat #39: a registered document to a path nothing holds, its bytes
  # as registered. Into a keepsake is deciding it one (#31); a keepsake
  # moved is still never edited, so the move carries the same hash.
  def execute(%__MODULE__{documents: documents}, %Commands.MoveDocument{} = c) do
    case {Map.get(documents, c.from), Map.has_key?(documents, c.to)} do
      {nil, _taken} ->
        {:error, Error.new(:seshat_no_such_document, :seshat_move_document_absent, path: c.from)}

      {_doc, true} ->
        {:error, Error.new(:seshat_move_target_taken, :seshat_move_document_taken, path: c.to)}

      {%{hash: hash}, false} when hash != c.hash ->
        {:error,
         Error.new(:seshat_not_movable, :seshat_move_document_changed,
           path: c.from,
           reason: "the file is not what was registered; write it first"
         )}

      {_doc, false} ->
        %Events.DocumentMoved{
          actor: c.actor,
          at: c.at,
          id: c.id,
          from: c.from,
          to: c.to,
          from_kind: c.from_kind,
          to_kind: c.to_kind,
          hash: c.hash
        }
    end
  end

  def execute(%__MODULE__{documents: documents}, %Commands.RemoveDocument{} = c) do
    cond do
      not Map.has_key?(documents, c.path) ->
        {:error,
         Error.new(:seshat_no_such_document, :seshat_remove_document_absent, path: c.path)}

      # A system kind's rule; a kind of hers (seshat#51) was checked
      # against her registry by the service before it got here.
      match?(%{}, Kinds.kind_of(c.path)) and not Kinds.removable?(Kinds.kind_of(c.path)) ->
        {:error, Error.new(:seshat_not_removable, :seshat_remove_document_kind, path: c.path)}

      true ->
        %Events.DocumentRemoved{actor: c.actor, at: c.at, id: c.id, path: c.path, kind: c.kind}
    end
  end

  def execute(%__MODULE__{documents: documents}, %Commands.AdoptDocument{} = c) do
    if Map.has_key?(documents, c.path),
      do: [],
      else: %Events.DocumentAdopted{
        actor: c.actor,
        at: c.at,
        id: c.id,
        path: c.path,
        kind: c.kind,
        hash: c.hash,
        bytes: c.bytes,
        provenance: c.provenance
      }
  end

  def execute(%__MODULE__{documents: documents}, %Commands.PublishPiece{} = c) do
    case Map.get(documents, c.path) do
      nil ->
        {:error,
         Error.new(:seshat_no_such_document, :seshat_publish_piece_no_such_document, path: c.path)}

      %{kind: kind} = doc ->
        cond do
          not has_status?(kind) ->
            {:error,
             Error.new(:seshat_not_publishable, :seshat_publish_piece_not_publishable,
               path: c.path
             )}

          not (is_binary(c.url) and Regex.match?(@url, c.url)) ->
            {:error, Error.new(:seshat_url_invalid, :seshat_publish_piece_url_invalid)}

          doc.url == c.url ->
            []

          true ->
            %Events.PiecePublished{actor: c.actor, at: c.at, id: c.id, path: c.path, url: c.url}
        end
    end
  end

  # An archive (seshat#45): a registered document, not a tombstone
  # already, to a path under archive/ nothing holds.
  def execute(%__MODULE__{documents: documents}, %Commands.ArchiveDocument{} = c) do
    cond do
      not Map.has_key?(documents, c.path) ->
        {:error, Error.new(:seshat_no_such_document, :seshat_archive_absent, path: c.path)}

      match?(%{kind: kind} when kind in ["tombstone", "archive"], documents[c.path]) ->
        {:error, Error.new(:seshat_not_movable, :seshat_archive_already, path: c.path)}

      Map.has_key?(documents, c.to) ->
        {:error, Error.new(:seshat_move_target_taken, :seshat_archive_target_taken, path: c.to)}

      not (is_binary(c.why) and String.trim(c.why) != "") ->
        {:error, Error.new(:seshat_archive_invalid, :seshat_archive_why_missing)}

      true ->
        %Events.DocumentArchived{
          actor: c.actor,
          at: c.at,
          id: c.id,
          path: c.path,
          to: c.to,
          why: String.trim(c.why),
          archived_hash: c.archived_hash,
          archived_bytes: c.archived_bytes,
          tombstone_hash: c.tombstone_hash,
          tombstone_bytes: c.tombstone_bytes
        }
    end
  end

  # A keepsake by registration (seshat#44): a root file, registered,
  # becomes one, and from then is never written again; either party may
  # register one, and registering one already is nothing.
  def execute(%__MODULE__{documents: documents}, %Commands.RegisterKeepsake{} = c) do
    case Map.get(documents, c.path) do
      %{kind: "keepsake"} ->
        []

      %{kind: "root"} ->
        %Events.KeepsakeRegistered{actor: c.actor, at: c.at, id: c.id, path: c.path}

      nil ->
        {:error,
         Error.new(:seshat_no_such_document, :seshat_register_keepsake_absent, path: c.path)}

      _other ->
        {:error,
         Error.new(:seshat_not_a_keepsake, :seshat_register_keepsake_not_root, path: c.path)}
    end
  end

  # Why a keepsake mattered is the resident's to say (seshat#32), of a
  # registered keepsake, in a line of up to 1,000 characters; the same
  # words again are no event.
  def execute(%__MODULE__{documents: documents}, %Commands.NoteKeepsake{} = c) do
    cond do
      c.actor.kind != :resident ->
        {:error, Error.new(:seshat_not_the_resident, :seshat_note_keepsake_resident_only)}

      not match?(%{kind: "keepsake"}, Map.get(documents, c.path)) ->
        {:error, Error.new(:seshat_not_a_keepsake, :seshat_note_keepsake_not_one, path: c.path)}

      not (is_binary(c.note) and String.trim(c.note) != "" and String.length(c.note) <= 1_000) ->
        {:error, Error.new(:seshat_keepsake_note_invalid, :seshat_note_keepsake_invalid)}

      Map.get(documents, c.path)[:note] == String.trim(c.note) ->
        []

      true ->
        %Events.KeepsakeNoted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          path: c.path,
          note: String.trim(c.note)
        }
    end
  end

  def execute(%__MODULE__{} = l, %Commands.OpenDiscussion{} = c) do
    cond do
      not Map.has_key?(l.documents, c.path) ->
        {:error,
         Error.new(:seshat_no_such_document, :seshat_open_discussion_no_such_document,
           path: c.path
         )}

      MapSet.member?(l.discussions, {c.path, c.session_key}) ->
        []

      true ->
        %Events.DiscussionOpened{
          actor: c.actor,
          at: c.at,
          id: c.id,
          path: c.path,
          session_key: c.session_key
        }
    end
  end

  # ---- the oracle (brain#49, seshat#34) ----

  # Each question named and its sources a list of refs; numbered in the
  # same dispatch from the oracle sequence, so a replay reproduces them.
  def execute(%__MODULE__{oracles: oracles}, %Commands.DispatchOracle{} = c) do
    questions = List.wrap(c.questions)

    if questions != [] and Enum.all?(questions, &oracle_question?/1) do
      first = (oracles |> Map.keys() |> Enum.max(fn -> 0 end)) + 1

      questions
      |> Enum.with_index(first)
      |> Enum.map(fn {q, n} ->
        %Events.OracleDispatched{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: n,
          question: String.trim(q.question),
          sources: q.sources,
          session_key: c.session_key
        }
      end)
    else
      {:error, Error.new(:seshat_oracle_invalid, :seshat_dispatch_oracle_invalid)}
    end
  end

  def execute(%__MODULE__{oracles: oracles}, %Commands.AnswerOracle{} = c) do
    case Map.get(oracles, c.number) do
      nil ->
        {:error,
         Error.new(:seshat_no_such_oracle, :seshat_answer_oracle_absent, number: c.number)}

      :open ->
        %Events.OracleAnswered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          path: c.path,
          confidence: c.confidence,
          read: c.read || [],
          used: c.used || [],
          model: c.actor.model
        }

      _settled ->
        []
    end
  end

  def execute(%__MODULE__{oracles: oracles}, %Commands.FailOracle{} = c) do
    case Map.get(oracles, c.number) do
      nil ->
        {:error, Error.new(:seshat_no_such_oracle, :seshat_fail_oracle_absent, number: c.number)}

      :open ->
        %Events.OracleFailed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          reason: c.reason
        }

      _settled ->
        []
    end
  end

  # External sources (seshat#46). A key already commissioned is no
  # event: the service answers its number. A fetch is asked of a source
  # that is not already waiting for one; a copy or a failure answers
  # only an asked fetch, so a reader's retry records nothing twice.
  def execute(%__MODULE__{} = l, %Commands.CommissionExternal{} = c) do
    cond do
      not party?(c.actor) ->
        {:error, Error.new(:seshat_external_not_allowed, :seshat_commission_external_actor)}

      Map.has_key?(l.external_keys, c.key) ->
        []

      true ->
        %Events.ExternalCommissioned{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: map_size(l.externals) + 1,
          kind: c.kind,
          key: c.key,
          url: c.url,
          ref: c.ref,
          session_key: c.session_key
        }
    end
  end

  def execute(%__MODULE__{externals: externals}, %Commands.AskExternalFetch{} = c) do
    case Map.get(externals, c.number) do
      nil ->
        {:error,
         Error.new(:seshat_no_such_external, :seshat_ask_external_absent, number: c.number)}

      _external when c.actor.kind not in [:resident, :witness] ->
        {:error, Error.new(:seshat_external_not_allowed, :seshat_ask_external_actor)}

      %{state: :asked} ->
        []

      _settled ->
        %Events.ExternalFetchAsked{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          session_key: c.session_key
        }
    end
  end

  def execute(%__MODULE__{externals: externals}, %Commands.RecordExternalFetch{} = c) do
    case Map.get(externals, c.number) do
      _any when c.actor.kind not in [:hands, :witness] ->
        {:error, Error.new(:seshat_external_not_allowed, :seshat_record_external_actor)}

      nil ->
        {:error,
         Error.new(:seshat_no_such_external, :seshat_record_external_absent, number: c.number)}

      %{state: :asked} ->
        %Events.ExternalFetched{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          path: c.path,
          title: c.title,
          content_hash: c.content_hash,
          commit: c.commit,
          bytes: c.bytes
        }

      _not_asked ->
        []
    end
  end

  def execute(%__MODULE__{externals: externals}, %Commands.FailExternalFetch{} = c) do
    case Map.get(externals, c.number) do
      _any when c.actor.kind not in [:hands, :witness] ->
        {:error, Error.new(:seshat_external_not_allowed, :seshat_fail_external_actor)}

      nil ->
        {:error,
         Error.new(:seshat_no_such_external, :seshat_fail_external_absent, number: c.number)}

      %{state: :asked} ->
        %Events.ExternalFetchFailed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          reason: c.reason
        }

      _not_asked ->
        []
    end
  end

  # Research (seshat#38): a named question of at most 2,000 characters,
  # at most ten pages to start from, each an http(s) URL.
  def execute(%__MODULE__{researches: researches}, %Commands.AskResearch{} = c) do
    question = String.trim(to_string(c.question || ""))
    urls = List.wrap(c.urls)

    if question != "" and String.length(question) <= 2000 and length(urls) <= 10 and
         Enum.all?(urls, &(is_binary(&1) and Regex.match?(@url, &1))) do
      %Events.ResearchAsked{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: (researches |> Map.keys() |> Enum.max(fn -> 0 end)) + 1,
        question: question,
        urls: urls,
        session_key: c.session_key
      }
    else
      {:error, Error.new(:seshat_research_invalid, :seshat_ask_research_invalid)}
    end
  end

  def execute(%__MODULE__{researches: researches}, %Commands.AnswerResearch{} = c) do
    case Map.get(researches, c.number) do
      nil ->
        {:error,
         Error.new(:seshat_no_such_research, :seshat_answer_research_absent, number: c.number)}

      :open ->
        %Events.ResearchAnswered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          path: c.path,
          sources: c.sources || []
        }

      _settled ->
        []
    end
  end

  def execute(%__MODULE__{researches: researches}, %Commands.FailResearch{} = c) do
    case Map.get(researches, c.number) do
      nil ->
        {:error,
         Error.new(:seshat_no_such_research, :seshat_fail_research_absent, number: c.number)}

      :open ->
        %Events.ResearchFailed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          reason: c.reason
        }

      _settled ->
        []
    end
  end

  # Seshat #40: one digest open at a time; asking while one is open is
  # no event, and the service answers with the open one's number.
  def execute(%__MODULE__{digests: digests}, %Commands.AskDigest{} = c) do
    cond do
      not match?(%DateTime{}, c.since) ->
        {:error, Error.new(:seshat_digest_invalid, :seshat_ask_digest_since)}

      Enum.any?(digests, fn {_n, state} -> state == :open end) ->
        []

      true ->
        %Events.DigestAsked{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: (digests |> Map.keys() |> Enum.max(fn -> 0 end)) + 1,
          session_key: c.session_key,
          since: c.since
        }
    end
  end

  def execute(%__MODULE__{digests: digests}, %Commands.AnswerDigest{} = c) do
    case Map.get(digests, c.number) do
      nil ->
        {:error,
         Error.new(:seshat_no_such_digest, :seshat_answer_digest_absent, number: c.number)}

      :open ->
        %Events.DigestAnswered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          path: c.path,
          items: c.items || 0
        }

      _settled ->
        []
    end
  end

  def execute(%__MODULE__{digests: digests}, %Commands.FailDigest{} = c) do
    case Map.get(digests, c.number) do
      nil ->
        {:error, Error.new(:seshat_no_such_digest, :seshat_fail_digest_absent, number: c.number)}

      :open ->
        %Events.DigestFailed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          reason: c.reason
        }

      _settled ->
        []
    end
  end

  def apply(%__MODULE__{} = l, %Events.DigestAsked{} = e),
    do: %{l | id: e.id, digests: Map.put(l.digests, e.number, :open)}

  def apply(%__MODULE__{} = l, %Events.DigestAnswered{} = e),
    do: %{l | digests: Map.put(l.digests, e.number, :answered)}

  def apply(%__MODULE__{} = l, %Events.DigestFailed{} = e),
    do: %{l | digests: Map.put(l.digests, e.number, :failed)}

  def apply(%__MODULE__{} = l, %Events.ExternalCommissioned{} = e) do
    %{
      l
      | id: e.id,
        externals: Map.put(l.externals, e.number, %{key: e.key, state: :asked}),
        external_keys: Map.put(l.external_keys, e.key, e.number)
    }
  end

  def apply(%__MODULE__{} = l, %Events.ExternalFetchAsked{} = e),
    do: put_in(l.externals[e.number].state, :asked)

  def apply(%__MODULE__{} = l, %Events.ExternalFetched{} = e),
    do: put_in(l.externals[e.number].state, :fetched)

  def apply(%__MODULE__{} = l, %Events.ExternalFetchFailed{} = e),
    do: put_in(l.externals[e.number].state, :failed)

  def apply(%__MODULE__{} = l, %Events.ResearchAsked{} = e),
    do: %{l | id: e.id, researches: Map.put(l.researches, e.number, :open)}

  def apply(%__MODULE__{} = l, %Events.ResearchAnswered{} = e),
    do: %{l | researches: Map.put(l.researches, e.number, :answered)}

  def apply(%__MODULE__{} = l, %Events.ResearchFailed{} = e),
    do: %{l | researches: Map.put(l.researches, e.number, :failed)}

  def apply(%__MODULE__{} = l, %Events.OracleDispatched{} = e),
    do: %{l | id: e.id, oracles: Map.put(l.oracles, e.number, :open)}

  def apply(%__MODULE__{} = l, %Events.OracleAnswered{} = e),
    do: %{l | oracles: Map.put(l.oracles, e.number, :answered)}

  def apply(%__MODULE__{} = l, %Events.OracleFailed{} = e),
    do: %{l | oracles: Map.put(l.oracles, e.number, :failed)}

  def apply(%__MODULE__{} = s, %Events.DocumentMoved{} = e) do
    {doc, documents} = Map.pop(s.documents, e.from)
    %{s | documents: Map.put(documents, e.to, %{doc | kind: Kinds.released(e.to_kind)})}
  end

  def apply(%__MODULE__{} = s, %Events.DocumentRemoved{} = e),
    do: %{s | documents: Map.delete(s.documents, e.path)}

  def apply(%__MODULE__{} = l, %Events.DocumentWritten{} = e), do: register(l, e)

  def apply(%__MODULE__{documents: docs} = l, %Events.DocumentArchived{} = e),
    do: %{
      l
      | documents:
          docs
          |> Map.put(e.to, %{kind: "archive", hash: e.archived_hash})
          |> Map.put(e.path, %{kind: "tombstone", hash: e.tombstone_hash})
    }

  def apply(%__MODULE__{documents: docs} = l, %Events.KeepsakeRegistered{path: path}),
    do: %{l | documents: Map.update!(docs, path, &Map.put(&1, :kind, "keepsake"))}

  def apply(%__MODULE__{} = l, %Events.DocumentAdopted{} = e), do: register(l, e)

  def apply(%__MODULE__{} = l, %Events.KeepsakeNoted{} = e),
    do: %{l | documents: Map.update!(l.documents, e.path, &Map.put(&1, :note, e.note))}

  # Updated by key, not with `put_in(l.documents[path].url, url)` as the
  # first version had it: that form returns the whole struct, so the
  # documents map became the aggregate itself and every other document
  # was lost from the state on the first publish. The HTTP suite found
  # it as a wiki page that could not be published because it was no
  # longer there.
  def apply(%__MODULE__{} = l, %Events.PiecePublished{} = e),
    do: %{l | documents: Map.update!(l.documents, e.path, &%{&1 | url: e.url})}

  def apply(%__MODULE__{} = l, %Events.DiscussionOpened{} = e),
    do: %{l | discussions: MapSet.put(l.discussions, {e.path, e.session_key})}

  defp register(l, e) do
    kind = Kinds.released(e.kind)
    doc = Map.get(l.documents, e.path, %{kind: kind, hash: nil, url: nil})
    %{l | id: e.id, documents: Map.put(l.documents, e.path, %{doc | kind: kind, hash: e.hash})}
  end

  defp has_status?(kind) do
    case Enum.find(Kinds.all(), &(&1.kind == kind)) do
      nil -> false
      k -> k.has_status
    end
  end

  defp oracle_question?(%{question: q, sources: sources}),
    do:
      is_binary(q) and String.trim(q) != "" and is_list(sources) and
        Enum.all?(sources, &is_binary/1)

  defp oracle_question?(_other), do: false

  # Commissioning a source is a dyad act (seshat#46): either party.
  defp party?(%{kind: kind}), do: kind in [:resident, :witness]
end
