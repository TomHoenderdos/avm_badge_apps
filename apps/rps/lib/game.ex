defmodule Badge.App.Rps.Game do
  @moduledoc """
  Rock, paper, scissors between two badges, as plain data.

  `Badge.App.Rps.Page` holds this state, feeds it keys, IR frames and
  ticks, and beams `encode/1`. A game goes:

    1. `:seeking` until another badge is in sight
    2. `:joining` with it until one of its frames names this badge back,
       then a second more so the other badge hears the same
    3. `:picking`, apart if the players like; the beam is not needed. Each
       round deals the choices in a random `order`, so the keys pressed say
       nothing about the pick
    4. `:locked` until each badge has the other's pick and knows the other
       has its own
    5. `:countdown`, three seconds, then `:result`; Enter plays a rematch

  A frame says who is playing whom, which round the sender is on and what it
  threw:

      <<tag, mine::16, theirs::16, round, stage::2, count::4, choice::2>>

  `mine` is the sender's session, new on every entry to the page; `theirs`
  is the session it is playing, 0 for nobody, so a frame naming this badge
  is the other's acknowledgement that it has been heard. A badge left
  joining catches up whenever the beam next reaches it, since the other
  names it in every frame. `choice` is 0 until a pick is locked, then 1
  rock, 2 paper, 3 scissors. `stage` is 1 once the sender has the other's
  pick too, and 2 once it has resolved the round and counts down or shows
  the result, with `count` the fifths of a second of countdown left, so
  the other badge joins the countdown where it is. Paired badges count
  rounds from 0, and a rematch only starts once the other badge has
  resolved the round too.

  The tag is below 0x20 and above every `Badge.Sharing.Wire` field tag.
  """

  @tag 0x10
  # Ticks of countdown, ten for each second.
  @countdown 30
  # Ticks to keep joining once sure, so the other badge hears as much.
  @hold 10
  # Ticks of silence before a badge still joining may take up another.
  @give_up 30

  @doc "The first byte of every frame."
  def tag, do: @tag

  @doc "Ticks the countdown lasts."
  def countdown, do: @countdown

  @doc "A badge looking for a game, for one visit to the page; `session` is 1 to 65535."
  @spec new(pos_integer) :: map
  def new(session) do
    %{
      session: session,
      phase: :seeking,
      round: 0,
      order: nil,
      cursor: nil,
      choice: 0,
      against: 0,
      outcome: nil,
      count: 0,
      waiting: false,
      opp: nil,
      opp_session: 0,
      quiet: 0,
      name: nil,
      heard: {0, 0, 0, 0},
      score: blank_record()
    }
  end

  @doc "The frame this badge beams."
  @spec encode(map) :: binary
  def encode(%{session: session, opp_session: theirs, round: round, choice: choice} = state) do
    %{phase: phase, count: count} = state

    stage =
      cond do
        phase == :countdown or phase == :result -> 2
        phase == :locked and ready?(state) -> 1
        true -> 0
      end

    <<@tag, session::16, theirs::16, round, stage::2, div(count, 2)::4, choice::2>>
  end

  @doc """
  A frame as `{mine, theirs, round, choice, stage, count}`, or `:error` for
  anything this game does not send.
  """
  @spec decode(binary) :: {:ok, tuple} | :error
  def decode(<<@tag, mine::16, theirs::16, round, stage::2, count::4, choice::2, _rest::binary>>)
      when mine > 0 and stage < 3 and (choice > 0 or stage == 0),
      do: {:ok, {mine, theirs, round, choice, stage, count}}

  def decode(_payload), do: :error

  @doc "How `mine` fares against `theirs`, both 1 to 3."
  @spec outcome(1..3, 1..3) :: :win | :lose | :draw
  def outcome(mine, theirs), do: elem({:draw, :win, :lose}, rem(mine - theirs + 3, 3))

  @doc "The name of a choice, 1 to 3."
  @spec word(1..3) :: binary
  def word(choice), do: elem({"ROCK", "PAPER", "SCISSORS"}, choice - 1)

  @doc "Why a choice, 1 to 3, wins."
  @spec beats(1..3) :: binary
  def beats(choice),
    do: elem({"ROCK BLUNTS SCISSORS", "PAPER COVERS ROCK", "SCISSORS CUT PAPER"}, choice - 1)

  @doc "Moves the highlight; the first move from none lands on an end."
  @spec move(map, -1 | 1) :: map
  def move(%{cursor: nil} = state, 1), do: %{state | cursor: 0}
  def move(%{cursor: nil} = state, -1), do: %{state | cursor: 2}
  def move(%{cursor: cursor} = state, delta), do: %{state | cursor: rem(cursor + delta + 3, 3)}

  @doc "Locks a choice, 1 to 3, once a game is on."
  @spec lock(map, 1..3) :: map
  def lock(%{phase: :picking} = state, choice),
    do: resolve(%{state | phase: :locked, choice: choice})

  def lock(state, _choice), do: state

  @doc "Enter on the result: a rematch, or waiting until the opponent has resolved this round."
  @spec next(map) :: map
  def next(%{phase: :result} = state) do
    if released?(state), do: advance(state), else: %{state | waiting: true}
  end

  def next(state), do: state

  @doc "Whether the opponent was last heard with a pick for this round."
  @spec ready?(map) :: boolean
  def ready?(%{round: round, heard: {round, choice, _stage, _count}}), do: choice > 0
  def ready?(_state), do: false

  @doc "Applies a decoded frame from the badge with chip id `from`."
  @spec hear(map, binary, tuple) :: map
  def hear(
        %{opp: from, opp_session: mine, session: session} = state,
        from,
        {mine, theirs, round, choice, stage, count}
      )
      when theirs == 0 or theirs == session do
    %{state | heard: {round, choice, stage, count}, quiet: 0}
    |> acknowledged(theirs == session)
    |> follow()
  end

  # A badge free to play starts joining; so does the opponent, back on the
  # page, and so does another badge once the one being joined falls silent.
  def hear(%{phase: phase, opp: opp, session: session, quiet: quiet} = state, from, frame)
      when (phase == :seeking or opp == from or (phase == :joining and quiet >= @give_up)) and
             (elem(frame, 1) == 0 or elem(frame, 1) == session) do
    {mine, theirs, round, choice, stage, count} = frame

    state
    |> pair(from, mine, {round, choice, stage, count}, :joining)
    |> acknowledged(theirs == session)
  end

  # The opponent has started a game with someone else.
  def hear(%{opp: from} = state, from, _frame), do: pair(state, nil, 0, {0, 0, 0, 0}, :seeking)

  def hear(state, _from, _frame), do: state

  @doc "One tick: finishes joining, counts a silent badge's quiet, and runs the countdown."
  @spec step(map) :: map
  def step(%{phase: :countdown, count: 1, score: score, outcome: outcome} = state),
    do: %{state | phase: :result, count: 0, score: tally(score, outcome)}

  def step(%{phase: :joining, count: 1} = state), do: %{state | phase: :picking, count: 0}

  def step(%{phase: phase, count: count} = state)
      when count > 1 and (phase == :countdown or phase == :joining),
      do: %{state | count: count - 1}

  def step(%{phase: :joining, quiet: quiet} = state) when quiet < @give_up,
    do: %{state | quiet: quiet + 1}

  def step(state), do: state

  # Named back by the badge being joined: it has heard this one.
  defp acknowledged(%{phase: :joining, count: 0} = state, true), do: %{state | count: @hold}
  defp acknowledged(state, _named), do: state

  defp pair(state, opp, session, heard, phase) do
    %{
      state
      | opp: opp,
        opp_session: session,
        quiet: 0,
        name: nil,
        heard: heard,
        round: 0,
        phase: phase,
        order: nil,
        cursor: nil,
        choice: 0,
        against: 0,
        outcome: nil,
        count: 0,
        waiting: false,
        score: blank_record()
    }
  end

  defp follow(state), do: state |> resolve() |> release()

  # Only once the other has this badge's pick too; a countdown already
  # running on the other badge is joined where it is.
  defp resolve(
         %{phase: :locked, round: round, heard: {round, theirs, stage, count}, choice: mine} =
           state
       )
       when theirs > 0 and stage > 0 do
    start = if stage == 2, do: max(count * 2, 1), else: @countdown

    %{
      state
      | phase: :countdown,
        count: start,
        against: theirs,
        outcome: outcome(mine, theirs)
    }
  end

  defp resolve(state), do: state

  defp release(%{waiting: true} = state) do
    if released?(state), do: advance(state), else: state
  end

  defp release(state), do: state

  defp released?(%{round: round, heard: {round, _choice, stage, _count}}), do: stage == 2

  defp released?(%{round: round, heard: {heard, _choice, _stage, _count}}),
    do: heard == rem(round + 1, 256)

  defp advance(%{round: round} = state) do
    %{
      state
      | round: rem(round + 1, 256),
        phase: :picking,
        order: nil,
        cursor: nil,
        choice: 0,
        against: 0,
        outcome: nil,
        waiting: false
    }
  end

  @doc "A tally with nothing played."
  @spec blank_record() :: map
  def blank_record, do: %{win: 0, lose: 0, draw: 0}

  @doc "The tally with one more of `outcome`."
  @spec tally(map, :win | :lose | :draw) :: map
  def tally(record, outcome), do: Map.put(record, outcome, Map.get(record, outcome) + 1)

  @doc "A record as stored: wins, losses and draws, 32 bits each."
  @spec encode_record(map) :: binary
  def encode_record(%{win: win, lose: lose, draw: draw}), do: <<win::32, lose::32, draw::32>>

  @doc "A record from storage; anything else is a blank record."
  @spec decode_record(binary | nil) :: map
  def decode_record(<<win::32, lose::32, draw::32>>), do: %{win: win, lose: lose, draw: draw}
  def decode_record(_blob), do: blank_record()
end
