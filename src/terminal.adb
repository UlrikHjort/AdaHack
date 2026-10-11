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

with Ada.Text_IO;      use Ada.Text_IO;
with Interfaces.C;     use Interfaces.C;

package body Terminal is

   procedure C_Set_Raw_Mode;
   pragma Import (C, C_Set_Raw_Mode, "set_raw_mode");

   procedure C_Restore_Terminal;
   pragma Import (C, C_Restore_Terminal, "restore_terminal");

   function C_Read_Byte return int;
   pragma Import (C, C_Read_Byte, "read_byte");

   function C_Read_Byte_NB return int;
   pragma Import (C, C_Read_Byte_NB, "read_byte_nb");

   ESC : constant Character := Character'Val (27);

   -- Strip leading space from Integer'Image for non-negative N
   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      if N >= 0 then
         return S (S'First + 1 .. S'Last);
      else
         return S;
      end if;
   end Img;

   procedure Init is
   begin
      C_Set_Raw_Mode;
      Put (ESC & "[?25l");   -- hide cursor
      Put (ESC & "[2J");     -- clear screen
      Put (ESC & "[H");      -- home
      Flush;
   end Init;

   procedure Cleanup is
   begin
      Put (ESC & "[0m");     -- reset attrs
      Put (ESC & "[?25h");   -- show cursor
      Put (ESC & "[24;1H");  -- bottom of screen
      New_Line;
      Flush;
      C_Restore_Terminal;
   end Cleanup;

   procedure Clear_Screen is
   begin
      Put (ESC & "[2J");
      Put (ESC & "[H");
   end Clear_Screen;

   procedure Move_To (Row, Col : Integer) is
   begin
      Put (ESC & "[" & Img (Row) & ";" & Img (Col) & "H");
   end Move_To;

   procedure Put_Ch (C : Character) is
   begin
      Put (C);
   end Put_Ch;

   procedure Put_Str (S : String) is
   begin
      Put (S);
   end Put_Str;

   procedure Put_Int (N : Integer) is
   begin
      Put (Img (N));
   end Put_Int;

   procedure Set_Color (Fg : Integer; Bold : Boolean := False) is
      F : constant Integer := Fg mod 8;
      B : constant String  := (if Bold then "1" else "0");
      D : constant String  := Integer'Image (30 + F);
   begin
      Put (ESC & "[" & B & ";" & D (D'First + 1 .. D'Last) & "m");
   end Set_Color;

   procedure Reset_Attrs is
   begin
      Put (ESC & "[0m");
   end Reset_Attrs;

   procedure Flush is
   begin
      Ada.Text_IO.Flush;
   end Flush;

   function Get_Key return Key_Event is
      B  : int;
      B2 : int;
   begin
      B := C_Read_Byte;
      if B < 0 then
         return (Key_None, ' ');
      end if;

      if B = 27 then                   -- ESC
         B2 := C_Read_Byte_NB;
         if B2 = int (Character'Pos ('[')) then
            B2 := C_Read_Byte_NB;
            case Character'Val (Integer (B2)) is
               when 'A'    => return (Key_Up,    ' ');
               when 'B'    => return (Key_Down,  ' ');
               when 'C'    => return (Key_Right, ' ');
               when 'D'    => return (Key_Left,  ' ');
               when others => return (Key_Escape,' ');
            end case;
         else
            return (Key_Escape, ' ');
         end if;
      elsif B = 13 or B = 10 then      -- CR / LF
         return (Key_Enter, Character'Val (Integer (B)));
      elsif B = 32 then
         return (Key_Space, ' ');
      else
         return (Key_Char, Character'Val (Integer (B)));
      end if;
   end Get_Key;

end Terminal;
