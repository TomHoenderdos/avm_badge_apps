defmodule Badge.App.Race.Scene do
  @moduledoc """
  Draws a race as AtomGL display items: text first, sky last.

      hills = Scene.hills()        # once, on entry
      Scene.items(race, hills)     # every frame
  """

  alias Badge.App.Race.Car
  alias Badge.App.Race.Race
  alias Badge.App.Race.Rivals
  alias Badge.App.Race.Road
  alias Badge.App.Race.Track
  alias Badge.Theme

  @top Theme.content_top()
  @width 320
  @char_w 8
  @hud_y @top + 2
  @bar_y @top + 20
  @bar_w 80
  @banner_y 60
  @prompt_y 150

  @sky 0x3070C0
  @sky_pixel <<0x30, 0x70, 0xC0, 255>>
  @hill_pixel <<0x2A, 0x6A, 0x3A, 255>>
  @road 0x606068
  @line 0xFFFFFF
  @player 0xE03030
  @player_roof 0xA02020
  @rival_colours {0x3278E6, 0xF0C828, 0xF0F0F0, 0xC83CC8, 0x28C8C8, 0xF08220, 0x78E650}
  @text 0xFFFFFF
  @panel 0x000000
  @speed 0xF0C040

  @hills_period 160
  @hills_w 2 * @hills_period
  @hills_h 24
  @hills_y 84

  # Each row of the silhouette as {:sky | :hill, count} runs, worked out on the host.
  @hill_runs (for y <- 0..(@hills_h - 1) do
                heights =
                  for x <- 0..(@hills_period - 1) do
                    a = 2 * :math.pi() * x / @hills_period
                    trunc(10 + 6 * :math.sin(a) + 4 * :math.sin(3 * a + 1))
                  end

                (heights ++ heights)
                |> Enum.map(&if(y >= @hills_h - &1, do: :hill, else: :sky))
                |> Enum.chunk_by(& &1)
                |> Enum.map(&{hd(&1), length(&1)})
              end)

  @doc "The hill silhouette on the horizon, two periods wide so any crop wraps."
  def hills do
    rows = for runs <- @hill_runs, {kind, count} <- runs, do: :binary.copy(pixel(kind), count)
    {:rgba8888, @hills_w, @hills_h, :erlang.iolist_to_binary(rows)}
  end

  @doc false
  def hill_runs, do: @hill_runs

  @doc "Every item for one frame of `race`."
  def items(race, hills) do
    bands = Road.bands(race.car.distance, race.car.x)

    overlay(race) ++
      hud(race) ++ player() ++ rivals(race, bands) ++ :lists.flatmap(&band/1, bands) ++ [horizon(race, hills), sky()]
  end

  @doc "A time as `m:ss.t`."
  def clock(ms) do
    seconds = div(ms, 1_000)
    int(div(seconds, 60)) <> ":" <> pad(rem(seconds, 60)) <> "." <> int(div(rem(ms, 1_000), 100))
  end

  defp pixel(:hill), do: @hill_pixel
  defp pixel(:sky), do: @sky_pixel

  defp overlay(%{phase: :intro, best: {best_lap, _total}}) do
    [
      centred(Track.name(), @banner_y),
      centred(best_text(best_lap), @banner_y + 20),
      centred("Space to start", @prompt_y)
    ]
  end

  defp overlay(%{phase: :countdown} = race), do: [centred(int(Race.count(race)), @banner_y)]

  defp overlay(%{phase: :racing} = race) do
    cond do
      race.now - race.since < 1_000 -> [centred("GO!", @banner_y)]
      race.lap == Race.laps() and race.now - race.lap_start < 2_000 -> [centred("FINAL LAP", @banner_y)]
      true -> []
    end
  end

  defp overlay(%{phase: :finished} = race) do
    record =
      case Race.record?(race) do
        true -> [centred("New record!", @banner_y + 60)]
        false -> []
      end

    [
      centred("Finished P" <> int(Race.place(race)) <> "/" <> int(Race.cars()), @banner_y),
      centred("Time " <> clock(race.total), @banner_y + 20),
      centred("Best lap " <> clock(Race.best_lap(race)), @banner_y + 40)
    ] ++ record ++ [centred("Space to race again", @prompt_y)]
  end

  defp best_text(0), do: "No best lap yet"
  defp best_text(ms), do: "Best lap " <> clock(ms)

  defp hud(%{phase: :intro}), do: []

  defp hud(race) do
    lap = "LAP " <> int(race.lap) <> "/" <> int(Race.laps())
    place = "P" <> int(Race.place(race)) <> "/" <> int(Race.cars())

    [
      text(lap, 4, @hud_y, @sky),
      text(clock(Race.elapsed(race)), div(@width - @char_w * 6, 2), @hud_y, @sky),
      text(place, @width - 4 - @char_w * byte_size(place), @hud_y, @sky),
      {:rect, 4, @bar_y, max(div(race.car.speed * @bar_w, Car.top_speed()), 1), 4, @speed}
    ]
  end

  defp player, do: [{:rect, 150, 212, 20, 8, @player_roof}, {:rect, 140, 220, 40, 14, @player}]

  # Nearest first, so a nearer car is drawn over a farther one.
  defp rivals(race, bands) do
    lap = Track.lap_length()
    reach = Road.ahead() * Track.segment_length()

    ahead =
      for {id, distance, x} <- Rivals.positions(race.rivals),
          delta <- [rem(rem(distance - race.car.distance, lap) + lap, lap)],
          delta > 0 and delta < reach,
          do: {delta, id, distance, x}

    :lists.flatmap(fn rival -> rival(rival, bands) end, :lists.sort(ahead))
  end

  defp rival({delta, id, distance, x}, bands) do
    index = rem(div(distance, Track.segment_length()), Track.segments())

    case :lists.keyfind(index, 5, bands) do
      {_y, _h, centre, _half, _index} ->
        depth = Road.depth(delta)
        half = Road.half(depth)
        bottom = Road.y(depth)
        w = div(half * 3, 10) + 2
        h = div(w, 2) + 1
        cx = centre + div(x * half, 1024)

        [
          {:rect, cx - div(w, 4), bottom - h - div(h, 2), div(w, 2), div(h, 2) + 1, @panel},
          {:rect, cx - div(w, 2), bottom - h, w, h, elem(@rival_colours, id - 1)}
        ]

      false ->
        []
    end
  end

  defp band({y, h, centre, half, index}) do
    stripe = rem(div(index, 3), 2)
    kerb = half + div(half, 6) + 1
    lane = max(div(half, 20), 1)

    marks =
      case stripe do
        0 -> [{:rect, centre - div(lane, 2), y, lane, h, @line}]
        1 -> []
      end

    marks ++
      [
        {:rect, centre - half, y, 2 * half, h, @road},
        {:rect, centre - kerb, y, 2 * kerb, h, kerb_colour(stripe)},
        {:rect, 0, y, @width, h, grass_colour(stripe)}
      ]
  end

  defp kerb_colour(0), do: 0xE03030
  defp kerb_colour(1), do: 0xF0F0F0

  defp grass_colour(0), do: 0x30A030
  defp grass_colour(1), do: 0x289028

  defp horizon(race, hills) do
    shift = rem(rem(race.heading, @hills_period) + @hills_period, @hills_period)
    {:scaled_cropped_image, 0, @hills_y, @width, @hills_h, @sky, shift, 0, 2, 1, [], hills}
  end

  defp sky, do: {:rect, 0, @top, @width, @hills_y - @top, @sky}

  defp centred(body, y), do: text(body, div(@width - @char_w * byte_size(body), 2), y, @panel)

  defp text(body, x, y, bg), do: {:text, x, y, :default16px, @text, bg, body}

  defp pad(n) when n < 10, do: "0" <> int(n)
  defp pad(n), do: int(n)

  defp int(n), do: :erlang.integer_to_binary(n)
end
