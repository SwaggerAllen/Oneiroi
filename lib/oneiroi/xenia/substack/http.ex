defmodule Oneiroi.Xenia.Substack.Http do
  @moduledoc """
  The Substack port on its public JSON endpoints (xenia#20), each
  verified signed out on 2026-11-15:

  - `substack.com/api/v1/user/<handle>/public_profile`: the profile's id,
    its public subscriptions and `visibleSubscriptionsCount`, which the
    list is checked against;
  - `<host>/api/v1/archive?sort=new&limit=…[&cursor=…]`: a publication's
    posts, newest first, with `reaction_count`, `comment_count` and
    `restacks`, paged by `nextCursor`;
  - `substack.com/api/v1/reader/feed/profile/<user_id>[?cursor=…]`: a
    person's feed, of which only their own notes are kept (`context.type`
    `note`, `user_id` theirs), not what they restacked;
  - `<host>/api/v1/posts/<slug>` and `substack.com/api/v1/reader/comment/<id>`:
    one item whole.

  Reads only. A page is at most `@limit` items and an account at most
  `@pages` pages, so an account that posted more since its last sample
  than that hands forward what it can.
  """
  @behaviour Oneiroi.Xenia.Substack

  alias Oneiroi.Xenia.Error

  @root "https://substack.com"
  @limit 20
  @pages 3
  @excerpt 400
  @agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

  @impl true
  def profile(handle) do
    with {:ok, body} <- get("#{@root}/api/v1/user/#{URI.encode(handle)}/public_profile", []) do
      {:ok,
       %{
         id: body["id"],
         visible: body["visibleSubscriptionsCount"],
         accounts:
           body
           |> Map.get("subscriptions", [])
           |> Enum.map(&account(&1["publication"] || %{}))
           |> Enum.reject(&is_nil(&1.key))
       }}
    end
  end

  defp account(pub) do
    key = pub["subdomain"]

    %{
      key: key,
      name: pub["name"],
      host: host(pub, key),
      publication_id: pub["id"],
      author_id: pub["author_id"]
    }
  end

  defp host(%{"custom_domain" => domain}, _key) when is_binary(domain) and domain != "",
    do: "https://" <> domain

  defp host(_pub, key), do: "https://#{key}.substack.com"

  @impl true
  def items(account, since) do
    with {:ok, posts} <- posts(account, since, nil, 1, []),
         {:ok, notes} <- notes(account, since, nil, 1, []) do
      {:ok, Enum.sort_by(posts ++ notes, & &1.at, {:desc, DateTime})}
    end
  end

  defp posts(account, since, cursor, page, acc) do
    params = [sort: "new", limit: @limit] ++ if(cursor, do: [cursor: cursor], else: [])

    with {:ok, body} <- get("#{account.host}/api/v1/archive", params) do
      batch = body |> Map.get("posts", []) |> Enum.map(&post(account, &1))
      fresh = Enum.filter(batch, &after?(&1, since))
      acc = acc ++ fresh
      next = body["nextCursor"]

      if (length(fresh) == length(batch) and batch != [] and next) && page < @pages,
        do: posts(account, since, next, page + 1, acc),
        else: {:ok, acc}
    end
  end

  defp post(account, p) do
    %{
      key: "p-#{p["id"]}",
      kind: "post",
      account: account.key,
      title: p["title"],
      url: p["canonical_url"] || "#{account.host}/p/#{p["slug"]}",
      at: instant(p["post_date"]),
      likes: p["reaction_count"] || 0,
      comments: p["comment_count"] || 0,
      restacks: p["restacks"] || 0,
      excerpt: excerpt(p["truncated_body_text"] || p["description"] || "")
    }
  end

  # A publication without an author id has no notes to read.
  defp notes(%{author_id: nil}, _since, _cursor, _page, acc), do: {:ok, acc}

  defp notes(account, since, cursor, page, acc) do
    params = if cursor, do: [cursor: cursor], else: []

    with {:ok, body} <- get("#{@root}/api/v1/reader/feed/profile/#{account.author_id}", params) do
      own =
        body
        |> Map.get("items", [])
        |> Enum.filter(&own_note?(&1, account.author_id))
        |> Enum.map(&note(account, &1["comment"]))

      fresh = Enum.filter(own, &after?(&1, since))
      acc = acc ++ fresh
      next = body["nextCursor"]

      # The feed interleaves restacks out of order, so it pages on while
      # any of its own notes on a page is still fresh.
      if (fresh != [] and next) && page < @pages,
        do: notes(account, since, next, page + 1, acc),
        else: {:ok, acc}
    end
  end

  defp own_note?(
         %{"type" => "comment", "context" => %{"type" => "note"}, "comment" => c},
         author
       ),
       do: c["user_id"] == author

  defp own_note?(_item, _author), do: false

  defp note(account, c) do
    %{
      key: "c-#{c["id"]}",
      kind: "note",
      account: account.key,
      title: nil,
      url: "#{@root}/@#{c["handle"]}/note/c-#{c["id"]}",
      at: instant(c["date"]),
      likes: c["reaction_count"] || 0,
      comments: c["children_count"] || 0,
      restacks: c["restacks"] || 0,
      excerpt: excerpt(c["body"] || "")
    }
  end

  @impl true
  def text(%{key: "p-" <> _id, url: url}) do
    uri = URI.parse(url)
    slug = uri.path |> to_string() |> String.split("/p/") |> List.last()

    with {:ok, body} <- get("#{uri.scheme}://#{uri.host}/api/v1/posts/#{slug}", []),
         do: {:ok, plain(body["body_html"] || body["truncated_body_text"] || "")}
  end

  def text(%{key: "c-" <> id}) do
    with {:ok, body} <- get("#{@root}/api/v1/reader/comment/#{id}", []),
         do: {:ok, get_in(body, ["item", "comment", "body"]) || ""}
  end

  defp get(url, params) do
    # Substack's public JSON, not a model provider: presence's reads
    # (xenia#20), registered in Xenia's externals with their fake.
    # oneiroi:allow model_port
    case Req.get(url,
           params: params,
           headers: [{"user-agent", @agent}, {"accept", "application/json"}],
           retry: false,
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error,
         Error.new(:xenia_substack_failed, :xenia_substack_status, status: status, url: url)}

      {:error, exception} ->
        {:error, Error.caught(:xenia_substack_failed, :xenia_substack_transport, exception)}
    end
  end

  defp after?(%{at: nil}, _since), do: false
  defp after?(%{at: at}, since), do: DateTime.compare(at, since) == :gt

  defp instant(nil), do: nil

  defp instant(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> at
      _bad -> nil
    end
  end

  defp excerpt(text), do: text |> plain() |> String.slice(0, @excerpt)

  # Tags out, the common entities back, whitespace folded: enough to read
  # a post's words, never to render it.
  @doc false
  def plain(html) do
    html
    |> String.replace(~r{<(br|/p|/h\d|/li|/blockquote)[^>]*>}i, "\n")
    |> String.replace(~r{<[^>]+>}, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace(~r{[ \t]+}, " ")
    |> String.replace(~r{\n\s*\n+}, "\n\n")
    |> String.trim()
  end
end
