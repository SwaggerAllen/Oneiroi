defmodule Oneiroi.Seshat.Palette do
  @moduledoc """
  The theme's derivation and readability checks (seshat#56), ported from
  the client, which owns them: `client/src/next/theme/derive.ts` and
  `color.ts`. Three seeds in (a ground, her colour, his colour), every
  colour token and the checks out, in OKLCH. The server runs the same
  checks so that an unreadable set is refused before it is written or
  filed; `test/fixtures/theme/derive.json`, written by the client's test
  and read by this one's, keeps the two agreeing. A change here is a
  change there first.
  """

  @default %{ground: "#0a0a10", resident: "#d8b4fe", witness: "#7ee7f5"}
  @hex ~r/\A#[0-9a-fA-F]{6}\z/

  @doc "The decided look's seeds, the client's DEFAULT_SEEDS."
  @spec default() :: %{ground: String.t(), resident: String.t(), witness: String.t()}
  def default, do: @default

  @doc "Whether a value is a `#rrggbb` colour."
  @spec hex?(term()) :: boolean()
  def hex?(value) when is_binary(value), do: Regex.match?(@hex, value)
  def hex?(_other), do: false

  @doc "Every token and every check for three seeds, and whether all the checks passed."
  @spec derive(%{ground: String.t(), resident: String.t(), witness: String.t()}) :: %{
          tokens: map(),
          checks: [map()],
          ok: boolean()
        }
  def derive(%{ground: ground, resident: resident, witness: witness}) do
    g = to_oklch(ground)
    tint = min(g.c, 0.02)

    tokens = %{
      ground: ground,
      groundDeep: at(g, max(g.l - 0.03, 0), tint),
      surface: at(g, g.l + 0.06, tint),
      surfaceRaised: at(g, g.l + 0.08, tint),
      border: at(g, g.l + 0.12, tint + 0.005),
      borderStrong: at(g, g.l + 0.17, tint + 0.01),
      text: at(g, 0.94, 0.01),
      textMuted: at(g, 0.66, 0.02),
      textFaint: at(g, 0.52, 0.02),
      resident: accent(resident),
      witness: accent(witness)
    }

    r = to_oklch(resident)
    w = to_oklch(witness)

    checks = [
      check("text on ground", contrast(tokens.text, tokens.ground), 7, "≥ 7:1"),
      check("muted text on ground", contrast(tokens.textMuted, tokens.ground), 4.5, "≥ 4.5:1"),
      check("faint text on surface", contrast(tokens.textFaint, tokens.surface), 3, "≥ 3:1"),
      check("her colour on ground", contrast(resident, tokens.ground), 4.5, "≥ 4.5:1"),
      check("his colour on ground", contrast(witness, tokens.ground), 4.5, "≥ 4.5:1"),
      check("text on his colour", contrast(tokens.witness.on, witness), 4.5, "≥ 4.5:1"),
      check(
        "her colour apart from his",
        max(hue_distance(r.h, w.h) / 60, abs(r.l - w.l) / 0.15),
        1,
        "≥ 60° of hue or 0.15 of lightness"
      )
    ]

    %{tokens: tokens, checks: checks, ok: Enum.all?(checks, & &1.passed)}
  end

  @doc "The checks in words, as she reads them: `text on ground 13.2:1 (needs ≥ 7:1)`."
  @spec report([map()]) :: String.t()
  def report(checks) do
    Enum.map_join(checks, "; ", fn c ->
      value =
        if String.ends_with?(c.needs, ":1"),
          do: "#{c.value}:1",
          else: "#{c.value} of the distance"

      mark = if c.passed, do: "", else: " FAILS"
      "#{c.name} #{value} (needs #{c.needs})#{mark}"
    end)
  end

  defp accent(seed) do
    o = to_oklch(seed)

    %{
      accent: seed,
      on: at(o, 0.24, min(o.c, 0.06)),
      surface: at(o, 0.2, min(o.c * 0.45, 0.04)),
      surfaceStrong: at(o, 0.24, min(o.c * 0.55, 0.05)),
      border: at(o, 0.31, min(o.c * 0.6, 0.06)),
      borderStrong: at(o, 0.38, min(o.c * 0.75, 0.08)),
      text: at(o, 0.87, min(o.c * 0.75, 0.09)),
      glow: with_alpha(seed, 0.35)
    }
  end

  defp at(base, l, c), do: to_hex(%{l: l, c: c, h: base.h})

  defp check(name, value, min, needs),
    do: %{name: name, passed: value >= min, value: js_round(value * 100) / 100, needs: needs}

  # ---- colour (color.ts) ----

  defp to_linear(c) when c <= 0.04045, do: c / 12.92
  defp to_linear(c), do: :math.pow((c + 0.055) / 1.055, 2.4)

  defp to_gamma(c) when c <= 0.0031308, do: 12.92 * c
  defp to_gamma(c), do: 1.055 * :math.pow(c, 1 / 2.4) - 0.055

  defp clamp01(x), do: x |> max(0.0) |> min(1.0)

  # JavaScript's Math.round: half toward positive infinity.
  defp js_round(x), do: trunc(Float.floor(x + 0.5))

  defp rgb("#" <> hex) do
    n = String.to_integer(hex, 16)

    [
      Bitwise.band(Bitwise.bsr(n, 16), 255),
      Bitwise.band(Bitwise.bsr(n, 8), 255),
      Bitwise.band(n, 255)
    ]
    |> Enum.map(&(&1 / 255))
  end

  defp to_oklch(hex) do
    [r, g, b] = hex |> String.downcase() |> rgb() |> Enum.map(&to_linear/1)
    l_ = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m_ = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s_ = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    l = 0.2104542553 * l_ + 0.793617785 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.428592205 * m_ + 0.4505937099 * s_
    bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.808675766 * s_
    h = :math.atan2(bb, a) * 180 / :math.pi()
    %{l: l, c: :math.sqrt(a * a + bb * bb), h: if(h < 0, do: h + 360, else: h)}
  end

  defp to_hex(%{l: l, c: c, h: h}) do
    rad = h * :math.pi() / 180
    a = c * :math.cos(rad)
    b = c * :math.sin(rad)
    l_ = cube(l + 0.3963377774 * a + 0.2158037573 * b)
    m_ = cube(l - 0.1055613458 * a - 0.0638541728 * b)
    s_ = cube(l - 0.0894841775 * a - 1.291485548 * b)
    r = 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_
    g = -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_
    bl = -0.0041960863 * l_ - 0.7034186147 * m_ + 1.707614701 * s_
    "#" <> Enum.map_join([r, g, bl], &byte(to_gamma(clamp01(&1))))
  end

  defp byte(x),
    do:
      (clamp01(x) * 255)
      |> js_round()
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(2, "0")

  defp cube(x), do: x * x * x

  # Math.cbrt, with a Newton step after the power so the root lands
  # where the client's does.
  defp cbrt(x) when x == 0, do: 0.0
  defp cbrt(x) when x < 0, do: -cbrt(-x)

  defp cbrt(x) do
    y = :math.pow(x, 1 / 3)
    y - (y * y * y - x) / (3 * y * y)
  end

  defp luminance(hex) do
    [r, g, b] = hex |> String.downcase() |> rgb() |> Enum.map(&to_linear/1)
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  defp contrast(a, b) do
    [hi, lo] = Enum.sort([luminance(a), luminance(b)], :desc)
    (hi + 0.05) / (lo + 0.05)
  end

  defp hue_distance(a, b) do
    d = :math.fmod(abs(a - b), 360.0)
    if d > 180, do: 360 - d, else: d
  end

  defp with_alpha(hex, alpha) do
    [r, g, b] = hex |> String.downcase() |> rgb() |> Enum.map(&js_round(&1 * 255))
    "rgba(#{r},#{g},#{b},#{alpha})"
  end
end
