defmodule Badge.App.Race.Car do
  @moduledoc """
  The player's car: speed, place across the road, distance driven.

      car = Car.step(Car.new(), dt_ms, %{steer: 0, throttle: true, brake: false}, curve)

  `steer` runs from -1024 (full left) to 1024. `x` is -1024..1024 on the
  tarmac and grass beyond; `curve` is the bend under the car, from `Track`.
  Speeds are units per second.
  """

  @top 1_500
  @grass_top 500
  @accel 600
  @brake 1_500
  @coast 200
  @edge 1_024
  @limit 1_600

  @doc "Top speed on tarmac, in units per second."
  def top_speed, do: @top

  @doc "A car on the start line."
  def new, do: %{x: 0, speed: 0, distance: 0}

  @doc "The car `dt` milliseconds later."
  def step(car, dt, input, curve) do
    speed = car.speed |> pedal(input, dt) |> grass(car.x, dt) |> clamp(0, @top)
    steer = div(div(input.steer * speed, 1024) * 6 * dt, 5_000)
    drift = div(curve * speed * dt * 9, 40_000)

    %{
      car
      | speed: speed,
        x: clamp(car.x + steer - drift, -@limit, @limit),
        distance: car.distance + div(speed * dt, 1_000)
    }
  end

  defp pedal(speed, %{brake: true}, dt), do: speed - div(@brake * dt, 1_000)
  defp pedal(speed, %{throttle: true}, dt), do: speed + div(@accel * dt, 1_000)
  defp pedal(speed, _input, dt), do: speed - div(@coast * dt, 1_000)

  defp grass(speed, x, dt) when (x > @edge or x < -@edge) and speed > @grass_top,
    do: max(speed - div(@brake * dt, 1_000), @grass_top)

  defp grass(speed, _x, _dt), do: speed

  defp clamp(n, low, _high) when n < low, do: low
  defp clamp(n, _low, high) when n > high, do: high
  defp clamp(n, _low, _high), do: n
end
