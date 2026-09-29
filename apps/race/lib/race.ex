defmodule Badge.App.Race.Race do
  @moduledoc """
  One race: intro, countdown, three laps, result.

      race = Race.new({best_lap_ms, best_total_ms})
      race = Race.start(race, now)
      race = Race.step(race, now, %{steer: 0, throttle: true, brake: false})

  Pure: the caller passes the clock and the input. A best of 0 means none yet.
  """

  alias Badge.App.Race.Car
  alias Badge.App.Race.Rivals
  alias Badge.App.Race.Track

  @laps 3
  @count_ms 3_000
  @max_step_ms 200

  @doc "Laps in a race."
  def laps, do: @laps

  @doc "Cars in a race, the player's included."
  def cars, do: Rivals.count() + 1

  @doc "A race on its intro screen."
  def new(best) do
    %{
      phase: :intro,
      best: best,
      now: 0,
      since: 0,
      lap: 1,
      lap_start: 0,
      lap_times: [],
      total: 0,
      heading: 0,
      car: Car.new(),
      rivals: Rivals.new()
    }
  end

  @doc "A fresh race counting down from `now`, keeping any record just set."
  def start(%{phase: :finished} = race, now), do: start(%{race | phase: :intro, best: new_best(race)}, now)
  def start(race, now), do: %{new(race.best) | phase: :countdown, since: now, now: now}

  @doc "The race at `now`: the countdown runs, the cars move, laps are counted."
  def step(%{phase: :countdown} = race, now, _input) do
    go = race.since + @count_ms

    case now >= go do
      true -> %{race | phase: :racing, since: go, lap_start: go, now: now}
      false -> %{race | now: now}
    end
  end

  def step(%{phase: :racing} = race, now, input) do
    dt = min(now - race.now, @max_step_ms)
    curve = Track.curve_at(race.car.distance)
    car = Car.step(race.car, dt, input, curve)

    race = %{
      race
      | now: now,
        car: car,
        rivals: Rivals.step(race.rivals, dt),
        heading: race.heading + div(curve * car.speed * dt, 100_000)
    }

    lap(race, div(car.distance, Track.lap_length()) + 1)
  end

  def step(race, _now, _input), do: race

  @doc "The countdown's number, 3 to 1."
  def count(race), do: 3 - div(race.now - race.since, 1_000)

  @doc "Race time in ms: running while racing, frozen once finished."
  def elapsed(%{phase: :racing} = race), do: race.now - race.since
  def elapsed(%{phase: :finished} = race), do: race.total
  def elapsed(_race), do: 0

  @doc "The player's place, 1 being first."
  def place(race) do
    ahead = for {_id, distance, _x} <- Rivals.positions(race.rivals), distance > race.car.distance, do: distance
    length(ahead) + 1
  end

  @doc "The fastest lap of this race, 0 before the first."
  def best_lap(%{lap_times: []}), do: 0
  def best_lap(race), do: :lists.min(race.lap_times)

  @doc "The best lap and total after this race, keeping whichever old one it did not beat."
  def new_best(%{best: {lap, total}} = race), do: {better(best_lap(race), lap), better(race.total, total)}

  @doc "Whether a finished race beat the best lap or the best total."
  def record?(%{phase: :finished} = race), do: new_best(race) != race.best
  def record?(_race), do: false

  defp lap(%{lap: lap} = race, lap), do: race

  defp lap(race, next) do
    race = %{race | lap_times: race.lap_times ++ [race.now - race.lap_start], lap_start: race.now}

    case next > @laps do
      true -> %{race | phase: :finished, total: race.now - race.since}
      false -> %{race | lap: next}
    end
  end

  defp better(0, old), do: old
  defp better(new, 0), do: new
  defp better(new, old), do: min(new, old)
end
