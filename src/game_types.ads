-- ***************************************************************************
--                            AdaHack - Game_Types
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

-- All shared game data types
package Game_Types is

   Map_Width  : constant := 78;
   Map_Height : constant := 20;

   subtype Map_Col is Integer range 1 .. Map_Width;
   subtype Map_Row is Integer range 1 .. Map_Height;

   type Position is record
      X : Integer;
      Y : Integer;
   end record;

   function In_Bounds (P : Position) return Boolean is
     (P.X in Map_Col and P.Y in Map_Row);

   -- ---------------------------------------------------------------
   -- Map
   -- ---------------------------------------------------------------
   type Tile_Kind is (
      Void, Wall, Floor, Corridor,
      Door_Closed, Door_Open, Door_Locked,
      Door_Secret,       -- looks like Wall until found by searching
      Stairs_Down, Stairs_Up, Shop,
      Trap_Teleport,     -- ^ cyan  -teleports the player
      Trap_Dart,         -- ^ red   -poison dart does damage
      Trap_Pit,          -- ^ yellow -fall damage
      Trap_Blind         -- ^ magenta -blinds the player
   );

   type Tile is record
      Kind       : Tile_Kind := Void;
      Lock_ID    : Integer   := 0;       -- non-zero on Door_Locked tiles
      Seen       : Boolean   := False;
      Visible    : Boolean   := False;
      Is_Dark    : Boolean   := False;   -- tile is in an unlit room
      Trap_Known : Boolean   := False;   -- player has triggered/mapped this trap
   end record;

   type Map_Array is array (Map_Row, Map_Col) of Tile;

   function Is_Walkable (K : Tile_Kind) return Boolean is
     (K = Floor or K = Corridor or K = Door_Open
      or K = Stairs_Down or K = Stairs_Up or K = Shop
      or K = Trap_Teleport or K = Trap_Dart
      or K = Trap_Pit      or K = Trap_Blind);

   function Is_Trap (K : Tile_Kind) return Boolean is
     (K = Trap_Teleport or K = Trap_Dart or K = Trap_Pit or K = Trap_Blind);

   -- ---------------------------------------------------------------
   -- Items
   -- ---------------------------------------------------------------
   type Item_Kind is (
      No_Item,
      Gold,
      Potion_Heal,           -- value = HP restored (blue)
      Potion_Str,            -- permanently +1 Base_Attack (red)
      Potion_Poison,         -- value = HP lost (foul-smelling)
      Potion_Blind,          -- value = turns blinded (murky)
      Potion_Invis,          -- value = turns invisible (sparkling)
      Scroll_Identify,       -- identify all items in inventory
      Scroll_Magic_Map,      -- reveal entire level map
      Scroll_Fireball,       -- AoE fire attack in chosen direction
      Scroll_Enchant_Weapon, -- +1 to equipped weapon
      Scroll_Enchant_Armor,  -- +1 to equipped armor
      Scroll_Teleport,       -- teleport self to random floor tile
      Weapon,                -- value = atk bonus; negative = cursed/broken
      Bow,                   -- value = accuracy bonus; fire with 'f'
      Arrow,                 -- value = count (stackable ammo)
      Armor,                 -- value = def bonus; negative = cursed
      Food,
      Torch,                 -- value = turns of light remaining
      Key,
      Ring,                  -- value: 1=Regen  2=Invis  3=Speed  4=Teleport
      Amulet_Yendor          -- win condition: carry back to level 1
   );

   type Item_Data is record
      Kind    : Item_Kind := No_Item;
      Pos     : Position  := (1, 1);
      Value   : Integer   := 0;    -- semantics vary by Kind
      Present : Boolean   := False;
   end record;

   Max_Items : constant := 24;
   type Item_Array is array (1 .. Max_Items) of Item_Data;

   -- ---------------------------------------------------------------
   -- Shop
   -- ---------------------------------------------------------------
   Max_Shop_Items : constant := 5;

   type Shop_Item is record
      It    : Item_Data;
      Price : Integer := 0;
      Sold  : Boolean := False;
   end record;

   type Shop_Array is array (1 .. Max_Shop_Items) of Shop_Item;

   -- ---------------------------------------------------------------
   -- Monsters
   -- ---------------------------------------------------------------
   type Monster_Kind is (
      No_Monster, Rat, Bat, Goblin, Orc, Troll, Dragon
   );

   type Monster_Data is record
      Kind        : Monster_Kind := No_Monster;
      Pos         : Position     := (1, 1);
      HP          : Integer      := 0;
      Max_HP      : Integer      := 0;
      Attack      : Integer      := 0;
      Defense     : Integer      := 0;
      Dmg_Min     : Integer      := 1;   -- damage roll on a hit
      Dmg_Max     : Integer      := 1;
      XP_Value    : Integer      := 0;
      Symbol      : Character    := '?';
      Alive       : Boolean      := False;
      Asleep      : Boolean      := True;
      Regen_Ticks : Integer      := 0;   -- used by Troll
   end record;

   Max_Monsters : constant := 12;
   type Monster_Array is array (1 .. Max_Monsters) of Monster_Data;

   -- ---------------------------------------------------------------
   -- Player
   -- ---------------------------------------------------------------
   Max_Keys : constant := 8;
   Max_Inv  : constant := 10;

   type Key_Set    is array (1 .. Max_Keys) of Boolean;
   type Inv_Array  is array (1 .. Max_Inv)  of Item_Data;

   type Player_Data is record
      Pos           : Position  := (1, 1);
      HP            : Integer   := 20;
      Max_HP        : Integer   := 20;
      Base_Attack   : Integer   := 3;
      Base_Defense  : Integer   := 1;
      Weapon_Bonus  : Integer   := 0;   -- from equipped weapon
      Armor_Bonus   : Integer   := 0;   -- from equipped armor
      Ring_Atk_Bon  : Integer   := 0;   -- from ring of speed
      Level         : Integer   := 1;
      XP            : Integer   := 0;
      XP_Next       : Integer   := 50;
      Gold          : Integer   := 0;
      Dungeon_Level : Integer   := 1;
      Keys_Held     : Key_Set   := (others => False);
      Alive         : Boolean   := True;
      -- Inventory
      Inv           : Inv_Array := (others => (No_Item, (1, 1), 0, False));
      Inv_Count     : Integer   := 0;
      Weapon_Slot   : Integer   := 0;   -- 1..Max_Inv, 0 = bare hands
      Armor_Slot    : Integer   := 0;   -- 1..Max_Inv, 0 = no armor
      Ring_Slot     : Integer   := 0;   -- 1..Max_Inv, 0 = no ring
      Bow_Slot      : Integer   := 0;   -- 1..Max_Inv, 0 = no bow readied
      Torch_Slot    : Integer   := 0;   -- 1..Max_Inv, 0 = no lit torch
      -- Timed / active effects
      Invisible     : Boolean   := False;
      Blind_Turns   : Integer   := 0;
      Invis_Turns   : Integer   := 0;   -- turns left from potion of invisibility
      Regen_Ticks   : Integer   := 0;
      Ring_Turns    : Integer   := 0;   -- turns left before ring slips off
      -- Hunger
      Hunger        : Integer   := 1000;  -- 1000=full, <=0=starving
      Starve_Ticks  : Integer   := 0;
      -- Win / turn tracking
      Has_Amulet    : Boolean   := False;
      Won           : Boolean   := False;
      Turn_Count    : Integer   := 0;
   end record;

   -- ---------------------------------------------------------------
   -- Dungeon (one level's worth of data)
   -- ---------------------------------------------------------------
   type Dungeon is record
      Map        : Map_Array;
      Items      : Item_Array;
      Monsters   : Monster_Array;
      Shop_Stock : Shop_Array;
      Has_Shop   : Boolean := False;
   end record;

end Game_Types;
