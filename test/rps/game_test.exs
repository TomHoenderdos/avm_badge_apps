defmodule Badge.App.Rps.GameTest do
  use ExUnit.Case, async: true

  alias Badge.App.Rps.Game, as: Rps
  alias Badge.Sharing.Wire

  @a <<0, 0, 0, 0, 0, 0xA>>
  @b <<0, 0, 0, 0, 0, 0xB>>
  @c <<0, 0, 0, 0, 0, 0xC>>

  defp frame(state) do
    {:ok, frame} = Rps.decode(Rps.encode(state))
    frame
  end

  # Two badges that have joined a game with each other over a clean beam.
  defp paired, do: connect(Rps.new(100), Rps.new(200), 0)

  # Beams both ways, a tick apart, until both badges are in the game.
  defp connect(%{phase: :picking} = a, %{phase: :picking} = b, _n), do: {a, b}

  defp connect(a, b, n) when n < 50 do
    b = Rps.hear(b, @a, frame(a))
    a = Rps.hear(a, @b, frame(b))

    connect(Rps.step(a), Rps.step(b), n + 1)
  end

  # Both lock, then beam at each other until both count down.
  defp shoot(mine, theirs) do
    {a, b} = paired()
    reveal(Rps.lock(a, mine), Rps.lock(b, theirs), 0)
  end

  defp reveal(%{phase: :countdown} = a, %{phase: :countdown} = b, _n), do: {a, b}

  defp reveal(a, b, n) when n < 10 do
    b = Rps.hear(b, @a, frame(a))
    a = Rps.hear(a, @b, frame(b))

    reveal(a, b, n + 1)
  end

  defp steps(state, n), do: :lists.foldl(fn _i, acc -> Rps.step(acc) end, state, :lists.seq(1, n))

  describe "outcome/2" do
    test "rock blunts scissors, scissors cut paper, paper wraps rock" do
      assert Rps.outcome(1, 3) == :win
      assert Rps.outcome(3, 2) == :win
      assert Rps.outcome(2, 1) == :win
      assert Rps.outcome(3, 1) == :lose
      assert Rps.outcome(2, 3) == :lose
      assert Rps.outcome(1, 2) == :lose

      for choice <- 1..3, do: assert(Rps.outcome(choice, choice) == :draw)
    end

    test "choices have names" do
      assert Enum.map(1..3, &Rps.word/1) == ["ROCK", "PAPER", "SCISSORS"]
    end
  end

  describe "the frame" do
    test "round-trips who is playing whom, the round and the pick" do
      state = %{Rps.new(0x1234) | opp_session: 0x5678, round: 7, choice: 2, phase: :locked}

      assert Rps.encode(state) == <<0x10, 0x12, 0x34, 0x56, 0x78, 7, 2>>
      assert Rps.decode(Rps.encode(state)) == {:ok, {0x1234, 0x5678, 7, 2, 0, 0}}
    end

    test "carries the countdown once the round is resolved" do
      state = %{Rps.new(1) | choice: 3}

      assert Rps.encode(%{state | phase: :countdown, count: 30}) == <<0x10, 0, 1, 0, 0, 0, 0xBF>>

      assert Rps.decode(Rps.encode(%{state | phase: :countdown, count: 17})) ==
               {:ok, {1, 0, 0, 3, 2, 8}}

      assert Rps.decode(Rps.encode(%{state | phase: :result})) == {:ok, {1, 0, 0, 3, 2, 0}}
    end

    test "fits the IR link and leaves room to grow" do
      assert byte_size(Rps.encode(Rps.new(65_535))) <= Badge.Ir.max_payload()
      assert Rps.decode(<<0x10, 0, 1, 0, 0, 0, 1, "later">>) == {:ok, {1, 0, 0, 1, 0, 0}}
    end

    test "rejects what no badge of ours sends" do
      assert Rps.decode(<<0x10, 0, 0, 0, 0, 0, 1>>) == :error
      assert Rps.decode(<<0x10, 0, 1, 0, 0, 0, 0x80>>) == :error
      assert Rps.decode(<<0x10, 0, 1, 0, 0, 0, 0x40>>) == :error
      assert Rps.decode(<<0x10, 0, 1, 0, 0, 0, 0xC1>>) == :error
      assert Rps.decode(<<0x10, 0, 1>>) == :error
      assert Rps.decode(Wire.encode(:name, [:name], "Pat")) == :error
      assert Rps.decode("Pat") == :error
      assert Rps.decode(<<>>) == :error
    end

    test "is never taken for a shared profile field" do
      refute match?({:ok, _key, _shared, _value}, Wire.decode(Rps.encode(Rps.new(1))))
    end
  end

  describe "picking" do
    test "the highlight starts on nothing and wraps" do
      state = Rps.new(1)

      assert Rps.move(state, 1).cursor == 0
      assert Rps.move(state, -1).cursor == 2
      assert state |> Rps.move(1) |> Rps.move(-1) |> Map.get(:cursor) == 2
      assert state |> Rps.move(-1) |> Rps.move(1) |> Map.get(:cursor) == 0
    end

    test "there is nothing to pick until a game is on" do
      assert Rps.new(1).phase == :seeking
      assert Rps.lock(Rps.new(1), 1) == Rps.new(1)
    end

    test "a lock is final" do
      {a, _b} = paired()
      locked = Rps.lock(a, 1)

      assert locked.phase == :locked
      assert Rps.lock(locked, 2) == locked
    end

    test "both can lock apart, and the countdown starts once they see each other" do
      {a, b} = paired()
      a = Rps.lock(a, 3)
      b = Rps.lock(b, 1)

      assert {a.phase, b.phase} == {:locked, :locked}

      {a, b} = reveal(a, b, 0)

      assert {a.phase, b.phase} == {:countdown, :countdown}
      assert a.count == b.count
    end
  end

  describe "pairing" do
    test "contact starts a game with the first badge heard, named in each frame" do
      {a, b} = paired()

      assert {a.opp, a.opp_session, a.phase} == {@b, 200, :picking}
      assert {b.opp, b.opp_session, b.phase} == {@a, 100, :picking}
    end

    test "one frame heard is not a game, only the start of joining one" do
      a = Rps.hear(Rps.new(100), @b, frame(Rps.new(200)))

      assert {a.phase, a.opp, a.count} == {:joining, @b, 0}
      assert Rps.lock(a, 1) == a
    end

    test "a badge is in the game once the other names it back, after a second's hold" do
      a = Rps.new(100)
      b = Rps.hear(Rps.new(200), @a, frame(a))

      assert {b.phase, b.count} == {:joining, 0}

      a = Rps.hear(a, @b, frame(b))

      assert a.phase == :joining
      assert steps(a, 9).phase == :joining
      assert steps(a, 10).phase == :picking

      b = Rps.hear(b, @a, frame(a))

      assert steps(b, 10).phase == :picking
    end

    test "a beam that only reaches one way never starts a game" do
      a = Rps.new(100)

      b =
        :lists.foldl(
          fn _i, b -> b |> Rps.hear(@a, frame(a)) |> Rps.step() end,
          Rps.new(200),
          :lists.seq(1, 100)
        )

      assert {b.phase, b.count} == {:joining, 0}
      assert a.phase == :seeking
    end

    test "a badge left joining when the last acknowledgement is lost catches up on the next contact" do
      b = Rps.hear(Rps.new(200), @a, frame(Rps.new(100)))
      a = Rps.new(100) |> Rps.hear(@b, frame(b)) |> steps(10)

      # A was named back; B never heard A name it, and the players turned away.
      assert a.phase == :picking
      assert {b.phase, b.count} == {:joining, 0}

      a = %{a | order: {1, 2, 3}} |> Rps.lock(2)

      for gap <- [20, 100] do
        later = b |> steps(gap) |> Rps.hear(@a, frame(a)) |> steps(10)

        assert later.phase == :picking
        assert {later.opp, later.round} == {@a, 0}
        assert Rps.ready?(later)
      end
    end

    test "a badge still joining holds on through silence, but lets another take over" do
      joining = Rps.hear(Rps.new(100), @b, frame(Rps.new(200)))
      stranger = frame(Rps.new(300))

      assert steps(joining, 1000).opp == @b
      assert joining |> steps(29) |> Rps.hear(@c, stranger) |> Map.get(:opp) == @b
      assert joining |> steps(30) |> Rps.hear(@c, stranger) |> Map.get(:opp) == @c
    end

    test "a badge playing someone else is not adopted" do
      {a, _b} = paired()
      c = Rps.new(300)

      assert Rps.hear(c, @a, frame(a)) == c
    end

    test "once a game is on, other badges are ignored" do
      {a, _b} = paired()

      for phase <- [:joining, :picking, :locked, :countdown, :result] do
        state = %{a | phase: phase}

        assert Rps.hear(state, @c, frame(Rps.new(300))) == state
      end
    end

    test "an opponent that re-enters the page starts a fresh game" do
      {a, b} = paired()
      a = %{a | round: 5, score: %{win: 2, lose: 1, draw: 0}}
      back = Rps.hear(Rps.new(201), @a, frame(a))
      a = Rps.hear(a, @b, frame(back))

      assert {a.opp_session, a.phase} == {201, :joining}
      assert a.round == 0
      assert a.score == Rps.blank_record()
      assert b.opp == @a
    end

    test "an opponent that pairs with someone else is let go" do
      {a, b} = paired()
      a = Rps.hear(a, @b, frame(%{b | opp_session: 300}))

      assert a.opp == nil
      assert a.phase == :seeking
    end
  end

  describe "a round" do
    test "hearing the other's pick is not enough to start the countdown" do
      {a, b} = paired()
      b = Rps.lock(b, 2)
      a = a |> Rps.lock(1) |> Rps.hear(@b, frame(b))

      assert Rps.ready?(a)
      assert a.phase == :locked
      assert {:ok, {100, 200, 0, 1, 1, 0}} = Rps.decode(Rps.encode(a))
    end

    test "the countdown starts once each knows the other has its pick, on both badges" do
      {a, b} = shoot(3, 2)

      assert {a.outcome, b.outcome} == {:win, :lose}
      assert {a.against, b.against} == {2, 3}
      assert a.count == b.count
    end

    test "a badge hearing the other's countdown joins it where it is" do
      {a, _b} = shoot(1, 3)
      {_a, b} = paired()
      running = steps(a, 14)
      b = b |> Rps.lock(3) |> Rps.hear(@a, frame(running))

      assert b.phase == :countdown
      assert b.count == running.count
    end

    test "a badge that only hears the other after its reveal goes straight to the result" do
      {a, _b} = shoot(1, 3)
      {_a, b} = paired()
      revealed = steps(a, Rps.countdown())
      b = b |> Rps.lock(3) |> Rps.hear(@a, frame(revealed)) |> Rps.step()

      assert {revealed.phase, b.phase} == {:result, :result}
      assert {revealed.outcome, b.outcome} == {:win, :lose}
    end

    test "the countdown runs into the result and the score" do
      {a, _b} = shoot(1, 3)
      almost = steps(a, Rps.countdown() - 1)

      assert almost.phase == :countdown
      assert almost.score == Rps.blank_record()

      done = Rps.step(almost)

      assert done.phase == :result
      assert done.score.win == 1
    end

    test "a pick from another round does not resolve this one" do
      {a, b} = paired()
      a = Rps.lock(a, 1)
      a = Rps.hear(a, @b, frame(%{Rps.lock(b, 2) | round: 1}))

      assert a.phase == :locked
      refute Rps.ready?(a)
    end

    test "the next round waits for the opponent to see this one's result" do
      {a, b} = paired()
      a = Rps.lock(a, 1)
      b = b |> Rps.lock(2) |> Rps.hear(@a, frame(a))
      # A starts counting down; B has not heard it yet.
      a = Rps.hear(a, @b, frame(b))
      waiting = a |> steps(Rps.countdown()) |> Rps.next()

      assert {waiting.phase, waiting.waiting, b.phase} == {:result, true, :locked}

      b = b |> Rps.hear(@a, frame(waiting)) |> Rps.step()
      a = Rps.hear(waiting, @b, frame(b))

      assert a.phase == :picking
      assert a.round == 1
      assert a.cursor == nil
    end

    test "the next round opens at once if the opponent has already resolved" do
      {a, b} = shoot(1, 2)
      a = a |> Rps.hear(@b, frame(b)) |> steps(Rps.countdown()) |> Rps.next()

      assert {a.phase, a.round} == {:picking, 1}
    end

    test "every game and every rematch is dealt afresh" do
      {a, b} = paired()

      assert a.order == nil

      {a, b} = reveal(Rps.lock(%{a | order: {3, 2, 1}}, 1), Rps.lock(b, 2), 0)
      a = a |> Rps.hear(@b, frame(b)) |> steps(Rps.countdown()) |> Rps.next()

      assert {a.phase, a.order} == {:picking, nil}
    end

    test "the opponent's resolved pick is not taken for the next round" do
      {a, b} = shoot(1, 2)

      a =
        a
        |> Rps.hear(@b, frame(b))
        |> steps(Rps.countdown())
        |> Rps.next()
        |> Rps.lock(3)
        |> Rps.hear(@b, frame(b))

      assert a.phase == :locked
      refute Rps.ready?(a)
    end
  end

  describe "two badges over a lossy beam" do
    setup do
      :rand.seed(:exsss, {1, 2, 3})
      :ok
    end

    test "agree on every round" do
      {a, b, _c} = play(Rps.new(100), Rps.new(200), nil, 6000, 0.4)

      assert_agree(a, b)
      assert spread(a, b) <= 2
    end

    test "agree when players turn away to pick and face each other to reveal" do
      Process.put(:apart, true)
      {a, b, _c} = play(Rps.new(100), Rps.new(200), nil, 8000, 0.2)

      assert_agree(a, b)
      assert spread(a, b) <= 2
    end

    test "agree when the beam only works one way at a time" do
      Process.put(:one_way, 40)
      {a, b, _c} = play(Rps.new(100), Rps.new(200), nil, 20_000, 0.3)

      assert_agree(a, b)
    end

    test "agree when the beam is far worse one way than the other" do
      {a, b, _c} = play(Rps.new(100), Rps.new(200), nil, 8000, %{@a => 0.8, @b => 0.2})

      assert_agree(a, b)
      assert spread(a, b) <= 2
    end

    test "agree when the beam drops out for seconds at a time" do
      Process.put(:bursts, true)
      {a, b, _c} = play(Rps.new(100), Rps.new(200), nil, 20_000, 0.2)

      assert_agree(a, b)
    end

    test "agree with a third badge in view" do
      {a, b, _c} = play(Rps.new(100), Rps.new(200), nil, 40, 0.0)
      {a, b, c} = play(a, b, Rps.new(300), 6000, 0.2)

      assert_agree(a, b)
      assert spread(a, b) <= 2
      assert c.history == []
    end

    test "agree after one re-enters the page mid-game" do
      {a, _b, _c} = play(Rps.new(100), Rps.new(200), nil, 1500, 0.3)
      {a, b, _c} = play(a, Map.put(Rps.new(201), :history, []), nil, 4000, 0.3)

      assert_agree(a, b)
      assert spread(a, b) <= 2
    end
  end

  # The largest gap, in ticks, between the two badges revealing a round.
  defp spread(a, b) do
    mine = for {session, _r, _c, _a, tick} <- a.history, session == b.session, do: tick
    theirs = for {session, _r, _c, _a, tick} <- b.history, session == a.session, do: tick
    shared = min(length(mine), length(theirs))

    gaps =
      Enum.zip_with(
        Enum.take(:lists.reverse(mine), shared),
        Enum.take(:lists.reverse(theirs), shared),
        &abs(&1 - &2)
      )

    Enum.max(gaps)
  end

  defp assert_agree(a, b) do
    mine =
      for {session, round, choice, against, _tick} <- a.history,
          session == b.session,
          do: {round, choice, against}

    theirs =
      for {session, round, choice, against, _tick} <- b.history,
          session == a.session,
          do: {round, against, choice}

    shared = min(length(mine), length(theirs))

    assert shared >= 20
    assert abs(length(mine) - length(theirs)) <= 1
    assert Enum.take(:lists.reverse(mine), shared) == Enum.take(:lists.reverse(theirs), shared)

    assert for({round, _c, _a} <- :lists.reverse(mine), do: round) ==
             for(i <- 0..(length(mine) - 1), do: rem(i, 256))
  end

  # Ticks both badges like the page does: beams every other tick, each frame lost with `loss`.
  defp play(a, b, c, ticks, loss) do
    :lists.foldl(
      fn tick, {a, b, c} ->
        Process.put(:tick, tick)
        {a, b, c} = {act(a), act(b), c && act(c)}

        {a, b, c} =
          if rem(tick, 2) == 0 and facing?(a, b), do: exchange(a, b, c, loss), else: {a, b, c}

        {a, b, c}
      end,
      {Map.put_new(a, :history, []), Map.put_new(b, :history, []), c && Map.put_new(c, :history, [])},
      :lists.seq(1, ticks)
    )
  end

  # With `:apart` set, players turn away while either is still picking.
  defp facing?(a, b) do
    Process.get(:apart) != true or (a.phase != :picking and b.phase != :picking)
  end

  defp exchange(a, b, c, loss) do
    {to_b, to_a} = directions(:erlang.get(:one_way))
    b = if to_b, do: send_to(b, @a, a, loss), else: b
    a = if to_a, do: send_to(a, @b, b, loss), else: a

    case c do
      nil ->
        {a, b, nil}

      c ->
        c = c |> send_to(@a, a, loss) |> send_to(@b, b, loss)
        {send_to(a, @c, c, loss), send_to(b, @c, c, loss), c}
    end
  end

  # With `:one_way` set to n, the beam carries A to B for n exchanges, then B to A.
  defp directions(:undefined), do: {true, true}

  defp directions(n) do
    turn = Process.get(:turn, 0)
    Process.put(:turn, turn + 1)
    forward = rem(div(turn, n), 2) == 0

    {forward, not forward}
  end

  defp send_to(receiver, from, sender, loss) do
    if dropped?(from, loss), do: receiver, else: Rps.hear(receiver, from, frame(sender))
  end

  # Uniform loss, and with `:bursts` set, a sender's beam blocked for up to 8 s at a time.
  defp dropped?(from, loss) when is_map(loss), do: dropped?(from, Map.fetch!(loss, from))

  defp dropped?(from, loss) do
    case Process.get({:blocked, from}, 0) do
      0 ->
        if Process.get(:bursts) && :rand.uniform(40) == 1 do
          Process.put({:blocked, from}, :rand.uniform(40))
          true
        else
          :rand.uniform() < loss
        end

      left ->
        Process.put({:blocked, from}, left - 1)
        true
    end
  end

  # A person: picks after a while, and is quick to play again.
  defp act(state) do
    next =
      case {state.phase, :rand.uniform(10)} do
        {:picking, 1} -> Rps.lock(state, :rand.uniform(3))
        {:result, roll} when roll <= 4 -> Rps.next(state)
        _ -> state
      end
      |> Rps.step()

    if next.phase == :result and state.phase != :result do
      %{
        next
        | history: [
            {next.opp_session, next.round, next.choice, next.against, Process.get(:tick)}
            | next.history
          ]
      }
    else
      next
    end
  end
end
