defmodule Oneiroi.Proteus.Honcho.Recorded do
  @moduledoc """
  The deployed Honcho as recorded from its source at the pinned commit
  (`test/fixtures/proteus/honcho-server.json`, proteus #9): which routes
  it has, which query each takes, which body fields each model declares
  under which name, which are required, and the keys each answer
  carries. The fakes ask it before they answer: `refusal/1` for a
  request, which they answer with the 422 the server sends, and
  `answer_problem/2` for what a Honcho on the loopback says back.

  Stricter than the server where the fixture says so (its `fakes`): a
  field's own name where the server reads an alias, an undeclared body
  field or query parameter, a filter key outside the public mapping.
  The server takes or drops each of those; a client that sends one
  believes it set something it did not.

  Read only by the fakes, so only in the suite: the file is a test
  fixture, found beside this source rather than by the working
  directory, which an async test may move.
  """

  @path Path.expand("../../../../test/fixtures/proteus/honcho-server.json", __DIR__)
  @key {__MODULE__, :schema}

  @typedoc "A request as the server reads it (`Honcho.Wire.as_read/1`)."
  @type read :: %{method: String.t(), path: [String.t()], params: map(), body: term()}

  @doc "The upstream commit the record was read at."
  def commit, do: schema()["provenance"]["commit"]

  @doc """
  Why the server (or the stricter fake) refuses a request, naming the
  route and the field, never a value: a value can be a tenant's words.
  Nil when it would be answered.
  """
  @spec refusal(read()) :: String.t() | nil
  def refusal(%{method: method, path: path, params: params, body: body}) do
    case route(method, path) do
      nil ->
        "#{method} /v3/#{Enum.join(path, "/")}: no such route"

      {name, spec} ->
        prefix(name, query_problem(spec, params) || body_problem(spec, body))
    end
  end

  @doc "What is wrong with an answer to `model` (`Page[Peer]`, `list[Message]`, `Workspace`): nil when it is the recorded shape."
  @spec answer_problem(String.t(), term()) :: String.t() | nil
  def answer_problem(model, body) do
    case Regex.run(~r/\A(Page|list)\[(\w+)\]\z/, model) do
      [_, "Page", item] ->
        keys_problem("Page", body) || items_problem(item, body["items"])

      [_, "list", item] ->
        items_problem(item, body)

      nil ->
        keys_problem(model, body) || nested_problem(model, body)
    end
  end

  # ---- routes ----

  defp route(method, path) do
    schema()["routes"]
    |> Enum.filter(fn {name, _} -> matches?(name, method, path) end)
    # A literal segment beats a parameter: `peers/list` is not a peer.
    |> Enum.max_by(fn {name, _} -> literals(name) end, fn -> nil end)
  end

  defp matches?(name, method, path) do
    [verb, "/v3" <> template] = String.split(name, " ")
    segments = String.split(template, "/", trim: true)

    verb == method and length(segments) == length(path) and
      Enum.all?(Enum.zip(segments, path), fn {s, p} -> param?(s) or s == p end)
  end

  defp literals(name),
    do: name |> String.split("/") |> Enum.reject(&param?/1) |> length()

  defp param?(segment), do: String.starts_with?(segment, "{")

  defp prefix(_name, nil), do: nil
  defp prefix(name, problem), do: name <> ": " <> problem

  # ---- the query ----

  defp query_problem(spec, params) do
    declared = declared_query(spec["query"])

    Enum.find_value(params, fn {key, value} ->
      case Map.fetch(declared, key) do
        :error -> "query `#{key}` is not a parameter of this route"
        {:ok, field} -> scalar_problem("query `#{key}`", field, value)
      end
    end)
  end

  defp declared_query(query) do
    {ref, own} = Map.pop(query, "$ref")
    shared = if ref, do: schema()["query"][ref]["fields"], else: %{}
    Map.merge(shared, own)
  end

  # The query arrives as text and the server casts it.
  defp scalar_problem(at, %{"type" => "integer"} = field, value) do
    case Integer.parse(value) do
      {n, ""} -> bounds_problem(at, field, n)
      _other -> "#{at} is not an integer"
    end
  end

  defp scalar_problem(at, %{"type" => "number"} = field, value) do
    case Float.parse(value) do
      {n, ""} -> bounds_problem(at, field, n)
      _other -> "#{at} is not a number"
    end
  end

  defp scalar_problem(at, %{"type" => "boolean"}, value),
    do: if(value in ["true", "false"], do: nil, else: "#{at} is not a boolean")

  defp scalar_problem(at, %{"type" => "datetime"}, value),
    do: if(datetime?(value), do: nil, else: "#{at} is not a datetime")

  defp scalar_problem(_at, %{"type" => "string"}, _value), do: nil

  defp bounds_problem(at, field, n) do
    cond do
      is_number(field["minimum"]) and n < field["minimum"] -> "#{at} is under #{field["minimum"]}"
      is_number(field["maximum"]) and n > field["maximum"] -> "#{at} is over #{field["maximum"]}"
      true -> nil
    end
  end

  # ---- the body ----

  defp body_problem(%{"body" => nil}, nil), do: nil
  defp body_problem(%{"body" => nil}, _body), do: "a body this route does not read"
  defp body_problem(%{"body_optional" => true}, nil), do: nil
  defp body_problem(%{"body" => model}, nil), do: "the body (#{model}) is missing"
  defp body_problem(%{"body" => model}, body), do: model_problem(model, body, "body")

  defp model_problem(model, body, at) when is_map(body) do
    fields = schema()["models"][model]["fields"]

    unknown_problem(fields, body, at) || missing_problem(fields, body, at) ||
      fields_problem(fields, body, at)
  end

  defp model_problem(model, _body, at), do: "#{at} is not an object (#{model})"

  defp unknown_problem(fields, body, at) do
    Enum.find_value(Map.keys(body), fn key ->
      cond do
        Map.has_key?(fields, key) -> nil
        wire = own_name_of(fields, key) -> own_name(at, key, wire, fields[wire]["by_name"])
        true -> "#{at}.#{key} is not a field the server declares"
      end
    end)
  end

  defp own_name_of(fields, key),
    do: Enum.find_value(fields, fn {wire, f} -> if f["field"] == key, do: wire end)

  defp own_name(at, key, wire, true),
    do: "#{at}.#{key} is `#{wire}`'s own name: the server takes it, the fake takes only `#{wire}`"

  defp own_name(at, key, wire, _not_by_name),
    do: "#{at}.#{key} is `#{wire}`'s own name, which the server does not take: it reads `#{wire}`"

  defp missing_problem(fields, body, at) do
    Enum.find_value(fields, fn {wire, f} ->
      if f["required"] == true and not Map.has_key?(body, wire), do: "#{at}.#{wire} is missing"
    end)
  end

  defp fields_problem(fields, body, at),
    do:
      Enum.find_value(body, fn {key, value} ->
        value_problem("#{at}.#{key}", fields[key], value)
      end)

  defp value_problem(at, field, nil),
    do: if(field["nullable"] == true, do: nil, else: "#{at} is null")

  defp value_problem(at, %{"model" => model}, value), do: model_problem(model, value, at)

  defp value_problem(at, %{"type" => type} = field, value),
    do: typed_problem(at, type, field, value)

  defp typed_problem(at, "string", field, value) when is_binary(value),
    do:
      length_problem(at, field, value |> String.codepoints() |> length()) ||
        string_problem(at, field, value)

  defp typed_problem(at, "datetime", _field, value) when is_binary(value),
    do: if(datetime?(value), do: nil, else: "#{at} is not a datetime")

  defp typed_problem(at, "integer", field, value) when is_integer(value),
    do: bounds_problem(at, field, value)

  defp typed_problem(at, "number", field, value) when is_number(value),
    do: bounds_problem(at, field, value)

  defp typed_problem(_at, "boolean", _field, value) when is_boolean(value), do: nil

  defp typed_problem(at, "array", field, value) when is_list(value) do
    length_problem(at, field, length(value)) ||
      value
      |> Enum.with_index()
      |> Enum.find_value(fn {item, i} -> value_problem("#{at}[#{i}]", field["items"], item) end)
  end

  defp typed_problem(at, "object", field, value) when is_map(value),
    do: keys_allowed_problem(at, field, value) || values_problem(at, field, value)

  defp typed_problem(at, type, _field, _value), do: "#{at} is not #{article(type)}"

  defp string_problem(at, field, value) do
    cond do
      is_binary(field["pattern"]) and not Regex.match?(Regex.compile!(field["pattern"]), value) ->
        "#{at} does not match #{field["pattern"]}"

      is_list(field["enum"]) and value not in field["enum"] ->
        "#{at} is not one of #{Enum.join(field["enum"], ", ")}"

      true ->
        nil
    end
  end

  defp length_problem(at, field, n) do
    cond do
      is_integer(field["min_length"]) and n < field["min_length"] ->
        "#{at} is shorter than #{field["min_length"]}"

      is_integer(field["max_length"]) and n > field["max_length"] ->
        "#{at} is longer than #{field["max_length"]}"

      true ->
        nil
    end
  end

  defp keys_allowed_problem(at, %{"keys" => keys}, value) when is_list(keys) do
    Enum.find_value(Map.keys(value), fn key ->
      if key in keys, do: nil, else: "#{at}.#{key} is not a key this list filters on"
    end)
  end

  defp keys_allowed_problem(_at, _field, _value), do: nil

  defp values_problem(at, %{"values" => model}, value),
    do: Enum.find_value(value, fn {key, v} -> model_problem(model, v, "#{at}.#{key}") end)

  defp values_problem(_at, _field, _value), do: nil

  defp article("integer"), do: "an integer"
  defp article("object"), do: "an object"
  defp article("array"), do: "an array"
  defp article(type), do: "a " <> type

  defp datetime?(value) do
    match?({:ok, _, _}, DateTime.from_iso8601(value)) or
      match?({:ok, _}, NaiveDateTime.from_iso8601(value))
  end

  # ---- answers ----

  defp keys_problem(model, body) when is_map(body) do
    want = schema()["responses"][model]["keys"] |> Enum.sort()
    have = body |> Map.keys() |> Enum.sort()

    if have == want,
      do: nil,
      else: "#{model} answered #{inspect(have)}, recorded #{inspect(want)}"
  end

  defp keys_problem(model, _body), do: "#{model} answered something other than an object"

  defp items_problem(item, items) when is_list(items),
    do: Enum.find_value(items, &answer_problem(item, &1))

  defp items_problem(item, _items), do: "a list of #{item} answered something other than a list"

  defp nested_problem(model, body) do
    nested = schema()["responses"][model]["nested"] || %{}

    Enum.find_value(nested, fn {key, inner} ->
      if body[key] == nil, do: nil, else: answer_problem(inner, body[key])
    end)
  end

  # ---- the record ----

  # The path is this module's constant, beside its source; nothing a
  # request carries reaches it.
  # sobelow_skip ["Traversal.FileModule"]
  defp schema do
    case :persistent_term.get(@key, nil) do
      nil ->
        schema = @path |> File.read!() |> Jason.decode!()
        :persistent_term.put(@key, schema)
        schema

      schema ->
        schema
    end
  end
end
