defmodule Oneiroi.Eunomia.Router do
  @moduledoc "The regression suite's router: `regression-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Eunomia.Suite",
    prefix: "regression-",
    commands: "Oneiroi.Eunomia.Commands",
    dispatching:
      ~w(WriteTest ChangeTest StartRun RecordAnswer FinishRun FailRun GradeAnswer FavouriteAnswer)
end
