defmodule Oneiroi.ErrorTest do
  use ExUnit.Case, async: true

  defmodule Engine do
    use Oneiroi.Component, slug: :engine

    def errors do
      [
        {:engine_grammar_invalid, "the bundle's grammar does not parse",
         remedy: "run mix oneiroi.records.check", runbook: "ops/grammar"},
        {:engine_not_found, "no bundle with that id", remedy: "check the id"}
      ]
    end
  end

  defmodule Engine.Error do
    @moduledoc false
    use Oneiroi.Error, component: Oneiroi.ErrorTest.Engine
  end

  test "the struct speaks for its component's declaration" do
    assert Engine.Error.component() == Engine
    assert Engine.Error.kinds() == [:engine_grammar_invalid, :engine_not_found]
  end

  test "meaning and remedy come from the registry, never from the call site" do
    error = Engine.Error.new(:engine_grammar_invalid, :engine_test_meaning, bundle: "acme")

    assert %Engine.Error{
             kind: :engine_grammar_invalid,
             site: :engine_test_meaning,
             cause: nil,
             meaning: "the bundle's grammar does not parse",
             remedy: "run mix oneiroi.records.check",
             runbook: "ops/grammar",
             admin: nil,
             details: [bundle: "acme"]
           } = error
  end

  test "conventions §8's spelling is what a caller matches on" do
    assert {:error, %Engine.Error{kind: :engine_not_found}} =
             {:error, Engine.Error.new(:engine_not_found, :engine_test_spelling)}
  end

  test "an undeclared kind has nowhere to be constructed from" do
    error =
      assert_raise ArgumentError, fn ->
        Engine.Error.new(:engine_invented, :engine_test_invented)
      end

    assert error.message =~ ":engine_invented is not a kind"
    assert error.message =~ "declared: [:engine_grammar_invalid, :engine_not_found]"
  end

  test "the struct enforces the two fields a failure cannot be without" do
    assert_raise ArgumentError, fn -> struct!(Engine.Error, meaning: "no kind") end
    assert_raise ArgumentError, fn -> struct!(Engine.Error, kind: :engine_not_found) end
  end

  describe "the site" do
    test "is an atom carrying the component's slug" do
      for bad <- [nil, true, "engine_string", :other_prefix, :engine] do
        error =
          assert_raise ArgumentError, fn -> Engine.Error.new(:engine_not_found, bad) end

        assert error.message =~ "is not a site for"
        assert error.message =~ "engine_"
      end
    end

    test "a failure from elsewhere keeps its class and never its message" do
      secret = "https://x-access-token:github_pat_TESTONLY@github.com/a/b.git"
      cause = %ErlangError{original: :enoent, reason: secret}
      error = Engine.Error.caught(:engine_not_found, :engine_test_caught, cause, id: 7)

      assert error.cause == ErlangError
      assert error.details == [id: 7]
      refute inspect(error) =~ "github_pat"
    end

    test "describe: the class of anything, and the site of one of ours" do
      inner = Engine.Error.new(:engine_not_found, :engine_test_inner)

      assert Oneiroi.Error.describe(%RuntimeError{message: "secret"}) == RuntimeError
      assert Oneiroi.Error.describe(:timeout) == :timeout
      assert Oneiroi.Error.describe({:shutdown, "secret"}) == :shutdown
      assert Oneiroi.Error.describe(%URI{host: "secret"}) == URI
      assert Oneiroi.Error.describe("a secret string") == :term
      assert Oneiroi.Error.describe(inner) == :engine_test_inner
    end

    test "sited? and the log metadata" do
      error = Engine.Error.caught(:engine_not_found, :engine_test_meta, :timeout)

      assert Oneiroi.Error.sited?(error)
      refute Oneiroi.Error.sited?(:not_found)
      refute Oneiroi.Error.sited?(%{kind: :x, site: :y})

      assert Oneiroi.Error.metadata(error) ==
               [
                 error_kind: :engine_not_found,
                 error_site: :engine_test_meta,
                 error_cause: :timeout
               ]
    end
  end

  test "the registry is read at construction, never at compile time" do
    # The property this buys: `Engine` may construct `%Engine.Error{}` in
    # its own body without the two modules waiting on each other, which
    # is a compile cycle and a hard gate (conventions §2).
    assert Oneiroi.Error.kinds(Engine) == Engine.Error.kinds()

    assert Oneiroi.Error.fields() ==
             [:kind, :site, :meaning, :remedy, :runbook, :admin, :details, :cause]
  end
end
