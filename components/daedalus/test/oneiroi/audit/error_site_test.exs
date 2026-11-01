defmodule Oneiroi.Audit.ErrorSiteTest do
  @moduledoc "The error_site check: every error built or caught names a unique, prefixed site, and patterns are not errors."
  use ExUnit.Case, async: true

  alias Oneiroi.Audit.Checks.ErrorSite

  setup do
    dir = Path.join(System.tmp_dir!(), "oneiroi-error-site-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir, scope: Path.join(dir, "*.ex")}
  end

  defp write(dir, name \\ "a.ex", source), do: File.write!(Path.join(dir, name), source)

  defp lines(problems) do
    for problem <- problems,
        [_, line] <- [Regex.run(~r/\.ex:(\d+):/, problem)],
        do: String.to_integer(line)
  end

  test "a sited error is clean however the module is spelled", ctx do
    write(ctx.dir, """
    defmodule A do
      alias Oneiroi.SimaQian.Error
      alias Oneiroi.Gaia.Error, as: IdentityError
      alias Oneiroi.Kumbukumbu.{Error, Store}

      def a, do: {:error, Error.new(:kumbukumbu_x, :kumbukumbu_a_failed)}
      def b, do: {:error, IdentityError.new(:gaia_x, :gaia_b_failed, key: 1)}
      def c(e), do: {:error, Oneiroi.Seshat.Error.caught(:seshat_x, :seshat_c_failed, e)}
      def d(conn), do: problem(conn, 422, :url_required, :web_d_url_required, "url is required")
    end
    """)

    assert ErrorSite.run(ctx.scope) == []
  end

  test "a site that is missing, not literal, wrongly prefixed or named twice", ctx do
    write(ctx.dir, """
    defmodule A do
      alias Oneiroi.SimaQian.Error

      def a, do: Error.new(:sima_qian_x)
      def b(site), do: Error.new(:sima_qian_x, site)
      def c, do: Error.new(:sima_qian_x, :gaia_c_failed)
      def d, do: Error.new(:sima_qian_x, :sima_qian_twice)
      def e, do: Error.new(:sima_qian_x, :sima_qian_twice, n: 1)
      def f(conn), do: problem(conn, 422, :k, :sima_qian_f, "edge sites are web_")
    end
    """)

    problems = ErrorSite.run(ctx.scope)
    assert lines(problems) |> Enum.sort() == [4, 5, 6, 7, 8, 9]
    assert Enum.any?(problems, &(&1 =~ ":6: site :gaia_c_failed does not start with sima_qian_"))
    assert Enum.any?(problems, &(&1 =~ ":7: site :sima_qian_twice is named at 2 lines"))
  end

  test "a site is unique across files, not only within one", ctx do
    write(ctx.dir, "a.ex", """
    defmodule A do
      def a, do: Oneiroi.Gaia.Error.new(:gaia_x, :gaia_shared)
    end
    """)

    write(ctx.dir, "b.ex", """
    defmodule B do
      def b, do: Oneiroi.Gaia.Error.new(:gaia_x, :gaia_shared)
    end
    """)

    assert length(ErrorSite.run(ctx.scope)) == 2
  end

  test "a bare error built in place, of every shape", ctx do
    write(ctx.dir, """
    defmodule A do
      def a, do: {:error, :no_such_session}
      def b, do: {:error, "git is not installed"}
      def c(x), do: {:error, "bad \#{x}"}
      def d(r), do: {:error, {:git, r}}
      def e, do: {:error, %Oneiroi.Gaia.Error{kind: :gaia_x, site: :gaia_e}}
      def f(r), do: {:halt, {:error, :nested}}
    end
    """)

    assert lines(ErrorSite.run(ctx.scope)) |> Enum.sort() == [2, 3, 4, 5, 6, 7]
  end

  test "patterns, passthroughs, keyword pairs, map keys and specs are not errors", ctx do
    write(ctx.dir, """
    defmodule A do
      @spec a(term()) :: {:error, :not_found} | :ok
      def a({:error, :given}), do: :ok
      def b(x) do
        case x do
          {:error, :no_such_session} -> :absent
          {:error, reason} -> {:error, reason}
        end
      end
      def c(x), do: match?({:error, :timeout}, x)
      def d(x) do
        {:error, :bound} = x
        with {:error, :w} <- x, do: :ok
      end
      def e, do: [error: "a keyword", other: 1]
      def f, do: %{error: "a map key"}
      def g, do: quote(do: {:error, :generated})
    end
    """)

    assert ErrorSite.run(ctx.scope) == []
  end

  test "a rescue or catch that names no site, and the ways out", ctx do
    write(ctx.dir, """
    defmodule A do
      alias Oneiroi.Nisaba.Error

      def a do
        :ok
      rescue
        _e -> :swallowed
      end

      def b(f) do
        try do
          f.()
        rescue
          e in ArgumentError -> {:error, Error.caught(:nisaba_x, :nisaba_b_rescued, e)}
        catch
          :exit, _ -> :swallowed_too
        end
      end

      def c(f) do
        try do
          f.()
        rescue
          e -> reraise e, __STACKTRACE__
        catch
          kind, value -> :erlang.raise(kind, value, __STACKTRACE__)
        end
      end
    end
    """)

    assert lines(ErrorSite.run(ctx.scope)) |> Enum.sort() == [7, 16]
  end

  test "the escape covers its line and is reported when idle", ctx do
    write(ctx.dir, """
    defmodule A do
      # oneiroi:allow error_site: Ecto.Type's cast/1 contract is a bare tuple
      def cast(_), do: {:error, :not_a_slug}
      # oneiroi:allow error_site
      def fine, do: :ok
    end
    """)

    problems = ErrorSite.run(ctx.scope)
    assert length(problems) == 1
    assert hd(problems) =~ ":4: oneiroi:allow error_site excuses nothing"
  end
end
