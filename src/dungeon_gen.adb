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

with Ada.Numerics.Discrete_Random;

package body Dungeon_Gen is

   -- ---------------------------------------------------------------
   -- RNG
   -- ---------------------------------------------------------------
   type Rand_Range is range 0 .. 2 ** 30 - 1;
   package RNG is new Ada.Numerics.Discrete_Random (Rand_Range);
   Gen        : RNG.Generator;
   RNG_Seeded : Boolean := False;

   procedure Ensure_Seeded is
   begin
      if not RNG_Seeded then
         RNG.Reset (Gen);
         RNG_Seeded := True;
      end if;
   end Ensure_Seeded;

   function Roll (Lo, Hi : Integer) return Integer is
      R : constant Integer := Integer (RNG.Random (Gen));
   begin
      if Hi <= Lo then return Lo; end if;
      return Lo + (R mod (Hi - Lo + 1));
   end Roll;

   -- ---------------------------------------------------------------
   -- Room type
   -- ---------------------------------------------------------------
   type Room is record
      X, Y, W, H : Integer;
   end record;

   function Center (Rm : Room) return Position is
     ((X => Rm.X + Rm.W / 2, Y => Rm.Y + Rm.H / 2));

   function Overlaps (A, B : Room) return Boolean is
   begin
      return A.X - 1 < B.X + B.W and A.X + A.W > B.X - 1
         and A.Y - 1 < B.Y + B.H and A.Y + A.H > B.Y - 1;
   end Overlaps;

   -- ---------------------------------------------------------------
   -- Tile helpers
   -- ---------------------------------------------------------------
   procedure Carve (D : in out Dungeon; X, Y : Integer; K : Tile_Kind) is
   begin
      if X in Map_Col and Y in Map_Row then
         if not (K = Corridor and D.Map (Y, X).Kind = Floor) then
            D.Map (Y, X).Kind := K;
         end if;
      end if;
   end Carve;

   procedure H_Tunnel (D : in out Dungeon; X1, X2, Y : Integer;
                        K : Tile_Kind := Corridor) is
      A : constant Integer := Integer'Min (X1, X2);
      B : constant Integer := Integer'Max (X1, X2);
   begin
      for X in A .. B loop
         Carve (D, X, Y, K);
      end loop;
   end H_Tunnel;

   procedure V_Tunnel (D : in out Dungeon; Y1, Y2, X : Integer;
                        K : Tile_Kind := Corridor) is
      A : constant Integer := Integer'Min (Y1, Y2);
      B : constant Integer := Integer'Max (Y1, Y2);
   begin
      for Y in A .. B loop
         Carve (D, X, Y, K);
      end loop;
   end V_Tunnel;

   -- ---------------------------------------------------------------
   -- FOV - simple ray-cast
   -- ---------------------------------------------------------------
   procedure Cast_Ray (D : in out Dungeon; X0, Y0, X1, Y1 : Integer) is
      Dx  : constant Integer := abs (X1 - X0);
      Dy  : constant Integer := abs (Y1 - Y0);
      Sx  : constant Integer := (if X0 < X1 then 1 else -1);
      Sy  : constant Integer := (if Y0 < Y1 then 1 else -1);
      Err : Integer          := Dx - Dy;
      X   : Integer          := X0;
      Y   : Integer          := Y0;
      E2  : Integer;
   begin
      loop
         exit when X not in Map_Col or Y not in Map_Row;
         D.Map (Y, X).Visible := True;
         D.Map (Y, X).Seen    := True;
         exit when D.Map (Y, X).Kind = Wall
                or D.Map (Y, X).Kind = Door_Secret   -- secret doors block like walls
                or D.Map (Y, X).Kind = Door_Closed
                or D.Map (Y, X).Kind = Door_Locked
                or D.Map (Y, X).Kind = Void;
         exit when X = X1 and Y = Y1;
         E2 := 2 * Err;
         if E2 > -Dy then Err := Err - Dy; X := X + Sx; end if;
         if E2 <  Dx then Err := Err + Dx; Y := Y + Sy; end if;
      end loop;
   end Cast_Ray;

   procedure Update_FOV (D : in out Dungeon; From : Position;
                          Radius : Integer := 9) is
   begin
      for Y in Map_Row loop
         for X in Map_Col loop
            D.Map (Y, X).Visible := False;
         end loop;
      end loop;
      for I in -Radius .. Radius loop
         Cast_Ray (D, From.X, From.Y, From.X + I,        From.Y - Radius);
         Cast_Ray (D, From.X, From.Y, From.X + I,        From.Y + Radius);
         Cast_Ray (D, From.X, From.Y, From.X - Radius,   From.Y + I);
         Cast_Ray (D, From.X, From.Y, From.X + Radius,   From.Y + I);
      end loop;
   end Update_FOV;

   -- ---------------------------------------------------------------
   -- Monster factory
   -- ---------------------------------------------------------------
   function Make_Monster (K : Monster_Kind; P : Position) return Monster_Data is
      M : Monster_Data;
   begin
      M.Kind := K; M.Pos := P; M.Alive := True; M.Asleep := True;
      M.Regen_Ticks := 0;
      case K is
         when Rat        => M.HP:=4;  M.Max_HP:=4;  M.Attack:=1; M.Defense:=0; M.Dmg_Min:=1; M.Dmg_Max:=3; M.XP_Value:=5;   M.Symbol:='r';
         when Bat        => M.HP:=3;  M.Max_HP:=3;  M.Attack:=1; M.Defense:=0; M.Dmg_Min:=1; M.Dmg_Max:=2; M.XP_Value:=4;   M.Symbol:='B';
         when Goblin     => M.HP:=8;  M.Max_HP:=8;  M.Attack:=2; M.Defense:=1; M.Dmg_Min:=1; M.Dmg_Max:=4; M.XP_Value:=15;  M.Symbol:='g';
         when Orc        => M.HP:=14; M.Max_HP:=14; M.Attack:=3; M.Defense:=1; M.Dmg_Min:=2; M.Dmg_Max:=6; M.XP_Value:=30;  M.Symbol:='o';
         when Troll      => M.HP:=22; M.Max_HP:=22; M.Attack:=5; M.Defense:=2; M.Dmg_Min:=3; M.Dmg_Max:=9; M.XP_Value:=60;  M.Symbol:='T';
         when Dragon     => M.HP:=40; M.Max_HP:=40; M.Attack:=8; M.Defense:=4; M.Dmg_Min:=4; M.Dmg_Max:=12; M.XP_Value:=200; M.Symbol:='D';
         when No_Monster => null;
      end case;
      return M;
   end Make_Monster;

   -- ---------------------------------------------------------------
   -- Random floor helpers
   -- ---------------------------------------------------------------
   function Random_Floor (D : Dungeon) return Position is
      P : Position;
   begin
      for Attempt in 1 .. 2000 loop
         P := (X => Roll (1, Map_Width), Y => Roll (1, Map_Height));
         if D.Map (P.Y, P.X).Kind = Floor then
            return P;
         end if;
      end loop;
      return (1, 1);
   end Random_Floor;

   function Random_Floor_In_Room (D : Dungeon; Rm : Room) return Position is
      P : Position;
   begin
      for Attempt in 1 .. 200 loop
         P := (X => Roll (Rm.X + 1, Rm.X + Rm.W - 2),
               Y => Roll (Rm.Y + 1, Rm.Y + Rm.H - 2));
         if D.Map (P.Y, P.X).Kind = Floor then
            return P;
         end if;
      end loop;
      return Random_Floor (D);
   end Random_Floor_In_Room;

   procedure Add_Item (D : in out Dungeon; It : Item_Data) is
   begin
      for I in 1 .. Max_Items loop
         if not D.Items (I).Present then
            D.Items (I) := It;
            return;
         end if;
      end loop;
   end Add_Item;

   -- ---------------------------------------------------------------
   -- Generate dungeon
   -- ---------------------------------------------------------------
   Max_Rooms    : constant := 10;
   Min_Room_Dim : constant := 4;
   Max_Room_Dim : constant := 10;

   procedure Generate (D : out Dungeon; Depth : Integer) is
      Rooms      : array (1 .. Max_Rooms) of Room;
      Room_Count : Integer := 0;

      type Conn_Info is record
         Door_Pos : Position;
         Valid    : Boolean;
      end record;
      Conns : array (1 .. Max_Rooms - 1) of Conn_Info;

      type Opt_Pos is record
         Pos   : Position;
         Found : Boolean;
      end record;
      No_Door : constant Opt_Pos := (Pos => (1, 1), Found => False);

      function Wall_Like (X, Y : Integer) return Boolean is
      begin
         if not (X in Map_Col and then Y in Map_Row) then return True; end if;
         return D.Map (Y, X).Kind = Wall
            or else D.Map (Y, X).Kind = Void
            or else D.Map (Y, X).Kind = Door_Secret;
      end Wall_Like;

      function Flanked_By_Walls (X, Y : Integer; Horiz : Boolean) return Boolean is
      begin
         if Horiz then
            return Wall_Like (X, Y - 1) and then Wall_Like (X, Y + 1);
         else
            return Wall_Like (X - 1, Y) and then Wall_Like (X + 1, Y);
         end if;
      end Flanked_By_Walls;

      function Exit_Tile (Rm : Room; C : Position; Target : Position;
                           Horiz : Boolean) return Opt_Pos is
         X, Y : Integer;
      begin
         if Horiz then
            Y := C.Y;
            X := (if Target.X >= C.X then Rm.X + Rm.W else Rm.X - 1);
         else
            X := C.X;
            Y := (if Target.Y >= C.Y then Rm.Y + Rm.H else Rm.Y - 1);
         end if;
         if X in Map_Col and then Y in Map_Row
            and then D.Map (Y, X).Kind = Corridor
            and then Flanked_By_Walls (X, Y, Horiz)
         then
            return (Pos => (X => X, Y => Y), Found => True);
         end if;
         return No_Door;
      end Exit_Tile;

      function Entry_Tile (Rm : Room; C : Position; From : Position;
                            Horiz : Boolean) return Opt_Pos is
         X, Y : Integer;
      begin
         if Horiz then
            Y := C.Y;
            X := (if C.X >= From.X then Rm.X - 1 else Rm.X + Rm.W);
         else
            X := C.X;
            Y := (if C.Y >= From.Y then Rm.Y - 1 else Rm.Y + Rm.H);
         end if;
         if X in Map_Col and then Y in Map_Row
            and then D.Map (Y, X).Kind = Corridor
            and then Flanked_By_Walls (X, Y, Horiz)
         then
            return (Pos => (X => X, Y => Y), Found => True);
         end if;
         return No_Door;
      end Entry_Tile;

      procedure Try_Add_Room is
         W  : constant Integer := Roll (Min_Room_Dim, Max_Room_Dim);
         H  : constant Integer := Roll (Min_Room_Dim, Max_Room_Dim);
         X  : constant Integer := Roll (2, Map_Width  - W - 1);
         Y  : constant Integer := Roll (2, Map_Height - H - 1);
         Nr : constant Room    := (X, Y, W, H);
      begin
         for I in 1 .. Room_Count loop
            if Overlaps (Nr, Rooms (I)) then return; end if;
         end loop;
         Room_Count := Room_Count + 1;
         Rooms (Room_Count) := Nr;

         -- Carve floor
         for Ry in Y .. Y + H - 1 loop
            for Rx in X .. X + W - 1 loop
               Carve (D, Rx, Ry, Floor);
            end loop;
         end loop;

         -- Mark room as dark (chance increases with depth)
         declare
            Dark_Chance : constant Integer :=
               (if Depth >= 7 then 60
                elsif Depth >= 5 then 40
                elsif Depth >= 3 then 20
                else 5);
         begin
            if Roll (1, 100) <= Dark_Chance then
               for Ry in Y .. Y + H - 1 loop
                  for Rx in X .. X + W - 1 loop
                     if D.Map (Ry, Rx).Kind = Floor then
                        D.Map (Ry, Rx).Is_Dark := True;
                     end if;
                  end loop;
               end loop;
            end if;
         end;

         -- Connect to previous room
         if Room_Count > 1 then
            declare
               C1      : constant Position := Center (Rooms (Room_Count - 1));
               C2      : constant Position := Center (Nr);
               H_First : constant Boolean  := (Roll (0, 1) = 0);
               CI      : constant Integer  := Room_Count - 1;
               R1, R2  : Opt_Pos;
               Best    : Opt_Pos;
            begin
               if H_First then
                  H_Tunnel (D, C1.X, C2.X, C1.Y);
                  V_Tunnel (D, C1.Y, C2.Y, C2.X);
                  R1 := Exit_Tile  (Rooms (CI), C1, C2, Horiz => True);
                  R2 := Entry_Tile (Nr, C2, From => (X => C2.X, Y => C1.Y),
                                    Horiz => False);
               else
                  V_Tunnel (D, C1.Y, C2.Y, C1.X);
                  H_Tunnel (D, C1.X, C2.X, C2.Y);
                  R1 := Entry_Tile (Nr, C2, From => (X => C1.X, Y => C2.Y),
                                    Horiz => True);
                  R2 := Exit_Tile  (Rooms (CI), C1, C2, Horiz => False);
               end if;

               Best := (if R1.Found then R1 else R2);
               Conns (CI) := (Door_Pos => Best.Pos, Valid => Best.Found);
            end;
         end if;
      end Try_Add_Room;

      Next_Lock_ID : Integer := 1;

   begin
      Ensure_Seeded;

      -- Blank the dungeon
      D.Map        := (others => (others => (Kind       => Void,
                                             Lock_ID    => 0,
                                             Seen       => False,
                                             Visible    => False,
                                             Is_Dark    => False,
                                             Trap_Known => False)));
      D.Items      := (others => (No_Item, (1, 1), 0, False));
      D.Monsters   := (others => (Kind        => No_Monster,
                                  Pos         => (1, 1),
                                  HP          => 0,
                                  Max_HP      => 0,
                                  Attack      => 0,
                                  Defense     => 0,
                                  Dmg_Min     => 1,
                                  Dmg_Max     => 1,
                                  XP_Value    => 0,
                                  Symbol      => '?',
                                  Alive       => False,
                                  Asleep      => True,
                                  Regen_Ticks => 0));
      D.Shop_Stock := (others => (It => (No_Item, (1, 1), 0, False),
                                  Price => 0,
                                  Sold  => False));
      D.Has_Shop   := False;

      -- Fill with walls
      for Y in Map_Row loop
         for X in Map_Col loop
            D.Map (Y, X) := (Kind       => Wall,
                             Lock_ID    => 0,
                             Seen       => False,
                             Visible    => False,
                             Is_Dark    => False,
                             Trap_Known => False);
         end loop;
      end loop;

      -- Carve rooms + corridors
      for Attempt in 1 .. Max_Rooms * 4 loop
         exit when Room_Count >= Max_Rooms;
         Try_Add_Room;
      end loop;

      -- ---------------------------------------------------------------
      -- Place doors with flanking re-check at placement time
      -- ---------------------------------------------------------------
      for I in 1 .. Room_Count - 1 loop
         if Conns (I).Valid then
            declare
               DP : constant Position := Conns (I).Door_Pos;
               Still_OK : constant Boolean :=
                  (Wall_Like (DP.X, DP.Y - 1) and then Wall_Like (DP.X, DP.Y + 1))
                  or else
                  (Wall_Like (DP.X - 1, DP.Y) and then Wall_Like (DP.X + 1, DP.Y));
            begin
               if D.Map (DP.Y, DP.X).Kind = Corridor and then Still_OK then
                  declare
                     Door_Roll  : constant Integer := Roll (1, 5);
                     Lock_Roll  : constant Integer := Roll (1, 4);
                     Place_Door : constant Boolean := Door_Roll <= 2;
                     Place_Lock : constant Boolean :=
                        Place_Door and I >= 2 and Lock_Roll = 1
                        and Next_Lock_ID <= Max_Keys;
                  begin
                     if Place_Lock then
                        D.Map (DP.Y, DP.X) :=
                           (Kind => Door_Locked, Lock_ID => Next_Lock_ID,
                            Seen => False, Visible => False,
                            Is_Dark => False, Trap_Known => False);
                        declare
                           Key_Room : constant Integer := Roll (1, I);
                           KP : constant Position :=
                              Random_Floor_In_Room (D, Rooms (Key_Room));
                        begin
                           Add_Item (D, (Key, KP, Next_Lock_ID, True));
                        end;
                        Next_Lock_ID := Next_Lock_ID + 1;
                     elsif Place_Door then
                        D.Map (DP.Y, DP.X) :=
                           (Kind => Door_Closed, Lock_ID => 0,
                            Seen => False, Visible => False,
                            Is_Dark => False, Trap_Known => False);
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;

      -- ---------------------------------------------------------------
      -- Secret doors: scan for wall tiles flanked by open space on two
      -- opposite sides (genuine wall crossing with no normal door).
      -- ---------------------------------------------------------------
      -- Skip the map border (Y=1/Max, X=1/Max) to avoid out-of-bounds neighbours
      for Y in Map_Row'First + 1 .. Map_Row'Last - 1 loop
         for X in Map_Col'First + 1 .. Map_Col'Last - 1 loop
            if D.Map (Y, X).Kind = Wall then
               declare
                  H_Cross : constant Boolean :=
                     Is_Walkable (D.Map (Y, X - 1).Kind) and then
                     Is_Walkable (D.Map (Y, X + 1).Kind);
                  V_Cross : constant Boolean :=
                     Is_Walkable (D.Map (Y - 1, X).Kind) and then
                     Is_Walkable (D.Map (Y + 1, X).Kind);
               begin
                  if (H_Cross or else V_Cross) and then Roll (1, 100) <= 8 then
                     D.Map (Y, X).Kind := Door_Secret;
                  end if;
               end;
            end if;
         end loop;
      end loop;

      -- Stairs down
      declare
         P : constant Position := Random_Floor (D);
      begin
         D.Map (P.Y, P.X).Kind := Stairs_Down;
      end;

      -- Stairs up (levels > 1 only)
      if Depth > 1 then
         declare
            P : constant Position := Random_Floor (D);
         begin
            D.Map (P.Y, P.X).Kind := Stairs_Up;
         end;
      end if;

      -- ---------------------------------------------------------------
      -- Traps: 1 to (1 + Depth/2) random traps
      -- ---------------------------------------------------------------
      declare
         Trap_Kinds : constant array (1 .. 4) of Tile_Kind :=
            (Trap_Teleport, Trap_Dart, Trap_Pit, Trap_Blind);
         Num_Traps  : constant Integer := Roll (1, 1 + Depth / 2);
      begin
         for I in 1 .. Num_Traps loop
            declare
               P : constant Position := Random_Floor (D);
               K : constant Tile_Kind := Trap_Kinds (Roll (1, 4));
            begin
               if D.Map (P.Y, P.X).Kind = Floor then
                  D.Map (P.Y, P.X).Kind := K;
               end if;
            end;
         end loop;
      end;

      -- ---------------------------------------------------------------
      -- Shop: 70% chance, room 2+, center tile
      -- ---------------------------------------------------------------
      if Room_Count >= 2 and then Roll (1, 10) <= 7 then
         declare
            SR : constant Room     := Rooms (Roll (2, Room_Count));
            SP : constant Position := Center (SR);
         begin
            if D.Map (SP.Y, SP.X).Kind = Floor then
               D.Map (SP.Y, SP.X).Kind := Shop;
               D.Has_Shop              := True;

               for I in 1 .. Max_Shop_Items loop
                  declare
                     R     : constant Integer := Roll (1, 9);
                     K     : Item_Kind        := Food;
                     V     : Integer          := 0;
                     Price : Integer          := 12;
                  begin
                     case R is
                        when 1 =>
                           K := Potion_Heal; V := Roll (8, 14);
                           Price := 30;
                        when 2 =>
                           K := Potion_Str;
                           Price := 65;
                        when 3 =>
                           K := Weapon; V := Roll (1, 1 + Depth);
                           Price := 20 + V * 25;
                        when 4 =>
                           K := Armor; V := Roll (1, Depth);
                           Price := 20 + V * 20;
                        when 5 =>
                           K := Food;
                           Price := 12;
                        when 6 =>
                           K := Ring; V := Roll (1, 4);
                           Price := 100 + V * 75;
                        when 7 =>
                           K := Potion_Invis; V := Roll (40, 80);
                           Price := 50;
                        when 8 =>
                           K := Scroll_Identify;
                           Price := 40;
                        when others =>
                           K := Torch; V := Roll (200, 500);
                           Price := 20;
                     end case;
                     D.Shop_Stock (I) :=
                        (It => (K, SP, V, True), Price => Price, Sold => False);
                  end;
               end loop;
            end if;
         end;
      end if;

      -- ---------------------------------------------------------------
      -- Regular items
      -- ---------------------------------------------------------------
      declare
         Num_Items : constant Integer := Roll (4, 9);
         P         : Position;
      begin
         for I in 1 .. Num_Items loop
            P := Random_Floor (D);
            declare
               R  : constant Integer := Roll (1, 14);
               K  : Item_Kind        := No_Item;
               V  : Integer          := 0;
            begin
               if R <= 3 then
                  K := Gold;
                  V := Roll (5, 50 * Depth);

               elsif R <= 5 then
                  K := Food;

               elsif R <= 7 then
                  -- Potions
                  declare
                     PT : constant Integer := Roll (1, 20);
                  begin
                     if PT <= 7 then
                        K := Potion_Heal;   V := Roll (6, 12);
                     elsif PT <= 11 then
                        K := Potion_Str;
                     elsif PT <= 14 then
                        K := Potion_Poison; V := Roll (5, 15);
                     elsif PT <= 17 then
                        K := Potion_Blind;  V := Roll (8, 20);
                     else
                        K := Potion_Invis;  V := Roll (40, 80);
                     end if;
                  end;

               elsif R <= 8 then
                  -- Scrolls
                  declare
                     ST : constant Integer := Roll (1, 6);
                  begin
                     case ST is
                        when 1 => K := Scroll_Identify;
                        when 2 => K := Scroll_Magic_Map;
                        when 3 => K := Scroll_Fireball;
                        when 4 => K := Scroll_Enchant_Weapon;
                        when 5 => K := Scroll_Enchant_Armor;
                        when others => K := Scroll_Teleport;
                     end case;
                  end;

               elsif R <= 9 then
                  -- Weapon
                  K := Weapon;
                  declare
                     Q : constant Integer := Roll (1, 10);
                  begin
                     if    Q <= 2 then V := -(Roll (1, 2));
                     elsif Q <= 5 then V := 0;
                     elsif Q <= 8 then V := Roll (1, 1 + Depth);
                     else               V := Roll (2, 2 + Depth);
                     end if;
                  end;

               elsif R <= 10 then
                  -- Armor
                  K := Armor;
                  declare
                     Q : constant Integer := Roll (1, 10);
                  begin
                     if    Q <= 2 then V := -(Roll (1, 1));
                     elsif Q <= 5 then V := 0;
                     elsif Q <= 8 then V := Roll (1, Depth);
                     else               V := Roll (1, 1 + Depth);
                     end if;
                  end;

               elsif R <= 11 then
                  -- Torch
                  K := Torch; V := Roll (150, 400);

               elsif R <= 12 then
                  -- Bow
                  K := Bow; V := Roll (0, Depth);

               elsif R <= 13 then
                  -- Arrows
                  K := Arrow; V := Roll (5, 20);

               else
                  -- Ring (rare)
                  K := Ring; V := Roll (1, 4);
               end if;

               if K /= No_Item then
                  Add_Item (D, (K, P, V, True));
               end if;
            end;
         end loop;
      end;

      -- ---------------------------------------------------------------
      -- Amulet of Yendor on level 10
      -- ---------------------------------------------------------------
      if Depth = 10 then
         Add_Item (D, (Amulet_Yendor, Random_Floor (D), 0, True));
      end if;

      -- ---------------------------------------------------------------
      -- Monsters
      -- ---------------------------------------------------------------
      declare
         Num_Mon : constant Integer := Roll (2 + Depth, 4 + Depth * 2);
         Actual  : constant Integer := Integer'Min (Num_Mon, Max_Monsters);
         P       : Position;
      begin
         for I in 1 .. Actual loop
            P := Random_Floor (D);
            declare
               R : constant Integer := Roll (1, 20);
               K : Monster_Kind;
            begin
               if    Depth = 1  and R <= 12 then K := Rat;
               elsif Depth = 1              then K := Bat;
               elsif Depth = 2  and R <=  8 then K := Goblin;
               elsif Depth = 2              then K := Orc;
               elsif Depth <= 4 and R <=  6 then K := Orc;
               elsif Depth <= 4 and R <= 14 then K := Troll;
               elsif Depth <= 7             then K := Troll;
               else                              K := Dragon;
               end if;
               D.Monsters (I) := Make_Monster (K, P);
            end;
         end loop;
      end;

   end Generate;

end Dungeon_Gen;
