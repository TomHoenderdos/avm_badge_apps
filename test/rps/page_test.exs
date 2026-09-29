defmodule Badge.App.Rps.PageTest do
  use ExUnit.Case, async: false

  alias Badge.App.Rps.Page
  alias Badge.App.Rps.Game, as: Rps
  alias Badge.Theme

  @other <<0, 0, 0, 0, 0, 0xB>>

  # A page after its first tick, without touching NVS.
  defp loaded, do: %{Page.init() | loaded: true, stored: Rps.blank_record()}

  # In a game with a badge whose name is already known, so no tick looks it
  # up, and dealt in plain order unless told otherwise.
  defp paired(opponent \\ Rps.new(200), order \\ {1, 2, 3}) do
    {:ok, state} = Page.handle_ir(@other, Rps.encode(opponent), loaded())
    %{state | name: "Pat", order: order, phase: :picking}
  end

  # Picks `choice` the only way there is: arrows to it, then Enter.
  defp pick(%{order: order} = state, choice) do
    steps = for position <- 0..2, elem(order, position) == choice, do: position + 1

    moved =
      :lists.foldl(fn _i, acc -> press(acc, {:move, :down}) end, state, :lists.seq(1, hd(steps)))

    press(moved, {:edit, :newline})
  end

  defp locked_opponent(choice), do: Rps.lock(%{Rps.new(200) | phase: :picking}, choice)

  defp press(state, event) do
    {:ok, next} = Page.handle_key(event, state)
    next
  end

  defp texts(state), do: for({:text, _x, _y, _f, _c, _b, body} <- Page.render(state), do: body)

  defp says?(state, text), do: Enum.any?(texts(state), &(:binary.match(&1, text) != :nomatch))

  # The pick drawn on a lit background, if any.
  defp lit(state) do
    case for({:text, _x, _y, _f, _c, bg, body} <- Page.render(state), bg == Theme.ok(), do: body) do
      [] -> nil
      [body] -> body
    end
  end

  defp colour_of(state, text) do
    [c] = for {:text, _x, _y, _f, c, _b, ^text} <- Page.render(state), do: c
    c
  end

  describe "identity" do
    test "fits a grid cell" do
      assert Page.title() == "RPS"
      assert byte_size(Page.title()) <= 13
    end

    test "does not trap escape, in any phase" do
      for phase <- [:picking, :locked, :countdown, :result] do
        assert Page.handle_key({:nav, :home}, %{loaded() | phase: phase}) == :ignore
      end
    end

    test "every entry is a new session" do
      assert Page.init().session in 1..65_535
    end
  end

  describe "keys" do
    test "nothing can be picked before a game is on" do
      assert Page.handle_key({:move, :down}, loaded()) == :ignore
    end

    test "nothing can be picked before the choices are dealt" do
      undealt = paired(Rps.new(200), nil)

      assert Page.handle_key({:move, :down}, undealt) == :ignore
      assert Page.handle_key({:edit, :newline}, %{undealt | cursor: 0}) == :ignore
    end

    test "letters do nothing, so no key names a pick" do
      for char <- [?r, ?p, ?s, ?R, ?P, ?S, ?x] do
        assert Page.handle_key({:char, char}, paired()) == :ignore
      end
    end

    test "Enter locks whatever the order put under the highlight" do
      shuffled = paired(Rps.new(200), {3, 1, 2})

      assert shuffled |> press({:move, :down}) |> press({:edit, :newline}) |> Map.get(:choice) ==
               3

      assert shuffled |> press({:move, :up}) |> press({:edit, :newline}) |> Map.get(:choice) == 2
      assert pick(shuffled, 1).choice == 1
    end

    test "Enter locks only once the arrows have picked something" do
      assert Page.handle_key({:edit, :newline}, paired()) == :ignore

      state = paired() |> press({:move, :down}) |> press({:move, :down})

      assert press(state, {:edit, :newline}).choice == 2
      assert paired() |> press({:move, :up}) |> press({:edit, :newline}) |> Map.get(:choice) == 3
    end

    test "a locked pick cannot be changed" do
      locked = pick(paired(), 1)

      assert locked.phase == :locked
      assert Page.handle_key({:move, :down}, locked) == :ignore
      assert Page.handle_key({:edit, :newline}, locked) == :ignore
    end

    test "Enter on the result waits for the opponent" do
      result = %{paired() | phase: :result, choice: 1, against: 3, outcome: :win}

      assert press(result, {:edit, :newline}).waiting
    end

    test "never touch the beam" do
      Process.register(self(), Badge.Ir.Link)

      paired()
      |> press({:move, :down})
      |> press({:edit, :newline})

      refute_received {:"$gen_cast", _}
    end
  end

  describe "dealing" do
    test "a tick deals the choices in a random order, once a round" do
      Process.register(self(), Badge.Ir.Link)
      dealt = Page.tick(paired(Rps.new(200), nil))

      assert Enum.sort(Tuple.to_list(dealt.order)) == [1, 2, 3]
      assert Page.tick(dealt).order == dealt.order
    end

    test "every order turns up" do
      Process.register(self(), Badge.Ir.Link)
      undealt = paired(Rps.new(200), nil)
      orders = for _i <- 1..300, into: MapSet.new(), do: Page.tick(undealt).order

      assert MapSet.size(orders) == 6
    end

    test "the choices are drawn top to bottom in the order dealt" do
      state = paired(Rps.new(200), {3, 1, 2})
      words = for {:text, _x, y, :dogica, _c, _b, word} <- Page.render(state), do: {y, word}

      assert for({_y, word} <- Enum.sort(words), do: word) == ["SCISSORS", "ROCK", "PAPER"]
    end

    test "nothing is dealt while looking for a game" do
      assert Page.tick(loaded()).order == nil
    end
  end

  describe "the beam" do
    test "every tick beams this badge's frame" do
      Process.register(self(), Badge.Ir.Link)
      state = loaded()

      for _i <- 1..3, do: Page.tick(state)

      for _i <- 1..3 do
        assert_received {:"$gen_cast", {:transmit, payload}}
        assert Rps.decode(payload) == {:ok, {state.session, 0, 0, 0, 0, 0}}
      end
    end

    test "frames that are not RPS are dropped" do
      assert Page.handle_ir(@other, "Pat", loaded()) == :ignore
      assert Page.handle_ir(@other, <<1, 1, "Pat">>, loaded()) == :ignore
    end

    test "pointing at another badge starts joining a game with it" do
      {:ok, joining} = Page.handle_ir(@other, Rps.encode(Rps.new(200)), loaded())

      assert {joining.phase, joining.opp} == {:joining, @other}
      assert says?(joining, "Connecting to Opponent")
      assert says?(joining, "Keep pointing at each other")
      assert Page.handle_key({:move, :down}, %{joining | order: {1, 2, 3}}) == :ignore
    end
  end

  describe "the LEDs" do
    test "pulse when the game is on, so both players know to turn away" do
      Process.register(self(), Badge.Pixels)
      holding = %{paired() | phase: :joining, count: 1}

      assert Page.tick(holding).phase == :picking
      assert_received {:"$gen_cast", {:flash, 200, _ticks}}
    end

    test "pulse once as each second of the countdown begins" do
      Process.register(self(), Badge.Pixels)
      state = %{paired() | phase: :countdown, count: Rps.countdown(), choice: 1, against: 3}

      {last, beats} =
        :lists.foldl(
          fn tick, {state, beats} ->
            next = Page.tick(state)

            receive do
              {:"$gen_cast", {:flash, 200, _ticks}} -> {next, [{tick, texts(next)} | beats]}
            after
              0 -> {next, beats}
            end
          end,
          {state, []},
          :lists.seq(1, Rps.countdown() - 1)
        )

      assert last.phase == :countdown

      assert :lists.reverse(beats) == [
               {1, ["Reveal in", "3"]},
               {10, ["Reveal in", "2"]},
               {20, ["Reveal in", "1"]}
             ]
    end
  end

  describe "render" do
    test "alone, it asks to be pointed at someone" do
      state = loaded()

      assert says?(state, "Point at a badge to start")
      assert colour_of(state, "ROCK") == Theme.dim()
      assert says?(state, "All time  0W 0L 0D")
      refute says?(state, "vs ")
    end

    test "once a game is on, it sends the players apart to pick" do
      assert says?(paired(), "Game on! Turn away and pick")
      assert says?(paired(), "vs Pat  0W 0L 0D")
      assert says?(paired(locked_opponent(2)), "Pat has picked")
      assert says?(%{paired() | name: nil}, "vs Opponent")
    end

    test "a locked pick asks for the badges to face each other again" do
      assert says?(pick(paired(), 1), "Point at Pat to reveal")
    end

    test "the highlight is a bar in the select colour, on every skin" do
      state = press(paired(), {:move, :down})

      for skin <- Badge.Skin.all() do
        Badge.Skin.activate(skin)
        items = Page.render(state)

        assert [{:text, x, _y, _f, fg, bar, "ROCK"}] =
                 for({:text, _, _, _, _, _, "ROCK"} = item <- items, do: item)

        assert {fg, bar} == {Theme.bg(), Theme.select()}
        assert fg != bar
        assert Enum.any?(items, &match?({:rect, rx, _, _, _, ^bar} when rx < x, &1))

        for word <- ["PAPER", "SCISSORS"] do
          assert [{:text, _, _, _, colour, bg, ^word}] =
                   for({:text, _, _, _, _, _, ^word} = item <- items, do: item)

          assert {colour, bg} == {Theme.fg(), Theme.bg()}
        end
      end
    end

    test "a locked pick is shown nowhere, not even as the one left lit" do
      locked = pick(paired(), 3)

      assert texts(locked) |> Enum.member?("LOCKED IN")

      for word <- ["ROCK", "PAPER", "SCISSORS"] do
        refute Enum.any?(texts(locked), &(:binary.match(&1, word) != :nomatch))
      end
    end

    test "nothing on the panel depends on this badge's pick until the reveal" do
      for choice <- 1..3 do
        locked = pick(paired(), choice)
        counting = %{locked | phase: :countdown, count: 25}

        assert Page.render(locked) == Page.render(pick(paired(), 1))
        assert Page.render(counting) == Page.render(%{counting | choice: 1})
      end
    end

    test "the opponent's pick shows nowhere before the result" do
      rock = paired(locked_opponent(1))
      scissors = paired(locked_opponent(3))

      assert Page.render(rock) == Page.render(scissors)
      assert Page.render(pick(rock, 2)) != Page.render(rock)

      countdown = fn state -> %{state | phase: :countdown, count: 9} end
      assert Page.render(countdown.(rock)) == Page.render(countdown.(scissors))
    end

    test "the countdown lasts three seconds, one number a second" do
      numbers =
        for count <- Rps.countdown()..1//-1 do
          ["Reveal in", number] = texts(%{paired() | phase: :countdown, count: count})
          number
        end

      assert Rps.countdown() == 30
      assert Enum.dedup(numbers) == ["3", "2", "1"]
      assert Enum.count(numbers, &(&1 == "1")) == 10
    end

    test "the result shows both picks, who won and what next" do
      result = %{paired() | phase: :result, choice: 1, against: 3, outcome: :win}

      assert says?(result, "You") and says?(result, "Pat")
      assert colour_of(result, "YOU WIN!") == Theme.ok()
      assert says?(result, "ROCK BLUNTS SCISSORS")
      assert colour_of(result, "SCISSORS") == Theme.dim()
      assert says?(result, "Enter rematch, Esc leave")
      assert says?(%{result | waiting: true}, "Waiting for Pat")
    end

    test "the winning pick is lit up, on whichever side it is" do
      win = %{paired() | phase: :result, choice: 2, against: 1, outcome: :win}
      lose = %{paired() | phase: :result, choice: 2, against: 3, outcome: :lose}

      assert lit(win) == "PAPER"
      assert lit(lose) == "SCISSORS"
      assert colour_of(lose, "PAPER") == Theme.dim()
      assert colour_of(lose, "YOU LOSE") == Theme.alert()
      assert says?(lose, "SCISSORS CUT PAPER")
    end

    test "a draw lights neither pick" do
      draw = %{paired() | phase: :result, choice: 3, against: 3, outcome: :draw}

      assert lit(draw) == nil
      assert colour_of(draw, "DRAW") == Theme.warn()
      assert says?(draw, "BOTH PICKED SCISSORS")

      assert for({:text, _, _, _, c, _, "SCISSORS"} <- Page.render(draw), do: c) == [
               Theme.warn(),
               Theme.warn()
             ]
    end

    test "every piece of text fits the panel" do
      states = [
        loaded(),
        %{paired() | name: "Bartholomew Pat"},
        %{paired() | phase: :countdown, count: 5},
        %{paired() | phase: :result, choice: 3, against: 3, outcome: :draw, waiting: true}
      ]

      states = states ++ [%{paired() | phase: :result, choice: 1, against: 3, outcome: :win}]

      for state <- states, {:text, x, _y, font, _c, _b, body} <- Page.render(state) do
        assert x >= 0
        assert x + Badge.Font.width(font, body) <= Theme.width()
      end

      for state <- states, {:rect, x, y, w, h, _c} <- Page.render(state) do
        assert x >= 0 and x + w <= Theme.width()
        assert y >= Theme.content_top() and y + h <= Theme.height()
      end
    end
  end
end
