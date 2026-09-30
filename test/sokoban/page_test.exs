defmodule Badge.App.Sokoban.PageTest do
  use ExUnit.Case, async: true

  alias Badge.App.Sokoban.Levels
  alias Badge.App.Sokoban.Page

  # Loaded and saved, so tick/1 never reaches NVS.
  defp ready(unlocked \\ 1),
    do: %{Page.init() | loaded: true, unlocked: unlocked, saved: unlocked}

  defp keys(state, events) do
    :lists.foldl(
      fn event, acc ->
        {:ok, next} = Page.handle_key(event, acc)
        next
      end,
      state,
      events
    )
  end

  defp texts(state),
    do: for({:text, _x, _y, _font, _fg, _bg, text} <- Page.render(state), do: text)

  # A shortest solution of Microban 1, found by breadth-first search.
  @solve_1 for dir <-
                 ~w(down left up right right right down left up left left down down right up left up right up up left
                          down right down down right right up left down left up up)a,
               do: {:move, dir}

  test "opens on level 1 with no moves" do
    assert "Level 1/20  Moves 0" in texts(ready())
  end

  test "a move counts, a blocked move does not" do
    state = keys(ready(), [{:move, :right}, {:move, :up}])

    assert state.moves == 1
    assert "Level 1/20  Moves 1" in texts(state)
  end

  test "r restarts the level" do
    state = keys(ready(), [{:move, :right}, {:char, ?r}])

    assert state.moves == 0
    assert state.board == state.start
  end

  defp heat_colours(state) do
    ramp = Tuple.to_list(Page.ramp())

    for {:rect, _x, _y, _w, _h, c} <- Page.render(state), c in ramp, do: c
  end

  test "every successful step heats the tile the player lands on" do
    state = keys(ready(), [{:move, :right}, {:move, :up}, {:move, :left}])

    assert state.heat == %{{2, 3} => 1, {3, 3} => 1}
  end

  test "r clears the heat" do
    assert keys(ready(), [{:move, :right}, {:char, ?r}]).heat == %{}
  end

  test "solving shows the heat map and queues the run to be saved" do
    state = keys(ready(), @solve_1)

    assert state.mode == :solved
    assert state.unlocked == 2
    assert "Enter next" in texts(state)
    assert {:text, _x, _y, :default16px, colour, _bg, "Solved!"} = List.keyfind(Page.render(state), "Solved!", 6)
    assert colour == Badge.Theme.ok()
    assert {1, 33, heat, _board} = state.save
    assert heat == state.heat
    assert length(heat_colours(state)) == map_size(state.heat)
  end

  test "keys other than Enter and Esc wait on the solved screen" do
    state = keys(ready(), @solve_1)

    assert keys(state, [{:move, :left}]) == state
  end

  test "Enter after solving opens the next level with fresh heat" do
    next = keys(ready(), @solve_1 ++ [{:edit, :newline}])

    assert next.mode == :play
    assert next.level == 2
    assert next.moves == 0
    assert next.heat == %{}
  end

  test "Enter after the last level ends on All solved" do
    done = keys(%{ready(20) | level: 20, mode: :solved}, [{:edit, :newline}])

    assert done.mode == :done
    assert "All solved" in texts(done)
    assert keys(done, [{:edit, :newline}]).level == 1
  end

  test "solving drops a cached preview, so the picker reloads the new best" do
    state = Page.preview(keys(ready(), [{:edit, :newline}]), nil)
    state = keys(state, [{:nav, :home}] ++ @solve_1)

    assert state.preview == nil
  end

  test "the heat map uses the fire gradient" do
    assert Page.ramp() == {0x800000, 0xC00000, 0xFF8000, 0xFFFF00, 0xFFFFFF}
  end

  test "the most visited tile is always the hottest colour" do
    state = %{keys(ready(), @solve_1) | heat: %{{2, 3} => 2, {3, 3} => 1}}

    assert elem(Page.ramp(), 4) in heat_colours(state)
    assert elem(Page.ramp(), 0) in heat_colours(state)
  end

  test "the picker shows a solved level's best run" do
    state = keys(ready(3), [{:edit, :newline}, {:move, :left}])
    state = Page.preview(state, {12, %{{2, 3} => 3, {3, 3} => 1}})

    assert "Level 1  Best 12 moves" in texts(state)
    assert length(heat_colours(state)) == 2
  end

  test "the picker shows an unsolved level's starting board" do
    state = Page.preview(keys(ready(3), [{:edit, :newline}]), nil)

    assert "Level 1  Not solved" in texts(state)
  end

  test "the picker drops a preview once the pick moves on" do
    state = Page.preview(keys(ready(3), [{:edit, :newline}, {:move, :left}]), nil)
    moved = keys(state, [{:move, :right}])

    refute Enum.any?(texts(moved), &(&1 =~ "Not solved"))
  end

  test "picker bounds: left stops at 1, right stops at the unlocked level" do
    state = keys(ready(3), [{:edit, :newline}])
    assert state.mode == :select

    assert keys(state, [{:move, :left}, {:move, :left}, {:move, :left}]).pick == 1
    assert keys(state, [{:move, :right}, {:move, :right}, {:move, :right}]).pick == 3
  end

  test "enter in the picker plays the picked level, esc goes back" do
    state = keys(ready(3), [{:edit, :newline}, {:move, :right}])

    assert keys(state, [{:edit, :newline}]).level == 2
    assert keys(state, [{:nav, :home}]).mode == :play
  end

  test "esc on the board goes home" do
    assert Page.handle_key({:nav, :home}, ready()) == :ignore
  end

  test "decode: a saved level resumes, garbage starts at 1" do
    assert Page.decode(<<5>>) == 5
    assert Page.decode(nil) == 1
    assert Page.decode(<<0>>) == 1
    assert Page.decode(<<Levels.count() + 1>>) == 1
    assert Page.decode("12") == 1
  end

  test "renders walls, boxes, goals and the player" do
    rects = for {:rect, _x, _y, _w, _h, _c} = r <- Page.render(ready()), do: r

    assert length(rects) > 10
  end
end
