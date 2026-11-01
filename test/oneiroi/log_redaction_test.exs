defmodule Oneiroi.LogRedactionTest do
  @moduledoc "The handler every environment logs through carries the redacting formatter, prod's JSON one included."
  use ExUnit.Case, async: true

  # Production is the environment that leaked (2026-11-01), and its
  # formatter is configured in a file this suite never loads, so the
  # prod config is read here and its formatter run on a real line.

  @root Path.expand("../..", __DIR__)
  @token "github_pat_11TESTONLY0abc_DEF"

  defp event,
    do: %{
      level: :error,
      msg: {:string, "clone https://x-access-token:#{@token}@github.com/a/b.git"},
      meta: %{time: System.os_time(:microsecond)}
    }

  test "the handler running this suite" do
    {:ok, %{formatter: {module, config}}} = :logger.get_handler_config(:default)
    assert module == Oneiroi.Apsu.LogRedacting
    refute module.format(event(), config) =~ @token
  end

  for env <- ["prod", "dev"] do
    test "the #{env} config" do
      config =
        Config.Reader.read!(Path.join(@root, "config/#{unquote(env)}.exs"),
          env: :"#{unquote(env)}"
        )

      {module, inner} = config[:logger][:default_handler][:formatter]
      assert module == Oneiroi.Apsu.LogRedacting

      line = module.format(event(), inner)
      assert line =~ "github.com/a/b.git"
      refute line =~ @token
    end
  end
end
