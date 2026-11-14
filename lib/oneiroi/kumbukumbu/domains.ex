defmodule Oneiroi.Kumbukumbu.Domains do
  @moduledoc """
  Domains per message (P23-R1, kumbukumbu#72): the one place that says
  which domain a conversation is in now, which a memory is in, and what
  retrieval does across the line.

  A domain is a pair, `%{person: "account:<id>" | "resident:<id>",
  domain: slug}`: whose life, and which part of it. nil is the common
  room. A message takes its domain as it lands, by precedence: the tag a
  party gave its turn, else the conversation's current domain (the last
  one named in it, carried forward to every untagged message after it,
  incoming and outgoing), else the common room. Her reply is in the
  domain of the message it answers, since both are one turn. Named by
  people, never detected.

  Retrieval hints rather than walls: a memory of the current domain or
  the common room may be put in front of her; one of another domain that
  ranks in is named as a door, by its number and domain alone, and never
  shown; her deliberate reach (`bookmark_open`, a transcript read, a
  search across domains) is never scoped. A wall is a contract term
  (agathos-daimon#45): it closes the door for the pair it names, never
  her reach.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Kumbukumbu.Store.{Message, Session}
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @type t :: %{person: String.t(), domain: String.t()} | nil

  # The kinds held with the witness; every other kind is hers alone, and
  # a domain in it is of her life.
  @with_witness ~w(main adapter imported)

  @doc """
  The conversation's current domain: the last one a party named in it,
  else nil. A session that opened with a domain before P23-R1 counts it
  as named at its opening, with its counterpart as the person.
  """
  @spec current(String.t(), String.t() | nil) :: t()
  def current(_resident_id, nil), do: nil

  def current(resident_id, session_key) do
    Scope.resident(resident_id, fn ->
      Repo.one(from(s in Session, where: s.key == ^session_key))
    end)
    |> of_session(resident_id)
  end

  @doc "A session row's current domain (`current/2` without the read)."
  @spec of_session(map() | nil, String.t()) :: t()
  def of_session(nil, _resident_id), do: nil

  def of_session(%{current_set: true} = s, _resident_id),
    do: pair(s.current_person, s.current_domain)

  def of_session(%{domain: domain} = s, resident_id) when is_binary(domain),
    do: pair(counterpart(s, resident_id), domain)

  def of_session(_session, _resident_id), do: nil

  @doc "Whose life a session's messages are, unless a tag says another: the witness's for a conversation with him, hers for her own."
  @spec counterpart(map(), String.t()) :: String.t()
  def counterpart(%{kind: kind, account_id: account}, _resident_id)
      when kind in @with_witness and is_binary(account),
      do: "account:" <> account

  def counterpart(_session, resident_id), do: "resident:" <> resident_id

  @doc "A pair, or nil for the common room."
  @spec pair(String.t() | nil, String.t() | nil) :: t()
  def pair(_person, nil), do: nil
  def pair(nil, _domain), do: nil
  def pair(person, domain), do: %{person: person, domain: domain}

  @doc """
  Each memory with its domain, by its anchor turn (`session_key`,
  `anchor_ref`): the domain its messages carry, else, for a turn not yet
  captured (a bookmark made inside it), its conversation's current one.
  Read under the resident's scope.
  """
  @spec attach(String.t(), [map()]) :: [map()]
  def attach(_resident_id, []), do: []

  def attach(resident_id, memories) do
    refs = memories |> Enum.map(& &1.anchor_ref) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    keys = memories |> Enum.map(& &1.session_key) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    {by_turn, sessions} =
      Scope.resident(resident_id, fn ->
        turns =
          from(m in Message,
            where: m.turn_ref in ^refs and m.session_key in ^keys,
            distinct: [m.session_key, m.turn_ref],
            select: {{m.session_key, m.turn_ref}, {m.domain_person, m.domain}}
          )
          |> Repo.all()
          |> Map.new()

        {turns, Map.new(Repo.all(from(s in Session, where: s.key in ^keys)), &{&1.key, &1})}
      end)

    Enum.map(memories, fn m ->
      key =
        case Map.fetch(by_turn, {m.session_key, m.anchor_ref}) do
          {:ok, {person, domain}} -> pair(person, domain)
          :error -> of_session(sessions[m.session_key], resident_id)
        end

      Map.put(m, :domain_key, key)
    end)
  end

  @doc "Whether a memory of `key` may be put in front of a turn in `current`: its own domain, or the common room."
  @spec in_domain?(t(), t()) :: boolean()
  def in_domain?(nil, _current), do: true
  def in_domain?(key, current), do: key == current

  @doc """
  Whether the contract walls a memory of `key` from a turn in `current`
  (agathos-daimon#45): a wall closes the door, so the near-miss row is
  not written. Never consulted for her deliberate reach.
  """
  @spec walled?(String.t(), t(), t()) :: boolean()
  def walled?(_resident_id, nil, _current), do: false

  def walled?(resident_id, key, current),
    do: resident_id |> AgathosDaimon.domain_walls() |> walled_by?(key, current)

  @doc "The same test over walls already read, for a list (`walls/1` once, then this per memory)."
  @spec walled_by?([map()], t(), t()) :: boolean()
  def walled_by?(_walls, nil, _current), do: false

  def walled_by?(walls, key, current) do
    Enum.any?(walls, fn w ->
      w.memory == key and matches?(w.context, current)
    end)
  end

  # A wall's context side may name anyone (`"*"`) or any domain of a
  # person; the common room is matched by `%{person: "*", domain: "*"}`
  # alone.
  defp matches?(%{person: "*", domain: "*"}, _current), do: true
  defp matches?(_context, nil), do: false
  defp matches?(%{person: "*", domain: d}, %{domain: d}), do: true
  defp matches?(%{person: p, domain: "*"}, %{person: p}), do: true
  defp matches?(%{person: p, domain: d}, %{person: p, domain: d}), do: true
  defp matches?(_context, _current), do: false

  @doc "The walls in force for the resident, read once (`AgathosDaimon.domain_walls/1`)."
  @spec walls(String.t()) :: [map()]
  def walls(resident_id), do: AgathosDaimon.domain_walls(resident_id)

  @doc "A domain in words, for a door or a line: its slug, or the common room."
  @spec name(t()) :: String.t()
  def name(nil), do: "the common room"
  def name(%{domain: domain}), do: domain

  @doc "The door a memory of another domain is named by (P23-R1 §2): its number and domain, never its words."
  @spec door(String.t(), pos_integer() | String.t(), t()) :: String.t()
  def door(kind, number, key),
    do: "nearby: #{kind} ##{number} (#{name(key)}), another domain; open it if you want it"
end
