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

  test "solving shows Solved! and advance opens the next level" do
    state = keys(ready(), @solve_1)
    assert state.mode == :solved
    assert "Solved!" in texts(state)

    next = Page.advance(%{state | until: :erlang.monotonic_time(:millisecond)})

    assert next.mode == :play
    assert next.level == 2
    assert next.unlocked == 2
    assert next.moves == 0
  end

  test "solving unlocks the next level at once, so leaving during the pause keeps it" do
    assert keys(ready(), @solve_1).unlocked == 2
  end

  test "advance waits until the pause is over" do
    state = %{keys(ready(), @solve_1) | until: :erlang.monotonic_time(:millisecond) + 60_000}

    assert Page.advance(state) == state
  end

  test "the last level ends on All solved" do
    state = %{ready(20) | level: 20, mode: :solved, until: :erlang.monotonic_time(:millisecond)}
    done = Page.advance(state)

    assert done.mode == :done
    assert Enum.any?(texts(done), &(&1 =~ "All solved"))
    assert keys(done, [{:edit, :newline}]).level == 1
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
