defmodule Badge.App.Sokoban.Levels do
  @moduledoc """
  Levels 1-20 of Microban by David W. Skinner, as XSB text.

  `get/1` takes a 1-based level number.
  """

  @levels ~S"""
          Level 1
          ####
          # .#
          #  ###
          #*@  #
          #  $ #
          #  ###
          ####

          Level 2
          ######
          #    #
          # #@ #
          # $* #
          # .* #
          #    #
          ######

          Level 3
            ####
          ###  ####
          #     $ #
          # #  #$ #
          # . .#@ #
          #########

          Level 4
          ########
          #      #
          # .**$@#
          #      #
          #####  #
              ####

          Level 5
           #######
           #     #
           # .$. #
          ## $@$ #
          #  .$. #
          #      #
          ########

          Level 6
          ###### #####
          #    ###   #
          # $$     #@#
          # $ #...   #
          #   ########
          #####

          Level 7
          #######
          #     #
          # .$. #
          # $.$ #
          # .$. #
          # $.$ #
          #  @  #
          #######

          Level 8
            ######
            # ..@#
            # $$ #
            ## ###
             # #
             # #
          #### #
          #    ##
          # #   #
          #   # #
          ###   #
            #####

          Level 9
          #####
          #.  ##
          #@$$ #
          ##   #
           ##  #
            ##.#
             ###

          Level 10
                #####
                #.  #
                #.# #
          #######.# #
          # @ $ $ $ #
          # # # # ###
          #       #
          #########

          Level 11
            ######
            #    #
            # ##@##
          ### # $ #
          # ..# $ #
          #       #
          #  ######
          ####

          Level 12
          #####
          #   ##
          # $  #
          ## $ ####
           ###@.  #
            #  .# #
            #     #
            #######

          Level 13
          ####
          #. ##
          #.@ #
          #. $#
          ##$ ###
           # $  #
           #    #
           #  ###
           ####

          Level 14
          #######
          #     #
          # # # #
          #. $*@#
          #   ###
          #####

          Level 15
               ###
          ######@##
          #    .* #
          #   #   #
          #####$# #
              #   #
              #####

          Level 16
           ####
           #  ####
           #     ##
          ## ##   #
          #. .# @$##
          #   # $$ #
          #  .#    #
          ##########

          Level 17
          #####
          # @ #
          #...#
          #$$$##
          #    #
          #    #
          ######

          Level 18
          #######
          #     #
          #. .  #
          # ## ##
          #  $ #
          ###$ #
            #@ #
            #  #
            ####

          Level 19
          ########
          #   .. #
          #  @$$ #
          ##### ##
             #  #
             #  #
             #  #
             ####

          Level 20
          #######
          #     ###
          #  @$$..#
          #### ## #
            #     #
            #  ####
            #  #
            ####
          """
          |> String.split(~r/^Level \d+\n/m, trim: true)
          |> Enum.map(&String.trim_trailing(&1, "\n"))

  @count length(@levels)

  @doc "How many levels there are."
  def count, do: @count

  @doc "The XSB text of level `n`, counting from 1."
  @spec get(pos_integer) :: binary
  def get(n)

  for {xsb, n} <- Enum.with_index(@levels, 1) do
    def get(unquote(n)), do: unquote(xsb)
  end
end
