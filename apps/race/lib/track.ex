defmodule Badge.App.Race.Track do
  @moduledoc """
  The circuit: one curve value per 100-unit segment, 600 segments a lap.

      Track.curve_at(z) #=> -4..4, positive bends right

  Written as sections below and expanded on the host at compile time.
  """

  @segment 100
  @lap_segments 600

  @sections [
    {:straight, 50},
    {:curve, 40, 2},
    {:straight, 30},
    {:curve, 60, -3},
    {:straight, 40},
    {:curve, 30, 4},
    {:curve, 30, -4},
    {:straight, 60},
    {:curve, 80, 1},
    {:straight, 30},
    {:curve, 50, -2},
    {:straight, 40},
    {:curve, 40, 3},
    {:straight, 20}
  ]

  @curves @sections
          |> Enum.flat_map(fn
            {:straight, n} -> List.duplicate(0, n)
            {:curve, n, strength} -> List.duplicate(strength, n)
          end)
          |> List.to_tuple()

  if tuple_size(@curves) != @lap_segments,
    do: raise("track sections add up to #{tuple_size(@curves)} segments, not #{@lap_segments}")

  @doc "The circuit's name, for the intro screen."
  def name, do: "Goatmire Ring"

  @doc "Units per segment."
  def segment_length, do: @segment

  @doc "Segments per lap."
  def segments, do: @lap_segments

  @doc "Units per lap."
  def lap_length, do: @segment * @lap_segments

  @doc "The curve of segment `index`, 0 to 599."
  def curve(index), do: elem(@curves, index)

  @doc "The curve under distance `z`, any number of laps in."
  def curve_at(z), do: elem(@curves, rem(div(z, @segment), @lap_segments))
end
