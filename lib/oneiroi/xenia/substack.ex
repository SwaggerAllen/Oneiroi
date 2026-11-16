defmodule Oneiroi.Xenia.Substack do
  @moduledoc """
  The Substack reads presence makes (xenia#20), on public endpoints
  verified 2026-11-15 without signing in: a profile's public
  subscriptions, a publication's posts and a person's notes since a
  time, each with its likes, comments and restacks, and an item's whole
  text. Nothing here writes: interactions go out through the reader, in
  the witness's own browser, and no Substack credential is held here.

  `XENIA_SUBSTACK_CLIENT` names the port: `http` in every real build,
  `fake` in test (conventions §9).
  """

  @typedoc "A publication the profile subscribes to, keyed by its subdomain."
  @type account :: %{
          key: String.t(),
          name: String.t() | nil,
          host: String.t(),
          publication_id: integer() | nil,
          author_id: integer() | nil
        }

  @typedoc "A post or a note, keyed `p-<id>` or `c-<id>` as Substack keys its feed."
  @type item :: %{
          key: String.t(),
          kind: String.t(),
          account: String.t(),
          title: String.t() | nil,
          url: String.t(),
          at: DateTime.t(),
          likes: non_neg_integer(),
          comments: non_neg_integer(),
          restacks: non_neg_integer(),
          excerpt: String.t()
        }

  @doc "A profile by handle: its id, its public subscriptions, and how many the profile says are visible."
  @callback profile(handle :: String.t()) ::
              {:ok, %{id: integer(), accounts: [account()], visible: non_neg_integer() | nil}}
              | {:error, term()}

  @doc "An account's posts, and its author's own notes, published after `since`, newest first."
  @callback items(account :: account(), since :: DateTime.t()) ::
              {:ok, [item()]} | {:error, term()}

  @doc "An item's whole text, as plain text."
  @callback text(item :: %{key: String.t(), url: String.t()}) ::
              {:ok, String.t()} | {:error, term()}

  @doc "The configured port."
  def client, do: Oneiroi.Config.fetch!(:xenia, :substack_client)
end
