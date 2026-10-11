-- ***************************************************************************
--                           AdaHack - Dungeon_Gen
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

-- Dungeon generation, FOV, and level helpers
package Dungeon_Gen is

   -- Generate a fresh dungeon level
   procedure Generate (D : out Dungeon; Depth : Integer);

   -- Recompute which tiles are currently visible from Pos.
   -- Radius defaults to 9; pass 1 when the player is blinded.
   procedure Update_FOV (D : in out Dungeon; From : Position;
                          Radius : Integer := 9);

   -- Return a random walkable floor/corridor tile
   function Random_Floor (D : Dungeon) return Position;

   -- Monster-stat factory
   function Make_Monster (K : Monster_Kind; P : Position) return Monster_Data;

end Dungeon_Gen;
