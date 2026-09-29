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

  @segment Track.segment_length()
  @segments Track.segments()

  @doc "Segments drawn ahead of the car."
  def ahead, do: @ahead

  @doc "Screen row of the road at `depth`."
  def y(0), do: @bottom
  def y(depth), do: min(@horizon + div(@y_scale, depth), @bottom)

  @doc "Road half-width in pixels at `depth`."
  def half(0), do: @half_scale
  def half(depth), do: div(@half_scale, depth)

  @doc "Depth of a point `delta` units ahead of the car, `delta` below `ahead() * 100`."
  def depth(delta), do: div(delta * @steps, @segment) + @camera

  @doc "The bands to draw for a car at distance `z` and lateral position `x`."
  def bands(z, x) do
    segment = div(z, @segment)
    step = div(rem(z, @segment) * @steps, @segment)

    walk(0, segment, step, x, 0, 0, [])
  end

  defp walk(@ahead, _segment, _step, _x, _dx, _ddx, acc), do: :lists.reverse(acc)

  defp walk(k, segment, step, x, dx, ddx, acc) do
    index = rem(segment + k, @segments)
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
