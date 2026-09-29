defmodule Badge.App.Rps.Page do
  @moduledoc """
  Rock, paper, scissors against the badge this one is pointed at.

  Pointing two badges at each other starts a game. Each player then picks
  with the arrows and Enter, apart if they like, from the choices dealt in
  a random order. Facing each other again reveals both picks after a
  three-second countdown, with the LEDs pulsing each second and flashing
  the outcome. Enter plays a rematch once the other badge has seen the
  result too. The score against the opponent lasts the visit; the lifetime
  record is kept in NVS.

  The game itself is `Badge.App.Rps.Game`, plain data this page feeds with
  keys, IR frames and ticks.
  """

  use Badge.Page

  alias Badge.App.Rps.Game
  alias Badge.Font
  alias Badge.Identity
  alias Badge.Ir
  alias Badge.Nvs
  alias Badge.Peers
  alias Badge.Pixels
  alias Badge.Profile
  alias Badge.Text
  alias Badge.Theme

  @key :rps_record

  @big :dogica

  @pick_y 44
  @pick_pitch 30
  @status_y 146
  @score_y 170
  @record_y 192
  @hint_y 216
  @reveal_y 76
  @word_y 100
  @side_y 44
  @throw_y 72
  @caption_y 108
  @verdict_y 130

  @win_hue 120
  @lose_hue 0
  @draw_hue 45
  @beat_hue 200

  # Every order the three choices can be dealt in.
  @orders {{1, 2, 3}, {1, 3, 2}, {2, 1, 3}, {2, 3, 1}, {3, 1, 2}, {3, 2, 1}}

  # The first tick of the countdown, then the start of each later second.
  @first_beat Game.countdown() - 1

  @impl true
  def title, do: "RPS"

  @impl true
  def icon, do: :cross

  @impl true
  def refresh(_state), do: 200

  @impl true
  def init do
    session = rem(abs(:erlang.monotonic_time(:millisecond)), 65_535) + 1

    Map.merge(Game.new(session), %{record: Game.blank_record(), stored: nil, loaded: false})
  end

  # Hardware is only touched here, never from a key handler.
  @impl true
  def tick(%{phase: phase} = state) do
    next =
      state
      |> load()
      |> deal()
      |> Game.step()
      |> beat()
      |> joined(phase)
      |> revealed(phase)
      |> named()

    Ir.send(Game.encode(next))

    persist(next)
  end

  defp load(%{loaded: true} = state), do: state

  defp load(state) do
    record = load_record()

    %{state | record: record, stored: record, loaded: true}
  end

  # Each round deals the choices in a fresh order, before anything is drawn.
  defp deal(%{phase: :picking, order: nil} = state) do
    <<roll>> = :crypto.strong_rand_bytes(1)

    %{state | order: elem(@orders, rem(roll, 6))}
  end

  defp deal(state), do: state

  defp revealed(%{phase: :result, outcome: outcome, record: record} = state, before)
       when before != :result do
    Pixels.flash(hue(outcome))

    %{state | record: Game.tally(record, outcome)}
  end

  defp revealed(state, _before), do: state

  defp hue(:win), do: @win_hue
  defp hue(:lose), do: @lose_hue
  defp hue(:draw), do: @draw_hue

  defp beat(%{phase: :countdown, count: count} = state)
       when count == @first_beat or rem(count, 10) == 0 do
    Pixels.flash(@beat_hue)

    state
  end

  defp beat(state), do: state

  # Both players can turn away once the LEDs say the game is on.
  defp joined(%{phase: :picking} = state, :joining) do
    Pixels.flash(@beat_hue)

    state
  end

  defp joined(state, _before), do: state

  defp named(%{opp: opp, name: nil} = state) when opp != nil do
    name =
      case Peers.find(Peers.load(), opp) do
        nil -> "Badge " <> :binary.part(Identity.format(opp), 8, 4)
        %{profile: profile} -> Profile.display_name(profile)
      end

    %{state | name: cut(Text.cp437(name), 16)}
  end

  defp named(state), do: state

  defp persist(%{loaded: true, record: record, stored: stored} = state) when record != stored do
    save_record(record)

    %{state | stored: record}
  end

  defp persist(state), do: state

  @impl true
  def leave(%{loaded: true, record: record, stored: stored}) when record != stored do
    save_record(record)

    :ok
  end

  def leave(_state), do: :ok

  @impl true
  def handle_ir(from, payload, state) do
    case Game.decode(payload) do
      {:ok, frame} -> {:ok, Game.hear(state, from, frame)}
      :error -> :ignore
    end
  end

  @impl true
  def handle_key({:move, direction}, %{phase: :picking, order: order} = state)
      when order != nil do
    case direction do
      :up -> {:ok, Game.move(state, -1)}
      :left -> {:ok, Game.move(state, -1)}
      _down_or_right -> {:ok, Game.move(state, 1)}
    end
  end

  # The cursor starts on nothing, so a held Enter cannot lock a pick by repeating.
  def handle_key({:edit, :newline}, %{phase: :picking, cursor: cursor, order: order} = state)
      when cursor != nil and order != nil,
      do: {:ok, Game.lock(state, elem(order, cursor))}

  def handle_key({:edit, :newline}, %{phase: :result} = state), do: {:ok, Game.next(state)}
  def handle_key(_event, _state), do: :ignore

  @impl true
  def render(%{phase: :countdown, count: count}) do
    [
      line("Reveal in", 0, @reveal_y, :default16px, Theme.dim()),
      line(:erlang.integer_to_binary(div(count + 9, 10)), 0, @word_y, @big, Theme.fg())
    ]
  end

  def render(%{phase: :result, choice: choice, against: against, outcome: outcome} = state) do
    [
      line("You", -1, @side_y, :default16px, Theme.dim()),
      line(label(state), 1, @side_y, :default16px, Theme.dim()),
      line(caption(choice, against, outcome), 0, @caption_y, :default16px, Theme.fg()),
      line(verdict(outcome), 0, @verdict_y, @big, colour(outcome))
    ] ++
      throw(choice, -1, outcome) ++
      throw(against, 1, flip(outcome)) ++ footer(state, result_hint(state))
  end

  # Nothing on the panel says what was picked until the reveal.
  def render(%{phase: :locked} = state) do
    [
      line("LOCKED IN", 0, @pick_y + @pick_pitch, @big, Theme.select()),
      line(status(state), 0, @status_y, :default16px, Theme.fg())
    ] ++ footer(state, "Esc leave")
  end

  def render(state) do
    picks(state, 0, []) ++
      [line(status(state), 0, @status_y, :default16px, Theme.fg())] ++
      footer(state, pick_hint(state))
  end

  defp picks(_state, 3, acc), do: acc

  defp picks(%{order: order} = state, position, acc) do
    y = @pick_y + position * @pick_pitch

    picks(
      state,
      position + 1,
      pick(state, position, Game.word(elem(order || {1, 2, 3}, position)), y) ++ acc
    )
  end

  defp pick(%{phase: phase}, _position, word, y) when phase == :seeking or phase == :joining,
    do: [line(word, 0, y, @big, Theme.dim())]

  defp pick(%{cursor: position}, position, word, y), do: lit(word, 0, y, Theme.select())
  defp pick(_state, _position, word, y), do: [line(word, 0, y, @big, Theme.fg())]

  defp status(%{phase: :seeking}), do: "Point at a badge to start"
  defp status(%{phase: :joining} = state), do: "Connecting to " <> label(state)
  defp status(%{phase: :locked} = state), do: "Point at " <> label(state) <> " to reveal"

  defp status(state) do
    if Game.ready?(state), do: label(state) <> " has picked", else: "Game on! Turn away and pick"
  end

  defp pick_hint(%{phase: :picking}), do: "up/down pick   Enter lock"
  defp pick_hint(%{phase: :joining}), do: "Keep pointing at each other"
  defp pick_hint(_state), do: "Esc leave"

  defp result_hint(%{waiting: true} = state), do: "Waiting for " <> label(state)
  defp result_hint(_state), do: "Enter rematch, Esc leave"

  # The winning pick is lit up; a loser is dimmed, and a draw lights neither.
  defp throw(choice, side, :win), do: lit(Game.word(choice), side, @throw_y, Theme.ok())

  defp throw(choice, side, :lose), do: [line(Game.word(choice), side, @throw_y, @big, Theme.dim())]
  defp throw(choice, side, :draw), do: [line(Game.word(choice), side, @throw_y, @big, Theme.warn())]

  defp flip(:win), do: :lose
  defp flip(:lose), do: :win
  defp flip(:draw), do: :draw

  defp caption(choice, _against, :win), do: Game.beats(choice)
  defp caption(_choice, against, :lose), do: Game.beats(against)
  defp caption(choice, _against, :draw), do: "BOTH PICKED " <> Game.word(choice)

  defp footer(%{record: record} = state, hint) do
    score(state) ++
      [
        line(summary("All time", record), 0, @record_y, :default16px, Theme.dim()),
        line(hint, 0, @hint_y, :default16px, Theme.dim())
      ]
  end

  defp score(%{opp: nil}), do: []

  defp score(%{score: score} = state),
    do: [line(summary("vs " <> label(state), score), 0, @score_y, :default16px, Theme.fg())]

  defp summary(heading, %{win: win, lose: lose, draw: draw}) do
    heading <>
      "  " <>
      :erlang.integer_to_binary(win) <>
      "W " <>
      :erlang.integer_to_binary(lose) <> "L " <> :erlang.integer_to_binary(draw) <> "D"
  end

  defp label(%{name: nil}), do: "Opponent"
  defp label(%{name: name}), do: name

  defp verdict(:win), do: "YOU WIN!"
  defp verdict(:lose), do: "YOU LOSE"
  defp verdict(:draw), do: "DRAW"

  defp colour(:win), do: Theme.ok()
  defp colour(:lose), do: Theme.alert()
  defp colour(:draw), do: Theme.warn()

  # In the background colour on a bar of `colour`, so it stands out on any skin.
  defp lit(text, side, y, colour) do
    {:text, x, y, font, _colour, _bg, text} = line(text, side, y, @big, nil)

    [
      {:text, x, y, font, Theme.bg(), colour, text},
      {:rect, x - 6, y - 5, Font.width(font, text) + 12, 29, colour}
    ]
  end

  # Centred on the panel at 0, or on its left (-1) or right (1) half.
  defp line(text, side, y, font, colour) do
    width = div(Theme.width(), 1 + abs(side))
    left = div((side + abs(side)) * width, 2)

    {:text, left + div(width - Font.width(font, text), 2), y, font, colour, Theme.bg(), text}
  end

  defp cut(text, columns) when byte_size(text) > columns, do: :binary.part(text, 0, columns)
  defp cut(text, _columns), do: text

  defp load_record, do: Game.decode_record(Nvs.get(@key))

  defp save_record(record) do
    case Nvs.put(@key, Game.encode_record(record)) do
      :ok -> :ok
      other -> failed(other)
    end
  catch
    kind, reason -> failed({kind, reason})
  end

  defp failed(reason) do
    :io.format(~c"Rps: write failed ~p~n", [reason])

    {:error, reason}
  end
end
