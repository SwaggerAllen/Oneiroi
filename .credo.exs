# Credo's defaults, strict, with one reviewed disagreement (conventions
# §2: a disagreement is a config change in a reviewed commit, never an
# inline disable).
%{
  configs: [
    %{
      name: "default",
      strict: true,
      checks: %{
        extra: [
          # A module that adopts `Oneiroi.Event` or `Oneiroi.Command` is one
          # `use` line naming its fields and version; a `@moduledoc` on each
          # would restate its name, and the system's `events/0` and the
          # containing module's doc are where they are explained. The names
          # and the other `use`s are credo's own defaults, restated because
          # a params list replaces the default one rather than extending it.
          {Credo.Check.Readability.ModuleDoc,
           ignore_names: [
             ~r/(\.\w+Controller|\.Endpoint|\.\w+Live(\.\w+)?|\.Repo|\.Router|\.\w+Socket|\.\w+View|\.\w+HTML|\.\w+JSON|\.Telemetry|\.Layouts|\.Mailer)$/
           ],
           ignore_modules_using: [
             Credo.Check,
             Ecto.Schema,
             Phoenix.LiveView,
             ~r/\.Web$/,
             Oneiroi.Event,
             Oneiroi.Command
           ]}
        ]
      }
    }
  ]
}
