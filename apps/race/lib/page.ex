defmodule Badge.App.Race.Page do
  @moduledoc """
  Racer: three laps of an Out Run style road against seven CPU cars.

  Tilt the badge or hold Left/Right to steer, Space or Up to accelerate,
  Down to brake. Space starts a race from the intro and result screens. The
  best lap and race time are kept in NVS under `race_best`.
  """

  use Badge.Page

  alias Badge.App.Race.Race
  alias Badge.App.Race.Scene
  alias Badge.App.Race.Tilt
  alias Badge.Keyboard
  alias Badge.Nvs
  alias Badge.Pixels

  @frame_ms 50
  @slow_ms 100
  @rewatch_ms 2_000
  @nvs_key :race_best
  @full_lock 25
  @roll_sign -1
  @red_hue 0
  @amber_hue 45
  @green_hue 120

  @impl true
  def title, do: "Racer"

  @impl true
  def icon, do: :triangle

  @impl true
  def init, do: %{race: nil, seen: nil, hills: nil, held: [], roll: 0, zero: 0, tilt: nil, watched: 0}

  @impl true
  def refresh(%{race: %{phase: phase}}) when phase in [:countdown, :racing], do: @frame_ms
  def refresh(_state), do: @slow_ms

  @impl true
  def awake?(%{race: %{phase: phase}}), do: :lists.member(phase, [:countdown, :racing])
  def awake?(_state), do: false

  # Hardware is only touched here and in leave/1, never from a key handler.
  @impl true
  def tick(%{race: nil} = state) do
    Keyboard.watch(self())
    race = Race.new(decode(Nvs.get(@nvs_key)))

    %{state | race: race, seen: race, hills: Scene.hills(), tilt: Tilt.start(self()), watched: now()}
  end

  def tick(state) do
    now = now()
    state = rewatch(state, now)
    race = Race.step(state.race, now, input(state))
    cheer(state.seen, race)
    save(state.seen, race)

    %{state | race: race, seen: race}
  end

  @impl true
  def handle_key({:char, ?\s}, %{race: %{phase: phase}} = state) when phase in [:intro, :finished] do
    {:ok, %{state | race: Race.start(state.race, now()), zero: state.roll}}
  end

  def handle_key(_event, _state), do: :ignore

  @impl true
  def handle_info({:held, labels}, state), do: {:ok, %{state | held: labels}}
  def handle_info({:tilt, roll}, state), do: {:ok, %{state | roll: roll}}
  def handle_info(_message, _state), do: :ignore

  @impl true
  def render(%{race: nil}), do: []
  def render(state), do: Scene.items(state.race, state.hills)

  @impl true
  def leave(%{tilt: nil}), do: :ok

  def leave(state) do
    Tilt.stop(state.tilt)
    Keyboard.unwatch()
    :ok
  end

  @doc "What the held keys and the badge's roll ask of the car."
  def input(state) do
    held = state.held

    %{
      steer: steer(held, state.roll, state.zero),
      throttle: :lists.member(~c"Space", held) or :lists.member(~c"Up", held),
      brake: :lists.member(~c"Down", held)
    }
  end

  @doc "Steering from -1024 (full left) to 1024: roll away from `zero`, plus the arrow keys."
  def steer(held, roll, zero) do
    tilt = clamp(div(@roll_sign * wrap(roll - zero) * 1024, @full_lock))
    clamp(tilt + 1024 * (key(held, ~c"Right") - key(held, ~c"Left")))
  end

  @doc "The best times stored in NVS, `{0, 0}` when there are none."
  def decode(<<lap::32, total::32>>), do: {lap, total}
  def decode(_value), do: {0, 0}

  @doc "The NVS value for a pair of best times."
  def encode({lap, total}), do: <<lap::32, total::32>>

  defp cheer(%{phase: :countdown} = old, %{phase: :countdown} = new) do
    if Race.count(old) != Race.count(new), do: Pixels.flash(@red_hue)
  end

  defp cheer(%{phase: :racing}, %{phase: :finished} = new) do
    Pixels.flash(if Race.record?(new), do: @green_hue, else: @amber_hue)
  end

  defp cheer(%{phase: phase}, %{phase: phase}), do: :ok
  defp cheer(_old, %{phase: :countdown}), do: Pixels.flash(@red_hue)
  defp cheer(_old, %{phase: :racing}), do: Pixels.flash(@green_hue)
  defp cheer(_old, _new), do: :ok

  defp save(%{phase: :racing}, %{phase: :finished} = race) do
    if Race.record?(race), do: put_best(Race.new_best(race))
  end

  defp save(_old, _new), do: :ok

  defp put_best(best) do
    try do
      case Nvs.put(@nvs_key, encode(best)) do
        :ok -> :ok
        error -> :io.format(~c"Racer: best not saved: ~p~n", [error])
      end
    catch
      kind, reason -> :io.format(~c"Racer: best not saved: ~p ~p~n", [kind, reason])
    end
  end

  # Picks up a keyboard server that restarted after the page's first watch.
  defp rewatch(state, now) do
    case now - state.watched >= @rewatch_ms do
      true ->
        Keyboard.watch(self())
        %{state | watched: now}

      false ->
        state
    end
  end

  defp key(held, label) do
    case :lists.member(label, held) do
      true -> 1
      false -> 0
    end
  end

  defp clamp(n), do: max(-1024, min(1024, n))

  defp wrap(degrees) when degrees > 180, do: degrees - 360
  defp wrap(degrees) when degrees < -180, do: degrees + 360
  defp wrap(degrees), do: degrees

  defp now, do: :erlang.monotonic_time(:millisecond)
end
