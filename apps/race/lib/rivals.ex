defmodule Badge.App.Race.Rivals do
  @moduledoc """
  The CPU cars: seven, starting on a two-wide grid ahead of the player.

      rivals = Rivals.step(Rivals.new(), dt_ms)
      Rivals.positions(rivals) #=> [{id, distance, x}]

  `distance` counts every lap driven. They are ghosts: nothing collides.
  """

  alias Badge.App.Race.Track

  @count 7
  @gap 150
  @accel 500
  @decel 1_000
  @curve_cost 100

  @doc "The grid, standing still."
  def new do
    for id <- :lists.seq(1, @count) do
      %{id: id, distance: div(id + 1, 2) * @gap, lane: lane(rem(id, 2)), speed: 0}
    end
  end

  @doc "How many rivals race."
  def count, do: @count

  @doc "Every rival `dt` milliseconds later."
  def step(rivals, dt), do: for(rival <- rivals, do: move(rival, dt))

  @doc "Where each rival is: id, total distance and place across the road."
  def positions(rivals) do
    for rival <- rivals, do: {rival.id, rival.distance, rival.lane + wobble(rival.distance, rival.id)}
  end

  defp move(rival, dt) do
    cap = target(rival.id) - abs(Track.curve_at(rival.distance)) * @curve_cost
    speed = approach(rival.speed, cap, dt)

    %{rival | speed: speed, distance: rival.distance + div(speed * dt, 1_000)}
  end

  # Each rival's top speed, 30 below the one ahead of it on the grid.
  defp target(id), do: 1_500 - 30 * id

  defp lane(0), do: -512
  defp lane(1), do: 512

  defp approach(speed, cap, dt) when speed < cap, do: min(speed + div(@accel * dt, 1_000), cap)
  defp approach(speed, cap, dt), do: max(speed - div(@decel * dt, 1_000), cap)

  # A slow triangle wave across the lane, out of step for each car.
  defp wobble(distance, id) do
    phase = rem(div(distance, 50) + id * 37, 200)
    (abs(phase - 100) - 50) * 4
  end
end
