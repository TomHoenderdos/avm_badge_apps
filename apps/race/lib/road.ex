defmodule Badge.App.Race.Road do
  @moduledoc """
  Projects the road ahead into horizontal bands, nearest first.

      Road.bands(z, x) #=> [{y, height, centre, half, segment}, ...]

  `z` is the distance driven and `x` the car's place across the road, -1024
  and 1024 being the edges. `y` and `height` are screen rows, `centre` and
  `half` the road's middle and half-width in pixels, `segment` the track
  segment the band shows.

  Depths count eighths of a segment from the camera, which sits behind the
  car; `y/1` and `half/1` project one, for placing things on the road.
  """

  alias Badge.App.Race.Track

  @horizon 100
  @bottom 240
  @middle 160
  @ahead 20
  @steps 8
  @camera 10
  @y_scale 1_250
  @half_scale 1_300
  @max_depth @ahead * @steps + @camera

  @ys (for d <- 0..@max_depth do
         if d == 0, do: @bottom, else: min(@horizon + div(@y_scale, d), @bottom)
       end)
      |> List.to_tuple()

  @halves (for d <- 0..@max_depth do
             if d == 0, do: @half_scale, else: div(@half_scale, d)
           end)
          |> List.to_tuple()

  @doc "Segments drawn ahead of the car."
  def ahead, do: @ahead

  @doc "Screen row of the road at `depth`."
  def y(depth), do: elem(@ys, depth)

  @doc "Road half-width in pixels at `depth`."
  def half(depth), do: elem(@halves, depth)

  @doc "Depth of a point `delta` units ahead of the car, `delta` below `ahead() * 100`."
  def depth(delta), do: div(delta * @steps, Track.segment_length()) + @camera

  @doc "The bands to draw for a car at distance `z` and lateral position `x`."
  def bands(z, x) do
    segment = div(z, Track.segment_length())
    step = div(rem(z, Track.segment_length()) * @steps, Track.segment_length())

    walk(0, segment, step, x, 0, 0, [])
  end

  defp walk(@ahead, _segment, _step, _x, _dx, _ddx, acc), do: :lists.reverse(acc)

  defp walk(k, segment, step, x, dx, ddx, acc) do
    index = rem(segment + k, Track.segments())
    ddx = ddx + Track.curve(index)
    dx = dx + ddx
    near = k * @steps - step + @camera
    top = y(near + @steps)
    bottom = bottom(k, near)
    half = half(near)
    centre = @middle + div(dx, 4) - div(x * half, 1024)

    acc =
      case bottom > top do
        true -> [{top, bottom - top, centre, half, index} | acc]
        false -> acc
      end

    walk(k + 1, segment, step, x, dx, ddx, acc)
  end

  # The nearest band reaches the bottom row, whatever the camera's step.
  defp bottom(0, _near), do: @bottom
  defp bottom(_k, near), do: y(near)
end
