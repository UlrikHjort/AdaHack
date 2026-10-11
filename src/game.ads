-- ***************************************************************************
--                               AdaHack - Game
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

with Game_Types; use Game_Types;

-- Top-level game state and main loop
package Game is

   Max_Msg_Len : constant := 78;

   -- Two-step commands that wait for a direction next keypress
   type Pending_Cmd is (None, Kick, Fire_Bow, Confirm_Quit);

   type Game_State is record
      Player   : Player_Data;
      Level    : Dungeon;
      Message  : String (1 .. Max_Msg_Len) := (others => ' ');
      Msg_Len  : Integer    := 0;
      Pending  : Pending_Cmd := None;
   end record;

   -- Show the title screen and wait for a key
   procedure Title_Screen;
   procedure New_Game  (State : out Game_State);
   procedure Run       (State : in out Game_State);

end Game;
