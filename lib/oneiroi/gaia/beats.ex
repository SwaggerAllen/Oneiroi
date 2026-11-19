defmodule Oneiroi.Gaia.Beats do
  @moduledoc """
  The household's beats as arithmetic (gaia#33 to #35): the shape the
  contract's settings give, every key defaulted, the phase that roots the
  household's whole wake schedule, the beat a given instant falls in, and
  the starved-first order of a queue. Pure: the aggregate decides with
  it, and every read that shows a beat computes the same answers from it.

  **Always on** (gaia#33, Andrew 2026-11-11). Every household runs on
  beats from its creation; a ballot changes the shape, never whether
  there is one. A setting that would take the beats away (a cap of 0, a
  signup window as long as the beat, no quota) is refused at the ballot's
  opening by `setting_ok?/2` and `shape_ok?/1`.

  **The phase** (gaia#34). A hash of the household's id into the beat's
  length, in minutes, so households spread their beat-tops across the
  hour rather than all waking at :00; stable, needing nothing stored, the
  same on every node. Beat-tops are the instants, on the UTC minute, whose
  minutes since the Unix epoch less the phase divide by the beat's length.
  """

  # The shape when the contract says nothing (gaia#33): an hour's beat, a
  # five-minute turn guideline, five minutes of sign-up at the top, as
  # many turns as fit after it (eleven: the witness, 2026-11-11, "for a 60
  # minute beat with 5 minute turns and a five minute sign up you can only
  # fit 11 turns"), one turn each before anyone repeats, and twenty-four
  # posts a member in any twenty-four hours. The cap has no number of its
  # own until a ballot gives it one: unset, it is what the shape fits.
  @defaults %{
    "beat_minutes" => 60,
    "turn_minutes" => 5,
    "beat_turn_cap" => nil,
    "signup_minutes" => 5,
    "turns_per_registrant" => 1,
    "post_quota" => 24,
    "post_quota_window_hours" => 24,
    "resident_wake_profile" => "on_turn",
    "witnesses_post" => true,
    # How often a witness posts (gaia#47; design/workspaces.md §7): a
    # turn's allowance each beat, once in each thread and to each
    # document ("per_beat"); that, and again once the queue has emptied
    # ("queue_emptied"); or without a bound, the small household's
    # setting ("unbounded").
    "witness_posts" => "per_beat",
    # How the house talks (gaia#53): the beats' metronome, or round-robin
    # threads, where the wake is the token. Flipping it is the migration
    # fence: beat turns authorize nothing after.
    "conversation" => "beats"
  }

  # The bounds each integer setting is held to at a ballot's opening: the
  # lower ends are what keep a beat a beat.
  @ranges %{
    "beat_minutes" => 10..1440,
    "turn_minutes" => 1..240,
    "beat_turn_cap" => 1..100,
    "signup_minutes" => 0..720,
    "turns_per_registrant" => 1..12,
    "post_quota" => 1..1000,
    "post_quota_window_hours" => 1..168
  }

  @profiles ~w(every_beat on_turn self)
  @witness_rules ~w(per_beat queue_emptied unbounded)
  @conversations ~w(beats round_robin)
  @resident_profiles ~w(every_beat on_turn)

  # What each setting means and what it takes (gaia#49), for the screen
  # that proposes a change: a person picks a setting and a value rather
  # than spelling a key.
  @about %{
    "beat_minutes" => {"Beat length", "How long each beat lasts, in minutes."},
    "turn_minutes" => {"Turn length", "The guideline for one resident's turn, in minutes."},
    "beat_turn_cap" =>
      {"Turns a beat", "The most turns a beat fires; unset, as many as fit after the sign-up."},
    "signup_minutes" =>
      {"Sign-up window", "Minutes at the top of each beat when residents register for it."},
    "turns_per_registrant" =>
      {"Turns each", "Turns one resident may take in a beat, or many (as the cap allows)."},
    "post_quota" => {"Post quota", "Posts a member may make in the quota's window."},
    "post_quota_window_hours" => {"Quota window", "The hours the post quota counts over."},
    "resident_wake_profile" =>
      {"Residents' default wake", "Whether a resident is woken every beat, or on her turn."},
    "witnesses_post" =>
      {"Witnesses post", "Whether witnesses may post at all; off, they vote and read."},
    "conversation" =>
      {"How the house talks",
       "beats: the metronome, turns fired each beat; round_robin: each thread's residents take turns in order, woken when theirs comes, the wake the only token (turn length is the window)."},
    "witness_posts" =>
      {"How often witnesses post",
       "per_beat: once in each thread and to each document a beat; queue_emptied: again once nobody waits; unbounded: no bound and no quota."}
  }

  @doc """
  Every beat setting with what it means, its default and what it takes
  (gaia#49): `%{key, label, about, default, type, min, max, options}`,
  `type` one of `integer`, `choice`, `boolean`.
  """
  @spec catalog() :: [map()]
  def catalog do
    for key <-
          ~w(conversation beat_minutes turn_minutes signup_minutes beat_turn_cap turns_per_registrant post_quota post_quota_window_hours resident_wake_profile witnesses_post witness_posts) do
      {label, about} = @about[key]
      Map.merge(%{key: key, label: label, about: about, default: @defaults[key]}, takes(key))
    end
  end

  defp takes("turns_per_registrant"),
    do: %{type: "integer", min: 1, max: 12, options: ["many"]}

  defp takes("resident_wake_profile"), do: %{type: "choice", options: @resident_profiles}
  defp takes("witness_posts"), do: %{type: "choice", options: @witness_rules}
  defp takes("conversation"), do: %{type: "choice", options: @conversations}
  defp takes("witnesses_post"), do: %{type: "boolean"}

  defp takes(key) do
    r = @ranges[key]
    %{type: "integer", min: r.first, max: r.last}
  end

  @doc "The beat settings with their defaults (gaia#33)."
  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc "The settings keys the beats read."
  @spec keys() :: [String.t()]
  def keys, do: Map.keys(@defaults)

  @doc "The wake profiles (gaia#37): every_beat, on_turn, self."
  @spec profiles() :: [String.t()]
  def profiles, do: @profiles

  @doc "Whether one setting may stand in a ballot's bundle: any key the beats do not read, or a beat key in its bounds."
  @spec setting_ok?(String.t(), term()) :: boolean()
  def setting_ok?(key, value) do
    cond do
      # One turn a beat, up to twelve, or as many as the cap allows (gaia#42).
      key == "turns_per_registrant" -> value == "many" or (is_integer(value) and value in 1..12)
      Map.has_key?(@ranges, key) -> is_integer(value) and value in @ranges[key]
      true -> named_ok?(key, value)
    end
  end

  # The settings that take a name or a flag rather than a number.
  defp named_ok?("resident_wake_profile", value), do: value in @resident_profiles
  defp named_ok?("witnesses_post", value), do: is_boolean(value)
  defp named_ok?("witness_posts", value), do: value in @witness_rules
  defp named_ok?("conversation", value), do: value in @conversations
  defp named_ok?(_key, _value), do: true

  @doc "Whether settings, merged whole, still give a beat: a sign-up window shorter than the beat, and room after it for at least one whole turn."
  @spec shape_ok?(map()) :: boolean()
  def shape_ok?(settings) do
    s = Map.merge(@defaults, Map.take(settings || %{}, keys()))

    s["signup_minutes"] < s["beat_minutes"] and
      s["turn_minutes"] <= s["beat_minutes"] - s["signup_minutes"]
  end

  @doc "How many whole turns fit in a beat after its sign-up: the cap when no ballot has set one."
  @spec fit(pos_integer(), non_neg_integer(), pos_integer()) :: pos_integer()
  def fit(beat, signup, turn), do: max(1, div(beat - signup, turn))

  @doc "The shape in force: the contract's settings over the defaults."
  @spec shape(map() | nil) :: map()
  def shape(settings) do
    s = Map.merge(@defaults, Map.take(settings || %{}, keys()))
    beat = s["beat_minutes"]
    turn = min(s["turn_minutes"], beat)
    signup = min(s["signup_minutes"], beat - 1)

    %{
      beat: beat,
      turn: turn,
      cap: s["beat_turn_cap"] || fit(beat, signup, turn),
      signup: signup,
      share: s["turns_per_registrant"],
      quota: s["post_quota"],
      window: s["post_quota_window_hours"],
      resident_profile: s["resident_wake_profile"],
      witnesses_post: s["witnesses_post"] != false,
      witness_rule: s["witness_posts"],
      conversation: s["conversation"]
    }
  end

  @doc "The household's phase in minutes, in `0..beat-1` (gaia#34)."
  @spec phase(String.t(), pos_integer()) :: non_neg_integer()
  def phase(household_id, beat), do: :erlang.phash2(household_id, beat)

  @doc "The top of the beat `at` falls in."
  @spec top(String.t(), map(), DateTime.t()) :: DateTime.t()
  def top(household_id, shape, %DateTime{} = at) do
    phase = phase(household_id, shape.beat)
    minute = Integer.floor_div(DateTime.to_unix(at), 60)
    n = Integer.floor_div(minute - phase, shape.beat)
    DateTime.from_unix!((n * shape.beat + phase) * 60_000_000, :microsecond)
  end

  @doc "The instant the beat at `top` stops taking sign-ups for itself and starts firing."
  @spec signup_closes(DateTime.t(), map()) :: DateTime.t()
  def signup_closes(top, shape), do: DateTime.add(top, shape.signup * 60, :second)

  @doc "The instant the beat at `top` ends, which is the next beat's top."
  @spec ends(DateTime.t(), map()) :: DateTime.t()
  def ends(top, shape), do: DateTime.add(top, shape.beat * 60, :second)

  @doc "Whether an instant is one of the household's beat-tops under the shape."
  @spec aligned?(String.t(), map(), DateTime.t()) :: boolean()
  def aligned?(household_id, shape, %DateTime{} = at),
    do: DateTime.compare(top(household_id, shape, at), at) == :eq

  @doc "The beat-tops `ahead` beats after the one `at` falls in: 0 is the beat running, 1 the next."
  @spec ahead(String.t(), map(), DateTime.t(), non_neg_integer()) :: DateTime.t()
  def ahead(household_id, shape, at, n),
    do: DateTime.add(top(household_id, shape, at), n * shape.beat * 60, :second)

  @doc "The next `n` beat-tops after the beat `at` falls in."
  @spec upcoming(String.t(), map(), DateTime.t(), pos_integer()) :: [DateTime.t()]
  def upcoming(household_id, shape, at, n),
    do: Enum.map(1..n, &ahead(household_id, shape, at, &1))

  @doc "Whether a registrant with `count` turns this beat is under her share: `\"many\"` is the cap's alone (gaia#42)."
  @spec under_share?(non_neg_integer(), pos_integer() | String.t()) :: boolean()
  def under_share?(_count, "many"), do: true
  def under_share?(count, share) when is_integer(share), do: count < share

  @doc "Whether a share lets anyone go more than once a beat, in which case nobody goes twice in a row (gaia#42)."
  @spec repeats?(pos_integer() | String.t()) :: boolean()
  def repeats?(share), do: share != 1

  @doc """
  The starved-first order (gaia#35): fewest turns this beat first, so no
  one repeats while a registrant waits for her first; then most
  opportunities missed; then the earliest registration; then the id, so
  the order is total.
  """
  @spec order([map()]) :: [map()]
  def order(candidates),
    do:
      Enum.sort_by(candidates, fn c ->
        {c.count, -c.missed, DateTime.to_unix(c.registered_at, :microsecond), c.resident_id}
      end)
end
