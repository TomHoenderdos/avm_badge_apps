defmodule Badge.App.Sokoban.Page do
  @moduledoc """
  Sokoban: push every box onto a goal.

  Arrows move and push, `r` restarts the level. Every step heats the tile the
  player lands on, so the start tile only counts once it is walked back to; a solved level shows that heat map until Enter opens the
  next one. Esc on the board goes home.

  Enter opens level select: left and right pick any unlocked level, Enter
  plays it, Esc goes back to the board. A solved level previews its best run's
  heat map and move count, an unsolved one its starting board.

  The highest unlocked level is kept in NVS under `sokoban`, each level's best
  run under `sokoban_h<n>` (see `Badge.App.Sokoban.Record`). NVS is read and
  written only from `tick/1` and `leave/1`.
  """

  use Badge.Page

  alias Badge.App.Sokoban.Board
  alias Badge.App.Sokoban.Levels
  alias Badge.App.Sokoban.Record
  alias Badge.FontType
  alias Badge.Nvs
  alias Badge.Readout
  alias Badge.Theme

  @nvs_key :sokoban
  @count Levels.count()
  @top Theme.content_top()
  @bar_y 216
  @area_h @bar_y - @top - 2
  @max_tile 24
  @margin 8
  # Fractals' Fire, darkest stop lifted to show on a dark skin; data colours, not the skin's.
  @ramp {0x800000, 0xC00000, 0xFF8000, 0xFFFF00, 0xFFFFFF}

  @impl true
  def title, do: "Sokoban"

  @impl true
  def init do
    :maps.merge(%{mode: :play, unlocked: 1, saved: 1, loaded: false, pick: 1, save: nil, preview: nil}, level(1))
  end

  @impl true
  def handle_key({:move, dir}, %{mode: :play} = state) do
    case Board.move(state.board, dir) do
      {:blocked, _board} -> {:ok, state}
      {_moved, board} -> {:ok, solve(%{state | board: board, moves: state.moves + 1, heat: heat(state.heat, board.player)})}
    end
  end

  def handle_key({:char, c}, %{mode: :play} = state) when c == ?r or c == ?R do
    {:ok, %{state | board: state.start, moves: 0, heat: %{}}}
  end

  def handle_key({:edit, :newline}, %{mode: :play} = state), do: {:ok, %{state | mode: :select, pick: state.level}}
  def handle_key({:move, :left}, %{mode: :select} = state), do: {:ok, %{state | pick: max(state.pick - 1, 1)}}
  def handle_key({:move, :right}, %{mode: :select} = state), do: {:ok, %{state | pick: min(state.pick + 1, state.unlocked)}}
  def handle_key({:edit, :newline}, %{mode: :select} = state), do: {:ok, play(state, state.pick)}
  def handle_key({:nav, :home}, %{mode: :select} = state), do: {:ok, %{state | mode: :play}}
  def handle_key({:edit, :newline}, %{mode: :solved, level: @count} = state), do: {:ok, %{state | mode: :done}}
  def handle_key({:edit, :newline}, %{mode: :solved} = state), do: {:ok, play(state, state.level + 1)}
  def handle_key({:move, _dir}, %{mode: :solved} = state), do: {:ok, state}
  def handle_key({:edit, :newline}, %{mode: :done} = state), do: {:ok, play(state, 1)}
  def handle_key(_event, _state), do: :ignore

  @impl true
  def tick(state), do: state |> load() |> persist() |> record() |> look()

  @impl true
  def leave(state) do
    state |> persist() |> record()

    :ok
  end

  @doc false
  def decode(<<n>>) when n >= 1 and n <= @count, do: n
  def decode(_value), do: 1

  @doc false
  def ramp, do: @ramp

  @doc false
  def preview(state, record), do: %{state | preview: :maps.merge(level(state.pick), %{pick: state.pick, record: record})}

  defp load(%{loaded: true} = state), do: state

  defp load(state) do
    unlocked = decode(Nvs.get(@nvs_key))

    play(%{state | unlocked: unlocked, saved: unlocked, loaded: true}, unlocked)
  end

  defp persist(%{unlocked: n, saved: n} = state), do: state

  defp persist(state) do
    Nvs.put(@nvs_key, <<state.unlocked>>)

    %{state | saved: state.unlocked}
  end

  defp record(%{save: nil} = state), do: state

  defp record(%{save: {n, moves, heat, board}} = state) do
    case Record.better?(moves, Record.decode(Nvs.get(key(n)), board)) do
      true -> Nvs.put(key(n), Record.encode(moves, heat, board))
      false -> :ok
    end

    %{state | save: nil}
  end

  defp look(%{mode: :select, pick: pick, preview: %{pick: pick}} = state), do: state
  defp look(%{mode: :select} = state), do: preview(state, Record.decode(Nvs.get(key(state.pick)), level(state.pick).board))
  defp look(state), do: state

  defp key(n), do: :erlang.binary_to_atom("sokoban_h" <> int(n), :utf8)

  defp play(state, n), do: :maps.merge(%{state | mode: :play}, level(n))

  defp level(n) do
    board = Board.parse(Levels.get(n))
    tile = min(@max_tile, min(div(Theme.width(), board.w), div(@area_h, board.h)))

    %{
      level: n,
      board: board,
      start: board,
      moves: 0,
      heat: %{},
      runs: Board.runs(board),
      tile: tile,
      x0: div(Theme.width() - board.w * tile, 2),
      y0: @top + div(@area_h - board.h * tile, 2)
    }
  end

  defp heat(heat, at), do: Map.put(heat, at, Map.get(heat, at, 0) + 1)

  defp solve(state) do
    case Board.solved?(state.board) do
      true ->
        unlocked = min(max(state.unlocked, state.level + 1), @count)

        %{state | mode: :solved, unlocked: unlocked, save: {state.level, state.moves, state.heat, state.start}, preview: nil}

      false ->
        state
    end
  end

  @impl true
  def render(%{mode: :select, pick: pick, preview: %{pick: pick, record: {moves, heat}} = view} = state) do
    hot(view, heat) ++ walls(view) ++ bar(state, "Level " <> int(pick) <> "  Best " <> int(moves) <> " moves")
  end

  def render(%{mode: :select, pick: pick, preview: %{pick: pick} = view} = state) do
    pieces(view) ++ bar(state, "Level " <> int(pick) <> "  Not solved")
  end

  def render(%{mode: :select} = state), do: bar(state, "Level " <> int(state.pick))
  def render(%{mode: :solved} = state), do: hot(state, state.heat) ++ walls(state) ++ bar(state, where(state))
  def render(%{mode: :done} = state), do: centred("All solved") ++ pieces(state) ++ bar(state, where(state))
  def render(state), do: pieces(state) ++ bar(state, where(state))

  defp where(state), do: "Level " <> int(state.level) <> "/" <> int(@count) <> "  Moves " <> int(state.moves)

  defp pieces(view), do: player(view) ++ boxes(view) ++ goals(view) ++ walls(view)

  defp hot(view, heat) do
    top = :lists.foldl(&max/2, 1, :maps.values(heat))

    for {{x, y}, n} <- :maps.to_list(heat), do: cell(view, x, y, 1, :erlang.element(div((n - 1) * 4, max(top - 1, 1)) + 1, @ramp))
  end

  defp player(%{board: %{player: {x, y}}} = view), do: [cell(view, x, y, div(view.tile, 4), Theme.accent())]

  defp boxes(view) do
    for {x, y} = box <- view.board.boxes do
      cell(view, x, y, 2, if(:lists.member(box, view.board.goals), do: Theme.ok(), else: Theme.warn()))
    end
  end

  defp goals(view), do: for({x, y} <- view.board.goals, do: cell(view, x, y, div(view.tile * 3, 8), Theme.dim()))

  defp walls(view) do
    for {x, y, n} <- view.runs, do: {:rect, view.x0 + x * view.tile, view.y0 + y * view.tile, n * view.tile, view.tile, Theme.muted()}
  end

  defp cell(view, x, y, inset, colour) do
    {:rect, view.x0 + x * view.tile + inset, view.y0 + y * view.tile + inset, view.tile - 2 * inset, view.tile - 2 * inset, colour}
  end

  defp centred(text), do: [{:text, Readout.centre_x(text), @top + div(@area_h, 2) - 8, FontType.body(), Theme.fg(), Theme.bg(), text}]

  defp bar(state, right) do
    font = FontType.heading()

    Theme.rule(0, @bar_y, Theme.width()) ++
      [
        {:text, @margin, @bar_y + 2, font, Theme.dim(), Theme.bg(), hints(state.mode)},
        {:text, Readout.right_x(right, font), @bar_y + 2, font, Theme.fg(), Theme.bg(), right}
      ]
  end

  defp hints(:select), do: "</> pick  Enter play"
  defp hints(:solved), do: "Solved! Enter next"
  defp hints(:done), do: "Enter play again"
  defp hints(_mode), do: "r restart  Enter levels"

  defp int(n), do: :erlang.integer_to_binary(n)
end
