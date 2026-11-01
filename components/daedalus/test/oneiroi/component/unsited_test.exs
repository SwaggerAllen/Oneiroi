defmodule Oneiroi.Component.UnsitedTest do
  @moduledoc "An error leaving an export carries a site: refused under the suite, warned about otherwise, and the result unchanged."
  # The setting is application-wide, so this module runs alone.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # Its own component rather than another test file's: a module defined
  # in a sibling test file exists only when that file runs in the same
  # pass, so a probe running this file alone found nothing to call.
  defmodule Exporting do
    use Oneiroi.Component, slug: :unsited

    def errors, do: [{:unsited_missing, "no such thing", remedy: "check the id"}]

    defexport fail do
      {:error, __MODULE__.Error.new(:unsited_missing, :unsited_test_fail)}
    end

    defexport fail_bare do
      {:error, :not_found}
    end
  end

  defmodule Exporting.Error do
    @moduledoc false
    use Oneiroi.Error, component: Oneiroi.Component.UnsitedTest.Exporting
  end

  setup do
    previous = Application.get_env(:oneiroi_daedalus, :unsited_errors)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:oneiroi_daedalus, :unsited_errors, previous),
        else: Application.delete_env(:oneiroi_daedalus, :unsited_errors)
    end)
  end

  test "under :raise, an unsited error leaving an export raises, naming the export and the class" do
    Application.put_env(:oneiroi_daedalus, :unsited_errors, :raise)

    error = assert_raise ArgumentError, fn -> Exporting.fail_bare() end
    assert error.message =~ "unsited.fail_bare returned an error with no site (:not_found)"
  end

  test "under :raise, a sited error passes" do
    Application.put_env(:oneiroi_daedalus, :unsited_errors, :raise)
    assert {:error, %{site: :unsited_test_fail}} = Exporting.fail()
  end

  test "under :log, it is a warning and the result is unchanged" do
    Application.put_env(:oneiroi_daedalus, :unsited_errors, :log)

    log = capture_log(fn -> assert {:error, :not_found} = Exporting.fail_bare() end)
    assert log =~ "unsited.fail_bare returned an error with no site"
  end

  test "unset, the substrate does nothing: it ships into platforms that chose no policy" do
    Application.delete_env(:oneiroi_daedalus, :unsited_errors)

    log = capture_log(fn -> assert {:error, :not_found} = Exporting.fail_bare() end)
    assert log == ""
  end
end
