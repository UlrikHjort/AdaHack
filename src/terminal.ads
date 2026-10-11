-- ***************************************************************************
--                             AdaHack - Terminal
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

-- Terminal: raw-mode input + ANSI output
package Terminal is

   type Key_Kind is (
      Key_Up, Key_Down, Key_Left, Key_Right,
      Key_Enter, Key_Escape, Key_Space,
      Key_Char, Key_None
   );

   type Key_Event is record
      Kind : Key_Kind;
      Ch   : Character;
   end record;

   procedure Init;
   procedure Cleanup;

   procedure Clear_Screen;
   procedure Move_To   (Row, Col : Integer);
   procedure Put_Ch    (C : Character);
   procedure Put_Str   (S : String);
   procedure Put_Int   (N : Integer);
   procedure Set_Color (Fg : Integer; Bold : Boolean := False);
   procedure Reset_Attrs;
   procedure Flush;

   function Get_Key return Key_Event;

   -- Foreground colour indices (pass to Set_Color)
   Black   : constant Integer := 0;
   Red     : constant Integer := 1;
   Green   : constant Integer := 2;
   Yellow  : constant Integer := 3;
   Blue    : constant Integer := 4;
   Magenta : constant Integer := 5;
   Cyan    : constant Integer := 6;
   White   : constant Integer := 7;

end Terminal;
