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

with Terminal;    use Terminal;
with Dungeon_Gen; use Dungeon_Gen;
with Ada.Numerics.Discrete_Random;

package body Game is

   -- ---------------------------------------------------------------
   -- Internal RNG (for combat dice)
   -- ---------------------------------------------------------------
   type D20_Range is range 1 .. 20;
   package D20 is new Ada.Numerics.Discrete_Random (D20_Range);
   Combat_Gen : D20.Generator;

   function Roll_D20 return Integer is (Integer (D20.Random (Combat_Gen)));

   type Ring_Life_Range is range 80 .. 200;
   package Ring_Life_RNG is new Ada.Numerics.Discrete_Random (Ring_Life_Range);
   Ring_Life_Gen : Ring_Life_RNG.Generator;

   function Roll_Ring_Life return Integer is
     (Integer (Ring_Life_RNG.Random (Ring_Life_Gen)));

   package Dice_RNG is new Ada.Numerics.Discrete_Random (Natural);
   Dice_Gen : Dice_RNG.Generator;

   -- Uniform roll in Lo .. Hi
   function Roll (Lo, Hi : Integer) return Integer is
     (if Hi <= Lo then Lo
      else Lo + Dice_RNG.Random (Dice_Gen) mod (Hi - Lo + 1));

   -- ---------------------------------------------------------------
   -- Messaging
   -- ---------------------------------------------------------------
   procedure Set_Msg (State : in out Game_State; S : String) is
      Len : constant Integer := Integer'Min (S'Length, Max_Msg_Len);
   begin
      State.Message (1 .. Len) := S (S'First .. S'First + Len - 1);
      State.Message (Len + 1 .. Max_Msg_Len) := (others => ' ');
      State.Msg_Len := Len;
   end Set_Msg;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N >= 0 then S (S'First + 1 .. S'Last) else S);
   end Img;

   -- Short description of an item
   function Item_Name (It : Item_Data) return String is
   begin
      case It.Kind is
         when Gold =>
            return Img (It.Value) & " gold pieces";

         when Potion_Heal =>
            return "blue potion [+" & Img (It.Value) & " HP]";
         when Potion_Str =>
            return "red potion [+1 atk forever]";
         when Potion_Poison =>
            return "foul-smelling potion";   -- effect hidden until drunk
         when Potion_Blind =>
            return "murky potion";           -- effect hidden until drunk
         when Potion_Invis =>
            return "sparkling potion";       -- effect hidden until drunk

         when Scroll_Identify       => return "scroll of identify";
         when Scroll_Magic_Map      => return "scroll of magic mapping";
         when Scroll_Fireball       => return "scroll of fireball";
         when Scroll_Enchant_Weapon => return "scroll of enchant weapon";
         when Scroll_Enchant_Armor  => return "scroll of enchant armor";
         when Scroll_Teleport       => return "scroll of teleportation";

         when Bow =>
            return (if It.Value > 0
                    then "fine bow [+" & Img (It.Value) & " acc]"
                    else "short bow [+0 acc]");
         when Arrow =>
            return Img (It.Value) & " arrows";
         when Torch =>
            return "torch [" & Img (It.Value) & " turns]";
         when Amulet_Yendor =>
            return "Amulet of Yendor";

         when Weapon =>
            if    It.Value <= -2 then return "broken weapon ["  & Img (It.Value) & " atk]";
            elsif It.Value =  -1 then return "cursed blade [-1 atk]";
            elsif It.Value =   0 then return "dagger [+0 atk]";
            elsif It.Value =   1 then return "short sword [+1 atk]";
            elsif It.Value =   2 then return "long sword [+2 atk]";
            elsif It.Value =   3 then return "war sword [+3 atk]";
            else                       return "great sword [+" & Img (It.Value) & " atk]";
            end if;

         when Armor =>
            if    It.Value <  0 then return "cursed scraps ["  & Img (It.Value) & " def]";
            elsif It.Value =  0 then return "leather jerkin [+0 def]";
            elsif It.Value =  1 then return "chainmail [+1 def]";
            elsif It.Value =  2 then return "plate armor [+2 def]";
            else                      return "full plate [+" & Img (It.Value) & " def]";
            end if;

         when Food =>
            return "food ration";

         when Key =>
            return "key #" & Img (It.Value);

         when Ring =>
            case It.Value is
               when 1 => return "ring of regeneration";
               when 2 => return "ring of invisibility";
               when 3 => return "ring of speed";
               when 4 => return "ring of teleportation";
               when others => return "strange ring";
            end case;

         when No_Item =>
            return "nothing";
      end case;
   end Item_Name;

   -- ---------------------------------------------------------------
   -- XP & levelling
   -- ---------------------------------------------------------------
   procedure Add_XP (State : in out Game_State; Amount : Integer) is
      P : Player_Data renames State.Player;
   begin
      P.XP := P.XP + Amount;
      if P.XP >= P.XP_Next then
         P.Level         := P.Level + 1;
         P.XP_Next       := P.XP_Next * 2;
         P.Max_HP        := P.Max_HP + 5 + Roll_D20 mod 4;
         P.HP            := P.Max_HP;
         P.Base_Attack   := P.Base_Attack + 1;
         P.Base_Defense  := P.Base_Defense + 1;
         Set_Msg (State, "Welcome to level " & Img (P.Level) & "!");
      end if;
   end Add_XP;

   -- ---------------------------------------------------------------
   -- Combat
   -- ---------------------------------------------------------------
   -- To-hit roll: d20 + attack must reach 10 + defense.
   -- A natural 20 always hits, a natural 1 always misses.
   function Attack_Hits (Attack, Defense : Integer) return Boolean is
      R : constant Integer := Roll_D20;
   begin
      if R = 20 then return True; end if;
      if R = 1  then return False; end if;
      return R + Attack >= 10 + Defense;
   end Attack_Hits;

   function Player_Total_Attack (P : Player_Data) return Integer is
     (P.Base_Attack + P.Weapon_Bonus + P.Ring_Atk_Bon);

   function Player_Total_Defense (P : Player_Data) return Integer is
     (P.Base_Defense + P.Armor_Bonus);

   -- Melee damage on a hit: 1d6 + weapon bonus, at least 1
   function Player_Damage (P : Player_Data) return Integer is
     (Integer'Max (1, Roll (1, 6) + P.Weapon_Bonus));

   function Monster_Damage (M : Monster_Data) return Integer is
     (Roll (M.Dmg_Min, M.Dmg_Max));

   procedure Attack_Monster (State : in out Game_State; Idx : Integer) is
      M   : Monster_Data renames State.Level.Monsters (Idx);
      Dmg : Integer;
   begin
      M.Asleep := False;
      if not Attack_Hits (Player_Total_Attack (State.Player), M.Defense) then
         Set_Msg (State, "You miss the " & M.Symbol & ".");
         return;
      end if;
      Dmg := Player_Damage (State.Player);
      M.HP := M.HP - Dmg;
      if M.HP <= 0 then
         M.Alive := False;
         Set_Msg (State, "You kill the " & M.Symbol & "! +" & Img (M.XP_Value) & " XP");
         Add_XP (State, M.XP_Value);
      else
         Set_Msg (State, "You hit the " & M.Symbol & " for " & Img (Dmg) & " damage.");
      end if;
   end Attack_Monster;

   procedure Monster_Hits_Player (State : in out Game_State; Idx : Integer) is
      M   : Monster_Data renames State.Level.Monsters (Idx);
      P   : Player_Data  renames State.Player;
      Dmg : Integer;
   begin
      if not Attack_Hits (M.Attack, Player_Total_Defense (P)) then
         Set_Msg (State, "The " & (1 => M.Symbol) & " misses you.");
         return;
      end if;
      Dmg := Monster_Damage (M);
      P.HP := P.HP - Dmg;
      if P.HP <= 0 then
         P.Alive := False;
         Set_Msg (State, "The " & (1 => M.Symbol) & " kills you!");
      else
         Set_Msg (State, "The " & (1 => M.Symbol) & " hits you for "
                  & Img (Dmg) & " damage.");
         -- Bat: 25% chance to blind on hit
         if M.Kind = Bat and then Roll_D20 >= 16 then
            declare
               Dur : constant Integer := Roll_D20 mod 6 + 3;
            begin
               P.Blind_Turns := P.Blind_Turns + Dur;
               Set_Msg (State, "The B scratches near your eyes!  "
                        & "You are blinded for " & Img (Dur) & " turns!");
            end;
         end if;
      end if;
   end Monster_Hits_Player;

   -- ---------------------------------------------------------------
   -- Noise: wake monsters within Radius of Pos
   -- ---------------------------------------------------------------
   procedure Wake_Nearby (State : in out Game_State;
                           Pos    : Position;
                           Radius : Integer) is
   begin
      for I in 1 .. Max_Monsters loop
         declare
            M : Monster_Data renames State.Level.Monsters (I);
         begin
            if M.Alive and then
               Integer'Max (abs (M.Pos.X - Pos.X),
                             abs (M.Pos.Y - Pos.Y)) <= Radius
            then
               M.Asleep := False;
            end if;
         end;
      end loop;
   end Wake_Nearby;

   -- ---------------------------------------------------------------
   -- Inventory helpers
   -- ---------------------------------------------------------------

   -- Add item to the first free inventory slot; show message if full.
   -- Returns True on success.
   function Add_To_Inv (State : in out Game_State; It : Item_Data) return Boolean is
      P : Player_Data renames State.Player;
   begin
      for I in 1 .. Max_Inv loop
         if P.Inv (I).Kind = No_Item then
            P.Inv (I)     := It;
            P.Inv_Count   := P.Inv_Count + 1;
            return True;
         end if;
      end loop;
      Set_Msg (State, "Your pack is full!  Drop something first.");
      return False;
   end Add_To_Inv;

   -- Remove item from slot, unequip if necessary.
   procedure Remove_From_Inv (State : in out Game_State; Slot : Integer) is
      P : Player_Data renames State.Player;
   begin
      if P.Weapon_Slot = Slot then
         P.Weapon_Slot  := 0;
         P.Weapon_Bonus := 0;
      end if;
      if P.Armor_Slot = Slot then
         P.Armor_Slot  := 0;
         P.Armor_Bonus := 0;
      end if;
      if P.Ring_Slot = Slot then
         P.Ring_Slot    := 0;
         P.Ring_Atk_Bon := 0;
         P.Invisible    := P.Invis_Turns > 0;  -- potion may still be active
         P.Regen_Ticks  := 0;
         P.Ring_Turns   := 0;
      end if;
      if P.Bow_Slot   = Slot then P.Bow_Slot   := 0; end if;
      if P.Torch_Slot = Slot then P.Torch_Slot := 0; end if;
      P.Inv (Slot) := (No_Item, (1, 1), 0, False);
      P.Inv_Count  := P.Inv_Count - 1;
   end Remove_From_Inv;

   -- Use (equip/eat/drink) the item in Slot.
   procedure Use_Inv_Item (State : in out Game_State; Slot : Integer) is
      P  : Player_Data renames State.Player;
      It : Item_Data   renames P.Inv (Slot);
   begin
      case It.Kind is
         -- ---- Weapon: wield / put away ----
         when Weapon =>
            if P.Weapon_Slot = Slot then
               P.Weapon_Slot  := 0;
               P.Weapon_Bonus := 0;
               Set_Msg (State, "You put away the " & Item_Name (It) & ".");
            else
               P.Weapon_Slot  := Slot;
               P.Weapon_Bonus := It.Value;
               if It.Value < 0 then
                  Set_Msg (State, "You wield the " & Item_Name (It)
                           & ". It feels wrong...");
               else
                  Set_Msg (State, "You wield the " & Item_Name (It) & ".");
               end if;
            end if;

         -- ---- Armor: wear / take off ----
         when Armor =>
            if P.Armor_Slot = Slot then
               P.Armor_Slot  := 0;
               P.Armor_Bonus := 0;
               Set_Msg (State, "You take off the " & Item_Name (It) & ".");
            else
               P.Armor_Slot  := Slot;
               P.Armor_Bonus := It.Value;
               if It.Value < 0 then
                  Set_Msg (State, "You wear the " & Item_Name (It)
                           & ". It chafes horribly...");
               else
                  Set_Msg (State, "You wear the " & Item_Name (It) & ".");
               end if;
            end if;

         -- ---- Ring: put on / remove ----
         when Ring =>
            if P.Ring_Slot = Slot then
               -- Remove
               P.Ring_Slot    := 0;
               P.Ring_Atk_Bon := 0;
               P.Invisible    := P.Invis_Turns > 0;  -- potion may still be active
               P.Regen_Ticks  := 0;
               P.Ring_Turns   := 0;
               Set_Msg (State, "You remove the " & Item_Name (It) & ".");
            else
               -- Unequip old ring if any
               if P.Ring_Slot /= 0 then
                  P.Ring_Atk_Bon := 0;
                  P.Invisible    := P.Invis_Turns > 0;
                  P.Regen_Ticks  := 0;
                  P.Ring_Turns   := 0;
               end if;
               P.Ring_Slot  := Slot;
               P.Ring_Turns := Roll_Ring_Life;
               case It.Value is
                  when 1 =>
                     P.Regen_Ticks := 0;
                     Set_Msg (State,
                        "You put on the ring of regeneration. You feel tougher.");
                  when 2 =>
                     P.Invisible := True;
                     Set_Msg (State,
                        "You put on the ring of invisibility. You feel unseen!");
                  when 3 =>
                     P.Ring_Atk_Bon := 2;
                     Set_Msg (State,
                        "You put on the ring of speed. You feel quicker! (+2 atk)");
                  when 4 =>
                     Set_Msg (State,
                        "You put on the ring of teleportation. Press 't' to teleport.");
                  when others =>
                     Set_Msg (State,
                        "You put on a strange ring. Nothing seems to happen.");
               end case;
            end if;

         -- ---- Potions ----
         when Potion_Heal =>
            P.HP := Integer'Min (P.Max_HP, P.HP + It.Value);
            Set_Msg (State, "You quaff the blue potion. +" & Img (It.Value) & " HP!");
            Remove_From_Inv (State, Slot);

         when Potion_Str =>
            P.Base_Attack := P.Base_Attack + 1;
            Set_Msg (State,
               "You quaff the red potion. You feel stronger! (Base_Atk now "
               & Img (P.Base_Attack) & ")");
            Remove_From_Inv (State, Slot);

         when Potion_Poison =>
            declare
               Dmg : constant Integer := It.Value;
            begin
               P.HP := Integer'Max (1, P.HP - Dmg);
               if P.HP <= 0 then
                  P.Alive := False;
                  Set_Msg (State, "You quaff the foul potion. POISON!  You die...");
               else
                  Set_Msg (State, "You quaff the foul potion. POISON! -"
                           & Img (Dmg) & " HP!");
               end if;
            end;
            Remove_From_Inv (State, Slot);

         when Potion_Blind =>
            P.Blind_Turns := P.Blind_Turns + It.Value;
            Set_Msg (State, "You quaff the murky potion. Everything goes dark! ("
                     & Img (It.Value) & " turns)");
            Remove_From_Inv (State, Slot);

         when Potion_Invis =>
            P.Invis_Turns := P.Invis_Turns + It.Value;
            P.Invisible   := True;
            Set_Msg (State, "You quaff the sparkling potion. You fade from sight! ("
                     & Img (It.Value) & " turns)");
            Remove_From_Inv (State, Slot);

         -- ---- Scrolls ----
         when Scroll_Identify =>
            Set_Msg (State,
               "The scroll glows!  Your items are fully identified.");
            Remove_From_Inv (State, Slot);

         when Scroll_Magic_Map =>
            for Y in Map_Row loop
               for X in Map_Col loop
                  if State.Level.Map (Y, X).Kind /= Void then
                     State.Level.Map (Y, X).Seen := True;
                     if Is_Trap (State.Level.Map (Y, X).Kind) then
                        State.Level.Map (Y, X).Trap_Known := True;
                     end if;
                  end if;
               end loop;
            end loop;
            Set_Msg (State, "A magical map floods your mind!");
            Remove_From_Inv (State, Slot);

         when Scroll_Fireball =>
            -- Ask for direction, then AoE 3x3 at 5 tiles distance
            Set_Msg (State, "Fireball!  Pick direction (hjkl / arrows):");
            declare
               Key2        : constant Key_Event := Get_Key;
               Dx2, Dy2    : Integer := 0;
               Got_Dir     : Boolean := False;
            begin
               if Key2.Kind = Key_Char then
                  case Key2.Ch is
                     when 'h' => Dx2 := -1; Dy2 :=  0; Got_Dir := True;
                     when 'l' => Dx2 :=  1; Dy2 :=  0; Got_Dir := True;
                     when 'k' => Dx2 :=  0; Dy2 := -1; Got_Dir := True;
                     when 'j' => Dx2 :=  0; Dy2 :=  1; Got_Dir := True;
                     when 'y' => Dx2 := -1; Dy2 := -1; Got_Dir := True;
                     when 'u' => Dx2 :=  1; Dy2 := -1; Got_Dir := True;
                     when 'b' => Dx2 := -1; Dy2 :=  1; Got_Dir := True;
                     when 'n' => Dx2 :=  1; Dy2 :=  1; Got_Dir := True;
                     when others => null;
                  end case;
               elsif Key2.Kind = Key_Left  then Dx2 := -1; Got_Dir := True;
               elsif Key2.Kind = Key_Right then Dx2 :=  1; Got_Dir := True;
               elsif Key2.Kind = Key_Up    then Dy2 := -1; Got_Dir := True;
               elsif Key2.Kind = Key_Down  then Dy2 :=  1; Got_Dir := True;
               end if;
               if Got_Dir then
                  declare
                     CX   : constant Integer := P.Pos.X + Dx2 * 5;
                     CY   : constant Integer := P.Pos.Y + Dy2 * 5;
                     Hits : Integer := 0;
                  begin
                     for I in 1 .. Max_Monsters loop
                        declare
                           M : Monster_Data renames State.Level.Monsters (I);
                        begin
                           if M.Alive
                              and then abs (M.Pos.X - CX) <= 1
                              and then abs (M.Pos.Y - CY) <= 1
                           then
                              declare
                                 Dmg : constant Integer := Roll_D20 mod 10 + 8;
                              begin
                                 M.HP := M.HP - Dmg;
                                 if M.HP <= 0 then
                                    M.Alive := False;
                                    Add_XP (State, M.XP_Value);
                                 end if;
                                 Hits := Hits + 1;
                              end;
                           end if;
                        end;
                     end loop;
                     Set_Msg (State, "KA-BOOM!  Fireball hits "
                              & Img (Hits) & " monster(s)!");
                  end;
               else
                  Set_Msg (State, "Fireball fizzles.");
               end if;
            end;
            Remove_From_Inv (State, Slot);

         when Scroll_Enchant_Weapon =>
            if P.Weapon_Slot /= 0 then
               P.Inv (P.Weapon_Slot).Value :=
                  P.Inv (P.Weapon_Slot).Value + 1;
               P.Weapon_Bonus := P.Weapon_Bonus + 1;
               Set_Msg (State, "Your weapon glows with a blue light!");
            else
               Set_Msg (State, "You have no weapon wielded!");
            end if;
            Remove_From_Inv (State, Slot);

         when Scroll_Enchant_Armor =>
            if P.Armor_Slot /= 0 then
               P.Inv (P.Armor_Slot).Value :=
                  P.Inv (P.Armor_Slot).Value + 1;
               P.Armor_Bonus := P.Armor_Bonus + 1;
               Set_Msg (State, "Your armor shines with a golden light!");
            else
               Set_Msg (State, "You are not wearing armor!");
            end if;
            Remove_From_Inv (State, Slot);

         when Scroll_Teleport =>
            P.Pos := Random_Floor (State.Level);
            Set_Msg (State,
               "The scroll crumbles!  You feel a lurch and appear elsewhere!");
            Remove_From_Inv (State, Slot);

         -- ---- Bow: ready / lower ----
         when Bow =>
            if P.Bow_Slot = Slot then
               P.Bow_Slot := 0;
               Set_Msg (State, "You lower the " & Item_Name (It) & ".");
            else
               P.Bow_Slot := Slot;
               Set_Msg (State, "You ready the " & Item_Name (It)
                        & ".  Press 'f' to fire.");
            end if;

         -- ---- Arrow: just a count, no equip ----
         when Arrow =>
            Set_Msg (State, "Arrows are used automatically when firing a bow ('f').");

         -- ---- Torch: light / snuff ----
         when Torch =>
            if P.Torch_Slot = Slot then
               P.Torch_Slot := 0;
               Set_Msg (State, "You snuff the torch.");
            else
               P.Torch_Slot := Slot;
               Set_Msg (State, "You light the torch.  It illuminates the darkness!");
            end if;

         -- ---- Amulet of Yendor ----
         when Amulet_Yendor =>
            P.Has_Amulet := True;
            Set_Msg (State,
               "The Amulet of Yendor pulses with eldritch power!  "
               & "Carry it to the surface (level 1 '<' stairs)!");

         -- ---- Food ----
         when Food =>
            declare
               Heal : constant Integer := 4 + Roll_D20 mod 5;  -- 4-8 HP
            begin
               P.HP     := Integer'Min (P.Max_HP, P.HP + Heal);
               P.Hunger := 1000;
               P.Starve_Ticks := 0;
               Set_Msg (State, "You eat the ration. +" & Img (Heal) & " HP. Yum!");
            end;
            Remove_From_Inv (State, Slot);

         when Key =>
            Set_Msg (State, "Keys are used automatically by walking into locked doors.");

         when No_Item | Gold =>
            Set_Msg (State, "You cannot use that here.");
      end case;
   end Use_Inv_Item;

   -- Drop item from inventory onto the floor at the player's feet.
   procedure Drop_Inv_Item (State : in out Game_State; Slot : Integer) is
      P    : Player_Data renames State.Player;
      Name : constant String := Item_Name (P.Inv (Slot));
      It   : Item_Data := P.Inv (Slot);
   begin
      It.Pos     := P.Pos;
      It.Present := True;
      -- Find a free floor-item slot
      declare
         Placed : Boolean := False;
      begin
         for I in 1 .. Max_Items loop
            if not State.Level.Items (I).Present then
               State.Level.Items (I) := It;
               Placed := True;
               exit;
            end if;
         end loop;
         if not Placed then
            Set_Msg (State, "No room on the floor here!");
            return;
         end if;
      end;
      Set_Msg (State, "You drop " & Name & ".");
      Remove_From_Inv (State, Slot);
   end Drop_Inv_Item;

   -- ---------------------------------------------------------------
   -- Per-turn timed effects (called once per real player turn via Run_Monsters)
   -- ---------------------------------------------------------------
   procedure Tick_Effects (State : in out Game_State) is
      P : Player_Data renames State.Player;
   begin
      -- Blindness countdown
      if P.Blind_Turns > 0 then
         P.Blind_Turns := P.Blind_Turns - 1;
         if P.Blind_Turns = 0 then
            Set_Msg (State, "Your vision clears!");
         end if;
      end if;

      -- Regeneration ring: +1 HP every 5 turns while worn
      if P.Ring_Slot /= 0
         and then P.Inv (P.Ring_Slot).Kind = Ring
         and then P.Inv (P.Ring_Slot).Value = 1
         and then P.HP < P.Max_HP
      then
         P.Regen_Ticks := P.Regen_Ticks + 1;
         if P.Regen_Ticks >= 5 then
            P.Regen_Ticks := 0;
            P.HP := P.HP + 1;
         end if;
      end if;

      -- Ring lifespan countdown
      if P.Ring_Slot /= 0 and then P.Ring_Turns > 0 then
         P.Ring_Turns := P.Ring_Turns - 1;
         if P.Ring_Turns = 10 then
            Set_Msg (State, "Your ring feels loose on your finger...");
         elsif P.Ring_Turns = 0 then
            declare
               Name : constant String :=
                  Item_Name (P.Inv (P.Ring_Slot));
            begin
               Set_Msg (State,
                  "Your " & Name & " slips off your finger and crumbles to dust!");
               Remove_From_Inv (State, P.Ring_Slot);
            end;
         end if;
      end if;

      -- Potion of invisibility countdown
      if P.Invis_Turns > 0 then
         P.Invis_Turns := P.Invis_Turns - 1;
         if P.Invis_Turns = 0 then
            if P.Ring_Slot = 0
               or else P.Inv (P.Ring_Slot).Kind /= Ring
               or else P.Inv (P.Ring_Slot).Value /= 2
            then
               P.Invisible := False;
               Set_Msg (State, "You feel visible again.");
            end if;
         end if;
      end if;

      -- Torch countdown
      if P.Torch_Slot /= 0 then
         P.Inv (P.Torch_Slot).Value := P.Inv (P.Torch_Slot).Value - 1;
         if P.Inv (P.Torch_Slot).Value = 20 then
            Set_Msg (State, "Your torch is flickering...");
         elsif P.Inv (P.Torch_Slot).Value <= 0 then
            Set_Msg (State, "Your torch burns out!  Darkness closes in.");
            Remove_From_Inv (State, P.Torch_Slot);
         end if;
      end if;

      -- Hunger countdown
      P.Hunger := P.Hunger - 1;
      P.Turn_Count := P.Turn_Count + 1;
      if P.Hunger <= 0 then
         P.Starve_Ticks := P.Starve_Ticks + 1;
         if P.Starve_Ticks mod 5 = 0 then
            P.HP := P.HP - 1;
            Set_Msg (State, "You are starving!  -1 HP.");
            if P.HP <= 0 then
               P.Alive := False;
               Set_Msg (State, "You die of starvation.");
            end if;
         end if;
      end if;
   end Tick_Effects;

   -- ---------------------------------------------------------------
   -- Item pickup (auto on stepping onto a tile)
   -- ---------------------------------------------------------------
   procedure Pick_Up_Items (State : in out Game_State) is
      P : Player_Data renames State.Player;
   begin
      for I in 1 .. Max_Items loop
         declare
            It : Item_Data renames State.Level.Items (I);
         begin
            if It.Present
               and then It.Pos.X = P.Pos.X
               and then It.Pos.Y = P.Pos.Y
            then
               case It.Kind is
                  -- Gold and keys: auto-collect (no pack space used)
                  when Gold =>
                     P.Gold := P.Gold + It.Value;
                     Set_Msg (State, "You pick up " & Img (It.Value) & " gold pieces.");
                     It.Present := False;

                  when Key =>
                     if It.Value in 1 .. Max_Keys then
                        P.Keys_Held (It.Value) := True;
                     end if;
                     Set_Msg (State, "You pick up key #" & Img (It.Value)
                              & " (opens a locked door somewhere).");
                     It.Present := False;

                  -- Everything else goes into the pack
                  when others =>
                     if Add_To_Inv (State, It) then
                        Set_Msg (State, "You pick up " & Item_Name (It) & ".");
                        It.Present := False;
                     end if;
                     -- If pack full, item stays on floor (Add_To_Inv set msg)
               end case;
            end if;
         end;
      end loop;

      -- Tile announcements
      case State.Level.Map (P.Pos.Y, P.Pos.X).Kind is
         when Stairs_Down =>
            Set_Msg (State, "Stairs leading down here.  Press '>' to descend.");
         when Stairs_Up =>
            Set_Msg (State, "Stairs leading up here.  Press '<' to ascend.");
         when Shop =>
            Set_Msg (State, "You see a shop ($) here.  Press 's' to browse wares.");
         when others => null;
      end case;
   end Pick_Up_Items;

   -- ---------------------------------------------------------------
   -- Monster AI
   -- ---------------------------------------------------------------
   function Chebyshev (A, B : Position) return Integer is
     (Integer'Max (abs (A.X - B.X), abs (A.Y - B.Y)));

   function Monster_At (D : Dungeon; P : Position; Exclude : Integer := 0)
     return Integer is
   begin
      for I in 1 .. Max_Monsters loop
         if I /= Exclude
           and then D.Monsters (I).Alive
           and then D.Monsters (I).Pos.X = P.X
           and then D.Monsters (I).Pos.Y = P.Y
         then
            return I;
         end if;
      end loop;
      return 0;
   end Monster_At;

   procedure Run_Monsters (State : in out Game_State) is
      P : Player_Data renames State.Player;
   begin
      for I in 1 .. Max_Monsters loop
         declare
            M : Monster_Data renames State.Level.Monsters (I);
         begin
            if M.Alive then
               -- Ring of invisibility: monsters only wake when attacked
               -- (proximity alone won't wake them)
               if M.Asleep
                  and then not P.Invisible
                  and then Chebyshev (M.Pos, P.Pos) <= 7
               then
                  M.Asleep := False;
               end if;

               -- Troll: regenerate 1 HP every 5 turns while alive
               if M.Kind = Troll and then M.HP < M.Max_HP then
                  M.Regen_Ticks := M.Regen_Ticks + 1;
                  if M.Regen_Ticks >= 5 then
                     M.Regen_Ticks := 0;
                     M.HP := Integer'Min (M.Max_HP, M.HP + 1);
                  end if;
               end if;

               if not M.Asleep then
                  -- Dragon: fire breath at range <= 4 (30% chance)
                  if M.Kind = Dragon
                     and then Chebyshev (M.Pos, P.Pos) <= 4
                     and then Roll_D20 >= 15
                  then
                     declare
                        Dmg : constant Integer := Roll_D20 mod 10 + 8;
                     begin
                        P.HP := P.HP - Dmg;
                        Set_Msg (State, "The D breathes fire at you!  -"
                                 & Img (Dmg) & " HP!");
                        if P.HP <= 0 then P.Alive := False; end if;
                     end;
                  elsif Chebyshev (M.Pos, P.Pos) = 1 then
                     Monster_Hits_Player (State, I);
                  else
                     declare
                        Dx, Dy : Integer := 0;
                        Moved  : Boolean := False;

                        procedure Try_Step (Tx, Ty : Integer) is
                           NP : constant Position := (Tx, Ty);
                        begin
                           if Moved then return; end if;
                           if not In_Bounds (NP) then return; end if;
                           if not Is_Walkable (State.Level.Map (Ty, Tx).Kind) then return; end if;
                           if Monster_At (State.Level, NP, I) /= 0 then return; end if;
                           if NP.X = P.Pos.X and then NP.Y = P.Pos.Y then return; end if;
                           M.Pos := NP;
                           Moved := True;
                        end Try_Step;
                     begin
                        if P.Pos.X > M.Pos.X then Dx := 1;
                        elsif P.Pos.X < M.Pos.X then Dx := -1; end if;
                        if P.Pos.Y > M.Pos.Y then Dy := 1;
                        elsif P.Pos.Y < M.Pos.Y then Dy := -1; end if;

                        Try_Step (M.Pos.X + Dx, M.Pos.Y + Dy);
                        Try_Step (M.Pos.X + Dx, M.Pos.Y);
                        Try_Step (M.Pos.X,       M.Pos.Y + Dy);
                     end;
                  end if;
               end if;
            end if;
         end;
         exit when not State.Player.Alive;
      end loop;
      -- One tick of timed effects per monster-turn cycle
      if State.Player.Alive then
         Tick_Effects (State);
      end if;
   end Run_Monsters;

   -- ---------------------------------------------------------------
   -- Effective FOV radius based on blindness, dark rooms, and torch
   -- ---------------------------------------------------------------
   function Effective_Radius (State : Game_State) return Integer is
      P : Player_Data renames State.Player;
   begin
      if P.Blind_Turns > 0 then return 1; end if;
      if State.Level.Map (P.Pos.Y, P.Pos.X).Is_Dark then
         return (if P.Torch_Slot /= 0 then 6 else 2);
      end if;
      return 9;
   end Effective_Radius;

   -- ---------------------------------------------------------------
   -- Trap trigger
   -- ---------------------------------------------------------------
   procedure Trigger_Trap (State : in out Game_State) is
      P : Player_Data renames State.Player;
      T : Tile renames State.Level.Map (P.Pos.Y, P.Pos.X);
   begin
      T.Trap_Known := True;
      case T.Kind is
         when Trap_Teleport =>
            P.Pos := Random_Floor (State.Level);
            Set_Msg (State, "** TELEPORT TRAP! **  You vanish in a flash!");
         when Trap_Dart =>
            declare
               Dmg : constant Integer := Roll_D20 mod 6 + 2;
            begin
               P.HP := P.HP - Dmg;
               Set_Msg (State,
                  "** DART TRAP! **  A dart pierces you for "
                  & Img (Dmg) & " damage!");
               if P.HP <= 0 then P.Alive := False; end if;
            end;
         when Trap_Pit =>
            declare
               Dmg : constant Integer := Roll_D20 mod 8 + 3;
            begin
               P.HP := P.HP - Dmg;
               Set_Msg (State,
                  "** PIT TRAP! **  You plunge into a pit!  -"
                  & Img (Dmg) & " HP!");
               if P.HP <= 0 then P.Alive := False; end if;
            end;
         when Trap_Blind =>
            declare
               Dur : constant Integer := Roll_D20 mod 10 + 8;
            begin
               P.Blind_Turns := P.Blind_Turns + Dur;
               Set_Msg (State,
                  "** BLIND TRAP! **  A cloud of spores blinds you for "
                  & Img (Dur) & " turns!");
            end;
         when others => null;
      end case;
   end Trigger_Trap;

   -- ---------------------------------------------------------------
   -- Bow firing
   -- ---------------------------------------------------------------
   procedure Do_Fire_Bow (State : in out Game_State; Dx, Dy : Integer) is
      P          : Player_Data renames State.Player;
      Arrow_Slot : Integer := 0;
      CX, CY     : Integer;
      Hit        : Boolean := False;
   begin
      -- Find arrows
      for S in 1 .. Max_Inv loop
         if P.Inv (S).Kind = Arrow and then P.Inv (S).Value > 0 then
            Arrow_Slot := S; exit;
         end if;
      end loop;
      if Arrow_Slot = 0 then
         Set_Msg (State, "You have no arrows!");
         return;
      end if;
      -- Consume one arrow
      P.Inv (Arrow_Slot).Value := P.Inv (Arrow_Slot).Value - 1;
      if P.Inv (Arrow_Slot).Value = 0 then
         Remove_From_Inv (State, Arrow_Slot);
      end if;
      -- Trace shot up to 12 tiles
      CX := P.Pos.X; CY := P.Pos.Y;
      for Step in 1 .. 12 loop
         CX := CX + Dx; CY := CY + Dy;
         exit when not In_Bounds ((CX, CY));
         exit when not Is_Walkable (State.Level.Map (CY, CX).Kind)
                   and then State.Level.Map (CY, CX).Kind /= Door_Closed
                   and then State.Level.Map (CY, CX).Kind /= Door_Locked;
         declare
            MI : constant Integer := Monster_At (State.Level, (CX, CY));
         begin
            if MI /= 0 then
               declare
                  Bow_Acc : constant Integer :=
                     (if P.Bow_Slot /= 0 then P.Inv (P.Bow_Slot).Value else 0);
                  Dmg     : constant Integer := Roll (1, 6);
                  M : Monster_Data renames State.Level.Monsters (MI);
               begin
                  M.Asleep := False;
                  if not Attack_Hits (P.Base_Attack + Bow_Acc, M.Defense) then
                     Set_Msg (State, "Your arrow misses the "
                              & (1 => M.Symbol) & ".");
                  else
                     M.HP := M.HP - Dmg;
                     if M.HP <= 0 then
                        M.Alive := False;
                        Add_XP (State, M.XP_Value);
                        Set_Msg (State, "Your arrow kills the "
                                 & (1 => M.Symbol) & "!");
                     else
                        Set_Msg (State, "Your arrow hits the "
                                 & (1 => M.Symbol)
                                 & " for " & Img (Dmg) & " damage.");
                     end if;
                  end if;
                  Hit := True;
               end;
               exit;
            end if;
         end;
      end loop;
      if not Hit then
         Set_Msg (State, "Your arrow flies into the darkness.");
      end if;
      Run_Monsters (State);
      Update_FOV (State.Level, P.Pos, Effective_Radius (State));
   end Do_Fire_Bow;

   -- ---------------------------------------------------------------
   -- Resting helpers
   -- ---------------------------------------------------------------

   -- True when any alive monster is already awake (auto-rest must stop)
   function Any_Awake_Monster (State : Game_State) return Boolean is
   begin
      for I in 1 .. Max_Monsters loop
         if State.Level.Monsters (I).Alive
            and then not State.Level.Monsters (I).Asleep
         then
            return True;
         end if;
      end loop;
      return False;
   end Any_Awake_Monster;

   -- Advance one rest turn: +1 HP, run monsters, refresh FOV, redraw.
   procedure Rest_One_Turn (State : in out Game_State) is
      P : Player_Data renames State.Player;
   begin
      if P.HP < P.Max_HP then
         P.HP := P.HP + 1;
      end if;
      Run_Monsters (State);
      Update_FOV (State.Level, P.Pos,
                   Effective_Radius (State));
   end Rest_One_Turn;

   -- ---------------------------------------------------------------
   -- Kick
   -- ---------------------------------------------------------------
   procedure Do_Kick (State : in out Game_State; Dx, Dy : Integer) is
      P  : Player_Data renames State.Player;
      NP : constant Position := (P.Pos.X + Dx, P.Pos.Y + Dy);
   begin
      if not In_Bounds (NP) then
         Set_Msg (State, "You kick the dungeon wall. *THUD*  Your foot hurts!");
         P.HP := Integer'Max (1, P.HP - 1);
         return;
      end if;
      declare
         T : Tile renames State.Level.Map (NP.Y, NP.X);
      begin
         case T.Kind is
            when Door_Closed =>
               T.Kind := Door_Open;
               Set_Msg (State, "You kick the door open!  *CRASH*");
               Wake_Nearby (State, NP, 5);
               Run_Monsters (State);
            when Door_Locked =>
               Wake_Nearby (State, NP, 8);
               if Roll_D20 >= 11 then
                  T.Kind := Door_Open; T.Lock_ID := 0;
                  Set_Msg (State, "You kick the locked door open!  *CRASH*");
               else
                  Set_Msg (State, "The door holds!  *BANG*  (monsters woken nearby)");
               end if;
               Run_Monsters (State);
            when Wall =>
               Set_Msg (State, "You stub your toe on the wall.  Ouch!");
               P.HP := Integer'Max (1, P.HP - 1);
            when others =>
               Set_Msg (State, "You kick the empty air.  Embarrassing.");
         end case;
      end;
   end Do_Kick;

   -- ---------------------------------------------------------------
   -- Level transitions
   -- ---------------------------------------------------------------
   procedure Descend (State : in out Game_State) is
   begin
      State.Player.Dungeon_Level := State.Player.Dungeon_Level + 1;
      State.Player.Keys_Held     := (others => False);
      State.Player.Blind_Turns   := 0;
      Generate (State.Level, State.Player.Dungeon_Level);
      State.Player.Pos := Random_Floor (State.Level);
      Update_FOV (State.Level, State.Player.Pos);
      Set_Msg (State, "You descend to dungeon level "
               & Img (State.Player.Dungeon_Level) & ".");
   end Descend;

   procedure Ascend (State : in out Game_State) is
      P : Player_Data renames State.Player;
   begin
      -- Win condition: carry Amulet of Yendor back to the surface
      if P.Dungeon_Level = 1 then
         if P.Has_Amulet then
            P.Won := True;
            Set_Msg (State, "You ascend with the Amulet of Yendor!  YOU WIN!");
         else
            Set_Msg (State,
               "There is nothing above this floor. "
               & "Find the Amulet of Yendor on level 10 first!");
         end if;
         return;
      end if;
      P.Dungeon_Level := P.Dungeon_Level - 1;
      P.Keys_Held     := (others => False);
      P.Blind_Turns   := 0;
      Generate (State.Level, P.Dungeon_Level);
      P.Pos := Random_Floor (State.Level);
      Update_FOV (State.Level, P.Pos);
      Set_Msg (State, "You ascend to dungeon level "
               & Img (P.Dungeon_Level) & ".");
   end Ascend;

   -- ---------------------------------------------------------------
   -- Drawing
   -- ---------------------------------------------------------------
   MAP_ROW_OFFSET : constant := 2;
   MSG_ROW        : constant := 1;
   STAT_ROW       : constant := 23;

   procedure Draw_Map (State : Game_State) is
      D : Dungeon     renames State.Level;
      P : Player_Data renames State.Player;
   begin
      for Y in Map_Row loop
         Move_To (Y + MAP_ROW_OFFSET - 1, 1);
         for X in Map_Col loop
            declare
               T : Tile renames D.Map (Y, X);
            begin
               if T.Visible then
                  case T.Kind is
                     when Wall        => Set_Color (White,   False); Put_Ch ('#');
                     when Door_Secret => Set_Color (White,   False); Put_Ch ('#');
                     when Floor       => Set_Color (Black,   True);  Put_Ch ('.');
                     when Corridor    => Set_Color (Black,   True);  Put_Ch ('.');
                     when Door_Closed => Set_Color (Yellow,  False); Put_Ch ('+');
                     when Door_Open   => Set_Color (Yellow,  False); Put_Ch ('/');
                     when Door_Locked => Set_Color (Red,     True);  Put_Ch ('+');
                     when Stairs_Down => Set_Color (White,   True);  Put_Ch ('>');
                     when Stairs_Up   => Set_Color (White,   True);  Put_Ch ('<');
                     when Shop        => Set_Color (Green,   True);  Put_Ch ('$');
                     when Trap_Teleport =>
                        if T.Trap_Known then Set_Color (Cyan,    True); Put_Ch ('^');
                        else                 Set_Color (Black,   True); Put_Ch ('.'); end if;
                     when Trap_Dart =>
                        if T.Trap_Known then Set_Color (Red,     True); Put_Ch ('^');
                        else                 Set_Color (Black,   True); Put_Ch ('.'); end if;
                     when Trap_Pit =>
                        if T.Trap_Known then Set_Color (Yellow,  True); Put_Ch ('^');
                        else                 Set_Color (Black,   True); Put_Ch ('.'); end if;
                     when Trap_Blind =>
                        if T.Trap_Known then Set_Color (Magenta, True); Put_Ch ('^');
                        else                 Set_Color (Black,   True); Put_Ch ('.'); end if;
                     when Void        => Reset_Attrs;                 Put_Ch (' ');
                  end case;
               elsif T.Seen then
                  Set_Color (Black, True);
                  case T.Kind is
                     when Wall        => Put_Ch ('#');
                     when Door_Secret => Put_Ch ('#');
                     when Floor       => Put_Ch ('.');
                     when Corridor    => Put_Ch ('.');
                     when Door_Closed => Put_Ch ('+');
                     when Door_Open   => Put_Ch ('/');
                     when Door_Locked => Put_Ch ('+');
                     when Stairs_Down => Put_Ch ('>');
                     when Stairs_Up   => Put_Ch ('<');
                     when Shop        => Put_Ch ('$');
                     when Trap_Teleport | Trap_Dart | Trap_Pit | Trap_Blind =>
                        Put_Ch ((if T.Trap_Known then '^' else '.'));
                     when Void        => Put_Ch (' ');
                  end case;
               else
                  Reset_Attrs; Put_Ch (' ');
               end if;
            end;
         end loop;
      end loop;

      -- Items
      for I in 1 .. Max_Items loop
         declare
            It : Item_Data renames D.Items (I);
         begin
            if It.Present and then In_Bounds (It.Pos)
               and then D.Map (It.Pos.Y, It.Pos.X).Visible
            then
               Move_To (It.Pos.Y + MAP_ROW_OFFSET - 1, It.Pos.X);
               case It.Kind is
                  when Gold         => Set_Color (Yellow,  True);  Put_Ch ('$');
                  when Potion_Heal  => Set_Color (Cyan,    True);  Put_Ch ('!');
                  when Potion_Str   => Set_Color (Red,     True);  Put_Ch ('!');
                  when Potion_Poison => Set_Color (Green,  True);  Put_Ch ('!');
                  when Potion_Blind => Set_Color (Magenta, False); Put_Ch ('!');
                  when Potion_Invis => Set_Color (White,   True);  Put_Ch ('!');
                  when Scroll_Identify
                     | Scroll_Magic_Map
                     | Scroll_Fireball
                     | Scroll_Enchant_Weapon
                     | Scroll_Enchant_Armor
                     | Scroll_Teleport    => Set_Color (White,   False); Put_Ch ('?');
                  when Weapon       => Set_Color (White,   True);  Put_Ch (')');
                  when Bow          => Set_Color (Cyan,    True);  Put_Ch (')');
                  when Arrow        => Set_Color (White,   False); Put_Ch ('/');
                  when Armor        => Set_Color (White,   True);  Put_Ch ('[');
                  when Food         => Set_Color (Yellow,  False); Put_Ch ('%');
                  when Torch        => Set_Color (Yellow,  True);  Put_Ch ('(');
                  when Key          => Set_Color (Magenta, True);  Put_Ch ('?');
                  when Ring         => Set_Color (Yellow,  True);  Put_Ch ('=');
                  when Amulet_Yendor => Set_Color (Yellow, True);  Put_Ch ('"');
                  when No_Item      => null;
               end case;
            end if;
         end;
      end loop;

      -- Monsters
      for I in 1 .. Max_Monsters loop
         declare
            M : Monster_Data renames D.Monsters (I);
         begin
            if M.Alive and then In_Bounds (M.Pos)
               and then D.Map (M.Pos.Y, M.Pos.X).Visible
            then
               Move_To (M.Pos.Y + MAP_ROW_OFFSET - 1, M.Pos.X);
               case M.Kind is
                  when Rat        => Set_Color (Black,  True);  Put_Ch (M.Symbol);
                  when Bat        => Set_Color (Black,  True);  Put_Ch (M.Symbol);
                  when Goblin     => Set_Color (Green,  False); Put_Ch (M.Symbol);
                  when Orc        => Set_Color (Green,  True);  Put_Ch (M.Symbol);
                  when Troll      => Set_Color (Cyan,   True);  Put_Ch (M.Symbol);
                  when Dragon     => Set_Color (Red,    True);  Put_Ch (M.Symbol);
                  when No_Monster => null;
               end case;
            end if;
         end;
      end loop;

      -- Player
      Move_To (P.Pos.Y + MAP_ROW_OFFSET - 1, P.Pos.X);
      Set_Color (Yellow, True); Put_Ch ('@');
   end Draw_Map;

   procedure Draw_Status (State : Game_State) is
      P : Player_Data renames State.Player;
   begin
      Move_To (STAT_ROW, 1);
      Reset_Attrs;
      Put_Str ("HP:");
      if P.HP <= P.Max_HP / 4 then Set_Color (Red,    True);
      elsif P.HP <= P.Max_HP / 2 then Set_Color (Yellow, True);
      else Set_Color (Green, True); end if;
      Put_Int (P.HP); Reset_Attrs; Put_Ch ('/'); Put_Int (P.Max_HP);
      Put_Str ("  Lv:"); Set_Color (Cyan, True); Put_Int (P.Level); Reset_Attrs;
      Put_Str ("  XP:"); Put_Int (P.XP); Put_Ch ('/'); Put_Int (P.XP_Next);
      Put_Str ("  $:"); Set_Color (Yellow, True); Put_Int (P.Gold); Reset_Attrs;
      Put_Str ("  Dl:"); Put_Int (P.Dungeon_Level);
      Put_Str ("  Atk:"); Put_Int (P.Base_Attack + P.Weapon_Bonus);
      Put_Str ("  Def:"); Put_Int (P.Base_Defense + P.Armor_Bonus);
      Put_Str ("  Inv:"); Put_Int (P.Inv_Count); Put_Ch ('/'); Put_Int (Max_Inv);

      -- Keys
      declare
         Any : Boolean := False;
      begin
         for K in 1 .. Max_Keys loop
            if P.Keys_Held (K) then Any := True; end if;
         end loop;
         if Any then
            Put_Str ("  Keys:");
            Set_Color (Magenta, True);
            for K in 1 .. Max_Keys loop
               if P.Keys_Held (K) then Put_Ch ('#'); Put_Int (K); end if;
            end loop;
            Reset_Attrs;
         end if;
      end;

      -- Active ring
      if P.Ring_Slot /= 0 then
         Set_Color (Yellow, True);
         case P.Inv (P.Ring_Slot).Value is
            when 1 => Put_Str ("  [Regen]");
            when 2 => Put_Str ("  [Invis]");
            when 3 => Put_Str ("  [Speed]");
            when 4 => Put_Str ("  [Tele]");
            when others => Put_Str ("  [Ring]");
         end case;
         Reset_Attrs;
      end if;

      -- Potion invisibility timer (ring shows [Invis] separately above)
      if P.Invis_Turns > 0 then
         Set_Color (Cyan, True);
         Put_Str ("  INVIS:"); Put_Int (P.Invis_Turns);
         Reset_Attrs;
      end if;

      -- Blindness
      if P.Blind_Turns > 0 then
         Set_Color (Red, True);
         Put_Str ("  BLIND:"); Put_Int (P.Blind_Turns);
         Reset_Attrs;
      end if;

      -- Torch indicator
      if P.Torch_Slot /= 0 then
         Set_Color (Yellow, True);
         Put_Str ("  [Torch:"); Put_Int (P.Inv (P.Torch_Slot).Value);
         Put_Str ("]"); Reset_Attrs;
      end if;

      -- Bow indicator
      if P.Bow_Slot /= 0 then
         Set_Color (Cyan, True);
         Put_Str ("  [Bow]"); Reset_Attrs;
      end if;

      -- Amulet indicator
      if P.Has_Amulet then
         Set_Color (Yellow, True);
         Put_Str ("  [AMULET]"); Reset_Attrs;
      end if;

      -- Hunger
      if P.Hunger <= 0 then
         Set_Color (Red, True); Put_Str ("  STARVING"); Reset_Attrs;
      elsif P.Hunger <= 300 then
         Set_Color (Yellow, True); Put_Str ("  Hungry"); Reset_Attrs;
      end if;

      if State.Pending = Kick then
         Set_Color (Yellow, True); Put_Str ("  KICK:dir"); Reset_Attrs;
      end if;
      if State.Pending = Fire_Bow then
         Set_Color (Cyan, True); Put_Str ("  FIRE:dir"); Reset_Attrs;
      end if;
   end Draw_Status;

   procedure Draw_Message (State : Game_State) is
   begin
      Move_To (MSG_ROW, 1);
      Set_Color (White, True);
      Put_Str (State.Message (1 .. State.Msg_Len));
      Reset_Attrs;
      for I in State.Msg_Len + 1 .. Max_Msg_Len loop
         Put_Ch (' ');
      end loop;
   end Draw_Message;

   procedure Draw (State : Game_State) is
   begin
      Draw_Map (State);
      Draw_Status (State);
      Draw_Message (State);
      Flush;
   end Draw;

   -- ---------------------------------------------------------------
   -- Inventory screen
   -- ---------------------------------------------------------------

   -- Draw the inventory overlay (replaces map rows 2-21).
   -- Inv_Prompt is an optional highlighted message shown at the bottom.
   procedure Draw_Inventory (State  : Game_State;
                              Prompt : String := "") is
      P   : Player_Data renames State.Player;
      Row : Integer := 4;
   begin
      -- Blank the map area
      for Y in 2 .. 21 loop
         Move_To (Y, 1);
         for X in 1 .. Map_Width loop Put_Ch (' '); end loop;
      end loop;

      -- Header
      Move_To (2, 3);
      Set_Color (White, True);
      Put_Str ("=== INVENTORY  (");
      Put_Int (P.Inv_Count); Put_Ch ('/'); Put_Int (Max_Inv);
      Put_Str (") ===");
      Reset_Attrs;

      -- List items
      for I in 1 .. Max_Inv loop
         if P.Inv (I).Kind /= No_Item then
            Move_To (Row, 3);
            -- Slot letter
            Set_Color (Cyan, True);
            Put_Ch (Character'Val (Character'Pos ('a') + I - 1));
            Put_Str (")  ");
            Reset_Attrs;
            -- Item description
            Put_Str (Item_Name (P.Inv (I)));
            -- Equipped tag
            if I = P.Weapon_Slot then
               Move_To (Row, 45);
               Set_Color (Yellow, True); Put_Str ("[wielded]"); Reset_Attrs;
            elsif I = P.Armor_Slot then
               Move_To (Row, 45);
               Set_Color (Yellow, True); Put_Str ("[worn]"); Reset_Attrs;
            end if;
            Row := Row + 1;
         end if;
      end loop;

      if P.Inv_Count = 0 then
         Move_To (Row, 5);
         Set_Color (Black, True); Put_Str ("(pack is empty)"); Reset_Attrs;
      end if;

      -- Controls / prompt line
      Move_To (20, 3);
      if Prompt'Length > 0 then
         Set_Color (Yellow, True); Put_Str (Prompt); Reset_Attrs;
      else
         Set_Color (White, False);
         Put_Str ("[letter] use/equip/eat    [D]+[letter] drop    [ESC/i] close");
         Reset_Attrs;
      end if;

      -- Redraw status + message at their normal rows
      Draw_Status (State);
      Draw_Message (State);
      Flush;
   end Draw_Inventory;

   -- Interactive inventory loop; returns when closed.
   procedure Run_Inventory (State : in out Game_State) is
      P   : Player_Data renames State.Player;
      Key : Key_Event;

      -- Resolve 'a'..'j' to an inventory slot (1..Max_Inv); 0 if invalid
      function Letter_To_Slot (C : Character) return Integer is
         Slot : constant Integer :=
            Character'Pos (C) - Character'Pos ('a') + 1;
      begin
         if Slot in 1 .. Max_Inv and then P.Inv (Slot).Kind /= No_Item then
            return Slot;
         end if;
         return 0;
      end Letter_To_Slot;

   begin
      Set_Msg (State, "");
      loop
         Draw_Inventory (State);
         Key := Get_Key;

         -- Close
         if Key.Kind = Key_Escape then exit; end if;
         if Key.Kind = Key_Char and then Key.Ch = 'i' then exit; end if;

         if Key.Kind = Key_Char then
            case Key.Ch is
               -- Drop mode: 'D' then a letter
               when 'D' =>
                  Draw_Inventory (State, "Drop which item? (press letter)");
                  Key := Get_Key;
                  if Key.Kind = Key_Char and then Key.Ch in 'a' .. 'j' then
                     declare
                        S : constant Integer := Letter_To_Slot (Key.Ch);
                     begin
                        if S > 0 then
                           Drop_Inv_Item (State, S);
                        else
                           Set_Msg (State, "No item in that slot.");
                        end if;
                     end;
                  else
                     Set_Msg (State, "Drop cancelled.");
                  end if;
                  exit;

               -- Use / equip / eat
               when 'a' .. 'j' =>
                  declare
                     S : constant Integer := Letter_To_Slot (Key.Ch);
                  begin
                     if S > 0 then
                        Use_Inv_Item (State, S);
                     else
                        Set_Msg (State, "No item in that slot.");
                     end if;
                  end;
                  exit;

               when others =>
                  Set_Msg (State, "Unknown key.  Use a letter, d, or ESC.");
            end case;
         end if;
      end loop;
   end Run_Inventory;

   -- ---------------------------------------------------------------
   -- Shop screen
   -- ---------------------------------------------------------------

   -- Gold the shopkeeper pays for an item (roughly 40 % of typical buy price).
   -- Returns 0 for items that cannot be sold (gold, keys).
   function Sell_Value (It : Item_Data) return Integer is
   begin
      case It.Kind is
         when No_Item | Gold | Key | Amulet_Yendor => return 0;
         when Food                 => return 5;
         when Potion_Heal          => return Integer'Max (5, It.Value * 2);
         when Potion_Str           => return 25;
         when Potion_Invis         => return 20;
         when Potion_Poison
            | Potion_Blind         => return 3;
         when Scroll_Identify
            | Scroll_Magic_Map
            | Scroll_Fireball
            | Scroll_Enchant_Weapon
            | Scroll_Enchant_Armor
            | Scroll_Teleport      => return 15;
         when Weapon               => return Integer'Max (3, It.Value * 10 + 8);
         when Bow                  => return Integer'Max (5, It.Value * 15 + 10);
         when Arrow                => return Integer'Max (1, It.Value);
         when Armor                => return Integer'Max (3, It.Value *  8 + 8);
         when Torch                => return Integer'Max (2, It.Value / 20);
         when Ring                 => return 40 + It.Value * 25;
      end case;
   end Sell_Value;
   procedure Draw_Shop (State : Game_State) is
      P        : Player_Data renames State.Player;
      Row      : Integer := 4;
      Any_Left : Boolean := False;
   begin
      -- Blank map area
      for Y in 2 .. 21 loop
         Move_To (Y, 1);
         for X in 1 .. Map_Width loop Put_Ch (' '); end loop;
      end loop;

      -- Header
      Move_To (2, 3);
      Set_Color (Green, True);
      Put_Str ("=== SHOP  (your gold: ");
      Set_Color (Yellow, True); Put_Int (P.Gold); Reset_Attrs;
      Set_Color (Green, True); Put_Str (") ==="); Reset_Attrs;

      -- Item list
      for I in 1 .. Max_Shop_Items loop
         declare
            SI : Shop_Item renames State.Level.Shop_Stock (I);
         begin
            if not SI.Sold and then SI.It.Kind /= No_Item then
               Any_Left := True;
               Move_To (Row, 3);
               Set_Color (Cyan, True);
               Put_Ch (Character'Val (Character'Pos ('a') + I - 1));
               Put_Str (")  ");
               Reset_Attrs;
               Put_Str (Item_Name (SI.It));
               -- Price right-aligned around column 52
               Move_To (Row, 52);
               Set_Color (Yellow, True);
               Put_Int (SI.Price);
               Put_Str (" gold");
               Reset_Attrs;
               Row := Row + 1;
            end if;
         end;
      end loop;

      if not Any_Left then
         Move_To (Row, 5);
         Set_Color (Black, True); Put_Str ("(sold out - come back next level)");
         Reset_Attrs;
      end if;

      Move_To (20, 3);
      Set_Color (White, False);
      Put_Str ("[letter] buy    [S] sell items    [ESC/s] leave shop");
      Reset_Attrs;

      Draw_Status (State);
      Draw_Message (State);
      Flush;
   end Draw_Shop;

   procedure Draw_Sell_Screen (State : Game_State) is
      P   : Player_Data renames State.Player;
      Row : Integer := 4;
   begin
      for Y in 2 .. 21 loop
         Move_To (Y, 1);
         for X in 1 .. Map_Width loop Put_Ch (' '); end loop;
      end loop;

      Move_To (2, 3);
      Set_Color (Green, True);
      Put_Str ("=== SELL ITEMS  (your gold: ");
      Set_Color (Yellow, True); Put_Int (P.Gold); Reset_Attrs;
      Set_Color (Green, True); Put_Str (") ==="); Reset_Attrs;

      for I in 1 .. Max_Inv loop
         if P.Inv (I).Kind /= No_Item then
            declare
               SV : constant Integer := Sell_Value (P.Inv (I));
            begin
               Move_To (Row, 3);
               Set_Color (Cyan, True);
               Put_Ch (Character'Val (Character'Pos ('a') + I - 1));
               Put_Str (")  ");
               Reset_Attrs;
               Put_Str (Item_Name (P.Inv (I)));
               Move_To (Row, 52);
               if SV > 0 then
                  Set_Color (Yellow, True);
                  Put_Str ("sell: "); Put_Int (SV); Put_Str (" gold");
               else
                  Set_Color (Black, True);
                  Put_Str ("(not sellable)");
               end if;
               Reset_Attrs;
               Row := Row + 1;
            end;
         end if;
      end loop;

      if P.Inv_Count = 0 then
         Move_To (Row, 5);
         Set_Color (Black, True); Put_Str ("(nothing to sell)"); Reset_Attrs;
      end if;

      Move_To (20, 3);
      Set_Color (White, False);
      Put_Str ("[letter] sell item    [ESC] cancel");
      Reset_Attrs;

      Draw_Status (State);
      Draw_Message (State);
      Flush;
   end Draw_Sell_Screen;

   procedure Run_Shop (State : in out Game_State) is
      P   : Player_Data renames State.Player;
      Key : Key_Event;
   begin
      Set_Msg (State, "Welcome!  Browse and buy with a letter key.");
      loop
         Draw_Shop (State);
         Key := Get_Key;

         exit when Key.Kind = Key_Escape;
         exit when Key.Kind = Key_Char and then Key.Ch = 's';

         if Key.Kind = Key_Char and then Key.Ch = 'S' then
            --  Enter sell sub-loop
            Set_Msg (State, "Sell which item?  (letter = sell, ESC = cancel)");
            loop
               Draw_Sell_Screen (State);
               Key := Get_Key;
               exit when Key.Kind = Key_Escape;
               if Key.Kind = Key_Char and then Key.Ch in 'a' .. 'j' then
                  declare
                     Slot : constant Integer :=
                        Character'Pos (Key.Ch) - Character'Pos ('a') + 1;
                  begin
                     if Slot in 1 .. Max_Inv
                        and then P.Inv (Slot).Kind /= No_Item
                     then
                        declare
                           SV   : constant Integer := Sell_Value (P.Inv (Slot));
                           Name : constant String  := Item_Name (P.Inv (Slot));
                        begin
                           if SV = 0 then
                              Set_Msg (State,
                                 "The shopkeeper doesn't want that.");
                           else
                              P.Gold := P.Gold + SV;
                              Set_Msg (State,
                                 "You sell the " & Name
                                 & " for " & Img (SV) & " gold.  "
                                 & Img (P.Gold) & " gold remaining.");
                              Remove_From_Inv (State, Slot);
                              exit;
                           end if;
                        end;
                     else
                        Set_Msg (State, "No item in that slot.");
                     end if;
                  end;
               end if;
            end loop;

         elsif Key.Kind = Key_Char and then Key.Ch in 'a' .. 'e' then
            declare
               Idx : constant Integer :=
                  Character'Pos (Key.Ch) - Character'Pos ('a') + 1;
            begin
               if Idx in 1 .. Max_Shop_Items then
                  declare
                     SI : Shop_Item renames State.Level.Shop_Stock (Idx);
                  begin
                     if SI.Sold or else SI.It.Kind = No_Item then
                        Set_Msg (State, "That item is already sold.");
                     elsif P.Gold < SI.Price then
                        Set_Msg (State,
                           "You can't afford that!  You need "
                           & Img (SI.Price) & " gold but only have "
                           & Img (P.Gold) & ".");
                     elsif Add_To_Inv (State, SI.It) then
                        P.Gold   := P.Gold - SI.Price;
                        SI.Sold  := True;
                        Set_Msg (State,
                           "You buy the " & Item_Name (SI.It)
                           & " for " & Img (SI.Price) & " gold.  "
                           & Img (P.Gold) & " gold remaining.");
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
   end Run_Shop;

   -- ---------------------------------------------------------------
   -- Direction decoder
   -- ---------------------------------------------------------------
   function Key_To_Dir (Key : Key_Event; Dx, Dy : out Integer) return Boolean is
   begin
      Dx := 0; Dy := 0;
      case Key.Kind is
         when Key_Up    => Dy := -1;           return True;
         when Key_Down  => Dy :=  1;           return True;
         when Key_Left  => Dx := -1;           return True;
         when Key_Right => Dx :=  1;           return True;
         when Key_Char =>
            case Key.Ch is
               when 'k' | '8' => Dy := -1;           return True;
               when 'j' | '2' => Dy :=  1;           return True;
               when 'h' | '4' => Dx := -1;           return True;
               when 'l' | '6' => Dx :=  1;           return True;
               when 'y' | '7' => Dx := -1; Dy := -1; return True;
               when 'u' | '9' => Dx :=  1; Dy := -1; return True;
               when 'b' | '1' => Dx := -1; Dy :=  1; return True;
               when 'n' | '3' => Dx :=  1; Dy :=  1; return True;
               when others    => return False;
            end case;
         when others => return False;
      end case;
   end Key_To_Dir;

   -- ---------------------------------------------------------------
   -- Main input handler - returns False to quit
   -- ---------------------------------------------------------------
   function Handle_Input (State : in out Game_State; Key : Key_Event)
     return Boolean is
      P      : Player_Data renames State.Player;
      Dx, Dy : Integer := 0;
      Moving : Boolean := False;
   begin
      Set_Msg (State, "");

      -- ---- resolve pending two-step commands ----
      if State.Pending = Kick then
         State.Pending := None;
         if Key_To_Dir (Key, Dx, Dy) then
            Do_Kick (State, Dx, Dy);
         else
            Set_Msg (State, "Kick cancelled.");
         end if;
         return True;
      end if;

      if State.Pending = Fire_Bow then
         State.Pending := None;
         if Key_To_Dir (Key, Dx, Dy) then
            Do_Fire_Bow (State, Dx, Dy);
         else
            Set_Msg (State, "Firing cancelled.");
         end if;
         return True;
      end if;

      if State.Pending = Confirm_Quit then
         State.Pending := None;
         if Key.Kind = Key_Char and then Key.Ch in 'y' | 'Y' then
            return False;
         end if;
         Set_Msg (State, "Never mind.");
         return True;
      end if;

      -- ---- normal commands ----
      if Key_To_Dir (Key, Dx, Dy) then
         Moving := True;
      elsif Key.Kind = Key_Char then
         case Key.Ch is
            when 'i' =>
               Run_Inventory (State);

            when 'e' =>
               -- Quick-eat: use first food in inventory
               declare
                  Found : Boolean := False;
               begin
                  for S in 1 .. Max_Inv loop
                     if P.Inv (S).Kind = Food then
                        Use_Inv_Item (State, S);
                        Found := True;
                        exit;
                     end if;
                  end loop;
                  if not Found then
                     Set_Msg (State, "You have no food.  Go find a ration (%).");
                  end if;
               end;

            when 's' =>
               if State.Level.Map (P.Pos.Y, P.Pos.X).Kind = Shop then
                  Run_Shop (State);
               else
                  Set_Msg (State,
                     "There is no shop here.  Find the green '$' tile.");
               end if;

            when 't' =>
               -- Ring of teleportation: teleport to random floor tile
               if P.Ring_Slot /= 0
                  and then P.Inv (P.Ring_Slot).Kind = Ring
                  and then P.Inv (P.Ring_Slot).Value = 4
               then
                  declare
                     TP : constant Position := Random_Floor (State.Level);
                  begin
                     P.Pos := TP;
                     Run_Monsters (State);
                     Update_FOV (State.Level, P.Pos,
                                  Effective_Radius (State));
                     Set_Msg (State, "Zap!  You teleport to a new location.");
                  end;
               else
                  Set_Msg (State,
                     "You need a ring of teleportation ('=') equipped to teleport.");
               end if;

            when 'r' =>
               -- Rest one turn: heal 1 HP, monsters act
               if P.HP >= P.Max_HP then
                  Set_Msg (State, "You are already at full health.");
               elsif Any_Awake_Monster (State) then
                  Set_Msg (State, "You can't rest -- a monster is nearby!");
               else
                  Rest_One_Turn (State);
                  Update_FOV (State.Level, P.Pos,
                               Effective_Radius (State));
                  Set_Msg (State, "You rest for a moment. (HP +"
                           & Img (P.HP) & "/" & Img (P.Max_HP) & ")");
               end if;

            when 'R' =>
               -- Auto-rest until full HP or interrupted by a waking monster
               if P.HP >= P.Max_HP then
                  Set_Msg (State, "You are already at full health.");
               elsif Any_Awake_Monster (State) then
                  Set_Msg (State, "You can't rest -- a monster is nearby!");
               else
                  Set_Msg (State, "Resting...");
                  loop
                     exit when P.HP >= P.Max_HP;
                     exit when not P.Alive;
                     exit when Any_Awake_Monster (State);
                     Rest_One_Turn (State);
                     Draw (State);
                  end loop;
                  if not P.Alive then
                     null;  -- death message handled by Run loop
                  elsif Any_Awake_Monster (State) then
                     Set_Msg (State, "Your rest is interrupted!  A monster is nearby!");
                  else
                     Set_Msg (State, "You wake up feeling refreshed. (HP "
                              & Img (P.HP) & "/" & Img (P.Max_HP) & ")");
                  end if;
                  Update_FOV (State.Level, P.Pos,
                               Effective_Radius (State));
               end if;

            when 'S' =>
               -- Search adjacent tiles for secret doors
               declare
                  Found : Boolean := False;
               begin
                  for Sy in -1 .. 1 loop
                     for Sx in -1 .. 1 loop
                        if Sx /= 0 or Sy /= 0 then
                           declare
                              NP : constant Position :=
                                 (P.Pos.X + Sx, P.Pos.Y + Sy);
                           begin
                              if In_Bounds (NP)
                                 and then State.Level.Map (NP.Y, NP.X).Kind
                                             = Door_Secret
                              then
                                 State.Level.Map (NP.Y, NP.X).Kind := Door_Closed;
                                 State.Level.Map (NP.Y, NP.X).Seen := True;
                                 Found := True;
                              end if;
                           end;
                        end if;
                     end loop;
                  end loop;
                  if Found then
                     Set_Msg (State, "You find a secret door!");
                  else
                     Set_Msg (State, "You search carefully... nothing here.");
                  end if;
               end;
               Run_Monsters (State);
               Update_FOV (State.Level, P.Pos, Effective_Radius (State));

            when 'f' =>
               if P.Bow_Slot = 0 then
                  Set_Msg (State,
                     "You need a bow readied first. (Use 'i' to ready a bow ')' cyan)");
               else
                  State.Pending := Fire_Bow;
                  Set_Msg (State, "Fire in which direction? (hjkl / arrows)");
               end if;

            when 'K' =>
               State.Pending := Kick;
               Set_Msg (State, "Kick in which direction? (hjkl / arrows)");

            when '>' =>
               if State.Level.Map (P.Pos.Y, P.Pos.X).Kind = Stairs_Down then
                  Descend (State);
               else
                  Set_Msg (State, "You must stand on '>' to descend.");
               end if;

            when '<' =>
               if State.Level.Map (P.Pos.Y, P.Pos.X).Kind = Stairs_Up then
                  Ascend (State);
               else
                  Set_Msg (State, "You must stand on '<' to ascend.");
               end if;

            when 'q' | 'Q' =>
               State.Pending := Confirm_Quit;
               Set_Msg (State, "Really quit? (y/n)");

            when others =>
               Set_Msg (State,
                  "hjkl/arrows=move  i=inv  e=eat  r/R=rest  S=search  f=fire  K=kick  s=shop  t=tele  ><=stairs  q=quit");
         end case;
      elsif Key.Kind = Key_Escape then
         Set_Msg (State, "Press q to quit.");
      end if;

      if Moving then
         declare
            NP : constant Position := (P.Pos.X + Dx, P.Pos.Y + Dy);
         begin
            if not In_Bounds (NP) then
               Set_Msg (State, "You walk into the dungeon boundary.");
            else
               declare
                  T  : Tile    renames State.Level.Map (NP.Y, NP.X);
                  MI : constant Integer := Monster_At (State.Level, NP);
               begin
                  if MI /= 0 then
                     Attack_Monster (State, MI);
                     Run_Monsters (State);

                  elsif T.Kind = Door_Closed then
                     T.Kind := Door_Open;
                     Set_Msg (State, "You open the door.");
                     Run_Monsters (State);

                  elsif T.Kind = Door_Locked then
                     declare
                        LID : constant Integer := T.Lock_ID;
                        Has : constant Boolean :=
                           LID in 1 .. Max_Keys and then P.Keys_Held (LID);
                     begin
                        if Has then
                           P.Keys_Held (LID) := False;
                           T.Kind    := Door_Open;
                           T.Lock_ID := 0;
                           Set_Msg (State, "You unlock the door with key #"
                                    & Img (LID) & " and push it open.");
                           Run_Monsters (State);
                        else
                           Set_Msg (State,
                              "The door is locked!  Find key #" & Img (LID)
                              & " (?) or kick it open (K).");
                        end if;
                     end;

                  elsif Is_Walkable (T.Kind) then
                     P.Pos := NP;
                     -- Trigger trap on first step (Trap_Known = False)
                     if Is_Trap (T.Kind) and then not T.Trap_Known then
                        Trigger_Trap (State);
                     end if;
                     Pick_Up_Items (State);
                     Run_Monsters (State);
                     -- Blind players see only 1 tile around them
                     Update_FOV (State.Level, P.Pos,
                                  Effective_Radius (State));

                  else
                     Set_Msg (State, "Ouch!  You bump into a wall.");
                  end if;
               end;
            end if;
         end;
      end if;

      return True;
   end Handle_Input;

   -- ---------------------------------------------------------------
   -- Public entry points
   -- ---------------------------------------------------------------
   procedure Title_Screen is
      Screen_Width : constant := 80;

      -- Put S centred on Row.  UTF-8 continuation bytes take no column.
      procedure Center (Row : Integer; S : String) is
         Width : Natural := 0;
      begin
         for C of S loop
            if Character'Pos (C) not in 16#80# .. 16#BF# then
               Width := Width + 1;
            end if;
         end loop;
         Move_To (Row, Integer'Max (1, (Screen_Width - Width) / 2 + 1));
         Put_Str (S);
      end Center;
   begin
      Clear_Screen;
      Set_Color (Yellow, True);
      Center (7, "A D A H A C K");
      Reset_Attrs;
      Center (9, "A NetHack-inspired roguelike written in Ada");
      Center (12, "Copyright (C) 2026 By Ulrik Hørlyk Hjort");
      Center (13, "Released under the MIT License");
      Set_Color (Cyan);
      Center (16, "Find the Amulet of Yendor on level 10 and return alive.");
      Reset_Attrs;
      Center (19, "Press any key to begin.");
      Flush;
      declare
         Dummy : Key_Event := Get_Key;
         pragma Unreferenced (Dummy);
      begin null; end;
   end Title_Screen;

   procedure New_Game (State : out Game_State) is
   begin
      D20.Reset (Combat_Gen);
      Ring_Life_RNG.Reset (Ring_Life_Gen);
      Dice_RNG.Reset (Dice_Gen);
      State.Player  := (others => <>);
      State.Msg_Len := 0;
      State.Message := (others => ' ');
      State.Pending := None;
      Generate (State.Level, 1);
      State.Player.Pos := Random_Floor (State.Level);
      Update_FOV (State.Level, State.Player.Pos);
      Set_Msg (State,
         "Welcome to AdaHack!  Find '>' to go deeper.  i=inv  e=eat  K=kick  t=teleport");
   end New_Game;

   procedure Run (State : in out Game_State) is
      Key : Key_Event;
      P   : Player_Data renames State.Player;
   begin
      loop
         Draw (State);
         exit when not P.Alive;
         exit when P.Won;
         Key := Get_Key;
         exit when not Handle_Input (State, Key);
         exit when not P.Alive;
         exit when P.Won;
      end loop;

      if P.Won then
         Draw (State);
         Move_To (10, 16); Set_Color (Yellow, True);
         Put_Str ("*** YOU WIN!  THE AMULET OF YENDOR IS YOURS! ***");
         Move_To (12, 22); Reset_Attrs;
         Put_Str ("Dungeon level reached : 10");
         Move_To (13, 22);
         Put_Str ("Player level         : " & Img (P.Level));
         Move_To (14, 22);
         Put_Str ("Gold collected       : " & Img (P.Gold));
         Move_To (15, 22);
         Put_Str ("Turns taken          : " & Img (P.Turn_Count));
         Move_To (17, 28); Reset_Attrs;
         Put_Str ("Press any key to exit.");
         Flush;
         declare
            Dummy : Key_Event := Get_Key;
            pragma Unreferenced (Dummy);
         begin null; end;

      elsif not P.Alive then
         Draw (State);
         Move_To (12, 30); Set_Color (Red, True);
         Put_Str ("*** YOU DIED ***");
         Move_To (13, 22); Reset_Attrs;
         Put_Str ("Level: " & Img (P.Level)
                  & "  Depth: " & Img (P.Dungeon_Level)
                  & "  Gold: "  & Img (P.Gold)
                  & "  Turns: " & Img (P.Turn_Count));
         Move_To (15, 28); Reset_Attrs;
         Put_Str ("Press any key to exit.");
         Flush;
         declare
            Dummy : Key_Event := Get_Key;
            pragma Unreferenced (Dummy);
         begin null; end;
      end if;
   end Run;

end Game;
