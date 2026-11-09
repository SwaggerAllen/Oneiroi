defmodule Oneiroi.Xenia.Routes do
  @moduledoc """
  The route registry (xenia#19, Lily's design/routes-as-data.md, her
  order #427): every way into or out of the house is a route, a source
  (a read that lands as documents of a kind) or a sink (a write from a
  kind that leaves, at his approval), bound to one profile, the
  capability it reads or acts through. The built-ins are the code's
  seed, rows naming what the reader already does; a resident's own
  routes are data, checked here against the safe subset. A profile is a
  signed-in context scoped to one origin; the platform's are seeded,
  any other the witness's to make, and either is his alone to revoke.

  The trust floor, held here and in `Oneiroi.Xenia.Routing`: a route's
  prompt is data and never chooses its profile, sites or landing; a
  route of hers is a source, on request, through a profile that exists,
  landing in a kind of her registry that she writes and whose approval
  stays in the house; a sink is the platform's, and serves only what
  he approved.
  """

  alias Oneiroi.Xenia.Error

  # The platform's profiles: what the reader on the witness's machine
  # already holds. `sites` names whose allowlist bounds it (the witness
  # sets both on Connections, xenia#16); `connector` a claude.ai
  # connector it reads through; `browser` the reader's profile folder.
  @profiles [
    %{
      key: "substack",
      label: "Substack",
      origin: "https://substack.com",
      browser: "browser-profile",
      sites: :scrape,
      connector: nil
    },
    %{
      key: "gmail",
      label: "Gmail",
      origin: "https://mail.google.com",
      browser: nil,
      sites: :none,
      connector: "gmail"
    },
    %{
      key: "research",
      label: "Research, signed in nowhere",
      origin: nil,
      browser: "research-profile",
      sites: :research,
      connector: nil
    },
    %{
      key: "open-web",
      label: "Plain fetch, signed in nowhere, no browser",
      origin: nil,
      browser: nil,
      sites: :none,
      connector: nil
    }
  ]

  # The built-ins (the design's table), each naming the reader's runner
  # that does it. Correspondence is split by profile, one profile to a
  # route: Substack's messages and Gmail's are two routes the one scrape
  # run serves, each only while its profile stands.
  @built_in [
    %{
      key: "correspondence-in",
      label: "Substack messages in",
      direction: "source",
      profile: "substack",
      kind: "correspondence",
      thread_key: "platform:identity:thread",
      cadence: "scheduled",
      runner: "scrape"
    },
    %{
      key: "mail-in",
      label: "Mail in",
      direction: "source",
      profile: "gmail",
      kind: "correspondence",
      thread_key: "platform:identity:thread",
      cadence: "scheduled",
      runner: "scrape"
    },
    %{
      key: "correspondence-out",
      label: "Substack replies out",
      direction: "sink",
      profile: "substack",
      kind: "correspondence",
      thread_key: "in_reply_to",
      cadence: "on_approval",
      runner: "send"
    },
    %{
      key: "mail-out",
      label: "Mail replies out",
      direction: "sink",
      profile: "gmail",
      kind: "correspondence",
      thread_key: "in_reply_to",
      cadence: "on_approval",
      runner: "send"
    },
    %{
      key: "digests",
      label: "Digests",
      direction: "source",
      profile: "gmail",
      kind: "feeds",
      thread_key: "digest:<n>",
      cadence: "on_request",
      runner: "digest"
    },
    %{
      key: "research",
      label: "Research",
      direction: "source",
      profile: "research",
      kind: "research",
      thread_key: "research:<n>",
      cadence: "on_request",
      runner: "research"
    },
    %{
      key: "external",
      label: "External sources",
      direction: "source",
      profile: "open-web",
      kind: "external",
      thread_key: "external:<n>",
      cadence: "on_request",
      runner: "fetch"
    },
    %{
      key: "writing-out",
      label: "Writing to a Substack draft",
      direction: "sink",
      profile: "substack",
      kind: "writing",
      thread_key: "path",
      cadence: "on_approval",
      runner: "publish"
    }
  ]

  @prompt_max 4_000

  @doc "The platform's seeded profiles."
  def seeded_profiles, do: @profiles

  @doc "The built-in routes."
  def built_in, do: Enum.map(@built_in, &Map.put(&1, :built_in, true))

  @doc "Whether a key names a built-in route."
  def built_in?(key), do: Enum.any?(@built_in, &(&1.key == key))

  @doc "Whether a key names a seeded profile."
  def seeded_profile?(key), do: Enum.any?(@profiles, &(&1.key == key))

  @doc """
  A route of hers checked against the safe subset (xenia#19): a key of 2
  to 40 lowercase letters, digits or `-`, no built-in's; a source, on
  request; a prompt of at most #{@prompt_max} characters; bound to a
  profile that exists; landing in a kind of `writable` (the kinds she
  writes, from her registry) whose approval does not leave the house.
  `leaves` names the kinds whose approval does. The thread key is the
  route's own namespace, never chosen. `{:ok, descriptor}` in the file's
  own shape, or the refusal naming what was claimed.
  """
  def user_route(attrs, profiles, writable, leaves) when is_map(attrs) do
    a = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    # In order: the first claim refused is the one named.
    checks = [
      {route_key?(a["key"]), Error.new(:xenia_route_invalid, :xenia_routes_user_key)},
      {not built_in?(a["key"]), Error.new(:xenia_route_invalid, :xenia_routes_user_built_in)},
      {(a["direction"] || "source") == "source",
       Error.new(:xenia_route_invalid, :xenia_routes_user_sink)},
      {(a["cadence"] || "on_request") == "on_request",
       Error.new(:xenia_route_invalid, :xenia_routes_user_cadence)},
      {prompt?(a["prompt"]), Error.new(:xenia_route_invalid, :xenia_routes_user_prompt)},
      {a["profile"] in profiles, Error.new(:xenia_route_invalid, :xenia_routes_user_profile)},
      {a["kind"] not in leaves, Error.new(:xenia_route_invalid, :xenia_routes_user_leaves_house)},
      {a["kind"] in writable, Error.new(:xenia_route_invalid, :xenia_routes_user_kind)}
    ]

    case Enum.find(checks, fn {held, _refusal} -> not held end) do
      nil -> {:ok, descriptor(a)}
      {_held, refusal} -> {:error, refusal}
    end
  end

  defp route_key?(key), do: is_binary(key) and Regex.match?(~r/\A[a-z][a-z0-9-]{1,39}\z/, key)

  defp prompt?(p),
    do: is_binary(p) and String.trim(p) != "" and String.length(p) <= @prompt_max

  defp descriptor(a) do
    key = a["key"]

    %{
      "key" => key,
      "label" => text(a["label"]) || key,
      "direction" => "source",
      "prompt" => a["prompt"],
      "profile" => a["profile"],
      "kind" => a["kind"],
      "thread_key" => "#{key}:<n>",
      "cadence" => "on_request"
    }
  end

  @doc "A route of hers as the registry holds one, from its descriptor."
  def from_descriptor(d) do
    %{
      key: d["key"],
      label: d["label"],
      direction: d["direction"],
      prompt: d["prompt"],
      profile: d["profile"],
      kind: d["kind"],
      thread_key: d["thread_key"],
      cadence: d["cadence"],
      runner: "route",
      built_in: false
    }
  end

  @doc """
  A profile the witness makes (xenia#19): a key like a route's, a label,
  exactly one origin (https://host), and whom it is signed in as. A
  seeded profile's key sets its label and sign-in alone; its origin and
  reach are the platform's.
  """
  def profile(attrs) when is_map(attrs) do
    a = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    key = a["key"]

    cond do
      not route_key?(key) ->
        {:error, Error.new(:xenia_profile_invalid, :xenia_routes_profile_key)}

      seeded_profile?(key) ->
        {:ok,
         %{"key" => key, "label" => text(a["label"]), "signed_in_as" => text(a["signed_in_as"])}}

      not origin?(a["origin"]) ->
        {:error, Error.new(:xenia_profile_invalid, :xenia_routes_profile_origin)}

      true ->
        {:ok,
         %{
           "key" => key,
           "label" => text(a["label"]) || key,
           "origin" => a["origin"],
           "signed_in_as" => text(a["signed_in_as"])
         }}
    end
  end

  defp origin?(o),
    do: is_binary(o) and Regex.match?(~r/\Ahttps:\/\/[a-z0-9.-]+(:[0-9]{1,5})?\z/, o)

  defp text(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: String.trim(v))
  defp text(_v), do: nil
end
