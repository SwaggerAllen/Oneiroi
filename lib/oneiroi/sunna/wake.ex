defmodule Oneiroi.Sunna.Wake do
  @moduledoc """
  The wake port (spec §6.7, §8): what the schedule calls when a check-in
  fires or free time opens, with the core's note and the purpose the
  answer is billed under. The in-core brain answers it; a brain adapter
  wired by remote trigger will answer it the same way.

  A port rather than a call, because the brain reads this system's dates
  on every turn (the countdowns, spec §6.7) and the schedule wakes the
  brain: a direct call each way is a cycle Boundary and `mix xref graph
  --format cycles` both reject. The implementation is named in
  `SUNNA_WAKE`, the same shape as the ledger's provider port, and is read
  at the call, so neither compiler sees an edge.
  """

  @doc "Wakes the resident in the session with the note; the answer is a captured turn."
  @callback wake(
              resident_id :: String.t(),
              session_key :: String.t(),
              note :: String.t(),
              purpose :: atom()
            ) :: {:ok, map()} | {:error, term()}

  @doc """
  One part of a check-in's note (sunna#28), by its catalog key, read now:
  the text to carry, or nil when the implementation has no such part. The
  dates are this system's own and never asked.
  """
  @callback checkin_part(resident_id :: String.t(), key :: String.t()) :: String.t() | nil

  @doc """
  Whether a digest is asked and not yet settled (sunna#61): a check-in
  carrying the digest part waits on it, so the note it fires with holds
  the digest, not the asking.
  """
  @callback digest_pending?(resident_id :: String.t()) :: boolean()

  @doc """
  The note for turn `n` of a night pass after the scene pass (sunna#57):
  `pass` is `people` or `behaviour`, `day` the ISO day. `{:ok, note}`, or
  `:skip` when the day gives the pass nothing to do (no names in the
  scene rows, no scenes at all). The scene rows are the library's, which
  the brain reads and this system does not.
  """
  @callback night_pass_note(
              resident_id :: String.t(),
              pass :: String.t(),
              day :: String.t(),
              n :: pos_integer()
            ) :: {:ok, String.t()} | :skip

  @doc """
  The note for turn `n` of a backfill pass (sunna#59): `pass` is
  `scenes`, `domains` or `people`, `day` the ISO day, `lists` the
  witness's (`"his"`) and her (`"hers"`) domain slugs. `{:ok, note}`, or
  `:skip` when the day gives the pass nothing (a day already closed, no
  conversations, no scenes).
  """
  @callback backfill_note(
              resident_id :: String.t(),
              pass :: String.t(),
              day :: String.t(),
              n :: pos_integer(),
              lists :: map()
            ) :: {:ok, String.t()} | :skip

  @doc """
  A wake whose answer goes past the dyad (kumbukumbu#81): the same as
  `wake/4`, with the audience the answer reaches (`audience:`), so her
  context for it is assembled for that audience. An implementation
  without it is woken by `wake/4`.
  """
  @callback wake_for(
              resident_id :: String.t(),
              session_key :: String.t(),
              note :: String.t(),
              purpose :: atom(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, term()}

  @doc """
  The backfill's labels pass over its range (kumbukumbu#101): no model,
  each record written in it labelled again from its turn and what it
  cites, the citation graph closed once over the whole range.
  """
  @callback backfill_labels(
              resident_id :: String.t(),
              from_day :: String.t(),
              to_day :: String.t()
            ) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  The conversations of `day` the backfill's domains pass has not yet named
  (sunna#89): the pass carries on while any is left.
  """
  @callback backfill_left(resident_id :: String.t(), day :: String.t()) :: [String.t()]

  @doc """
  Performs a mechanical house queue activity with no agent turn
  (sunna#104): a `promote-to-house` of the resident's own document, at
  the revision its review approved. `:ok` when the activity is finished;
  `{:error, reason}` leaves it hers to do in a run.
  """
  @callback promote_activity(
              resident_id :: String.t(),
              household_id :: String.t(),
              task :: pos_integer(),
              act :: String.t()
            ) :: :ok | {:error, term()}

  @optional_callbacks wake_for: 5,
                      promote_activity: 4,
                      backfill_left: 2,
                      backfill_labels: 3,
                      checkin_part: 2,
                      digest_pending?: 1,
                      night_pass_note: 4,
                      backfill_note: 5
end
