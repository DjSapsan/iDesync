# iDesync — .beh Compiler Project

## What this project is

A compiler/toolchain that compiles `.beh` (behavior script) source files into the JSON instruction format used by the game **Desynced** (sci-fi automation/RTS game). Behaviors are programs that control in-game units and structures.

## Goal

`.beh` source → tokenize → parse → AST → codegen → Desynced JSON

The JSON is then optionally encoded into a `*.base` string using `dsconvert.js` (Node.js) for in-game import.

---

## .beh Language Reference

### Top-level declarations

```beh
params [
    Cargo,       -- exposed behavior parameters (slots)
    param2,
]

vars [
    State = 0,   -- local variables, optional init value
    Entity,
    Signal,
]
```

### Statements

- `turnOn()` — Call built-in with no args
- `lockSlots(Cargo)` — Call built-in with args
- `State = 0` — Assignment
- `Entity, Signal = foreach(Cargo)` — Multi-assign from loop
- `Items = -1 * Items` — Arithmetic expression
- `goto(MAIN_LOOP)` — Unconditional jump to label
- `wait(300)` — Wait N ticks
- `break` — Break out of loop

### Control flow

```beh
repeat
    -- infinite loop body
end

compare(State, 0)
    equal
        -- code when State == 0
    end
    larger
        -- code when State > 0
    end
    smaller
        -- code when State < 0
    end
end

foreach(Cargo)
    if Signal > 0 then
        -- body
    end
end

if not checkFreeSpace(Cargo) then
    State = -1
end
```

### Functions

```beh
function findClosest (Arg1, Arg2)
    vars (Var1 Var2 Var3)

    -- body

    return (Arg1 Other)
end
```

---

## Target JSON format (Desynced opcodes)

Each instruction is a numbered key. Key fields:
- `"op"` — opcode name (string)
- `"0"`, `"1"`, `"2"`, `"3"` — positional arguments
- `"next"` — index of next instruction (omit = sequential, `false` = no fallthrough)
- `"c"` — condition register slot
- `"cmt"` — comment string
- `"nx"`, `"ny"` — visual position (node graph coords)
- `"sub"` — sub-behavior index (for `call`)
- `"pnum"` — parameter number (for `event_parameter`)

Top-level keys also include:
- `"pnames"` — array of parameter name strings
- `"parameters"` — array of booleans (true = exposed param slot)
- `"name"` — behavior name
- `"dependencies"` — array of sub-behavior objects (same structure)

### Argument value types

- integer N — register index (positive = component register, negative = owner register)
- `"VarName"` — named register (string)
- `{ id = "item_id" }` — game item/entity reference
- `{ num = 30 }` — literal number
- `false` — null/none

### Game instruction definition format (main/data/instructions.lua)

Each instruction is defined as `data.instructions.<id>` with:
- `func(comp, state, cause, ...)` — runtime logic (return true = yields/waits)
- `make_asm(inst)` — optional, generates extra arg passed to func after cause
- `next(comp, state, it, ...)` / `last(comp, state, it, ...)` — loop iteration/cleanup
- `exec_arg = { index, "Label", "Description" }` — execution path branching
- `args = { {'in'|'out'|'exec', "Name", "Desc", filter?, expanded?}, ... }` — argument definitions
- `name`, `desc`, `category`, `icon` — metadata
- `node_ui(canvas, inst, program_ui)` — optional visual editor UI
- `sample` — encoded example string

Categories: Flow, Unit, Global, Math, Move, Component, AutoBase

### Key opcodes

- `turnon` / `shutdown` — Enable/disable component
- `unlock` / `lock_slots` — Slot management
- `set_reg` — Assign value to register: `0`=dest, `1`=src
- `set_number` — Set numeric value
- `wait` — Wait N ticks: `0`={num=N}
- `jump` — Unconditional jump: `0`=label id
- `label` — Jump target: `0`=label id
- `call` — Call sub-behavior: `0`=arg, `sub`=sub-index
- `for_inventory_item` — foreach loop over inventory
- `for_signal_match` — foreach loop over signals
- `for_number` / `for_count_resources` / `for_component` — other loop types
- `check_number` — Conditional branch: `0`=next-if-false, `2`=value
- `compare_register` / `compare_entity` / `compare_item` — comparison ops
- `is_a` / `is_unit_a` / `is_empty` / `is_equipped` — type/state checks
- `add` / `sub` / `mul` / `div` / `modulo` — arithmetic
- `domove` / `domove_async` / `domovexy` / `domove_range` — movement
- `dopickup` / `dodrop` / `dodock` / `doundock` — item handling
- `attack_move` / `mine` / `scan` / `scout` — unit commands
- `get_closest_entity` / `get_distance` / `get_location` / `getxy` — spatial queries
- `notify` / `ping` / `debug_print` — notifications
- `exit` / `restart` / `stop` — execution control
- `event_parameter` / `event_radio` — parameter/event declarations
- `memory_get` / `memory_set` / `memory_insert` / `memory_remove` / `memory_loop` / `memory_length` — memory ops
- `read_signal` / `read_radio` / `readkey` — input reading
- `produce` / `build` / `equip_component` / `unequip_component` — production/equip
- `random_number` / `random_coordinate` — RNG
- `match` / `switch` / `sequence` / `select_nearest` — flow branching

Full list: 198 instructions defined in `main/data/instructions.lua`

---

## Project structure

```
iDesync/
  main.lua                  -- entry point: parse .beh, print AST
  src.beh / src2.beh        -- example source files (same content)
  Example.json              -- example target output (reference)
  Example.base              -- encoded Desynced string
  dsconvert.js              -- Node.js encoder/decoder for .base strings
  instructions.lua          -- full Desynced opcode definitions (game data)
  beh/
    tokenizer.lua           -- [STUB] .beh-specific tokenizer subclass
    parser.lua              -- [PARTIAL] .beh parser (only params so far)
    ast.lua                 -- [STUB] AST node definitions
  base/
    tokenizer.lua           -- full base tokenizer (coroutine-based)
    parser.lua              -- base parser class (canbe/mustbe)
    datareader.lua          -- regex-based stream reader
  main/data/                -- original Desynced game data (Lua source)
    instructions.lua        -- 198 instruction definitions with func/args/metadata
    behaviors.lua           -- built-in behavior encoded strings
    components.lua          -- all game components (slots, registers, recipes)
    items.lua               -- all game items (resources, produced goods)
    values.lua              -- signal/color/filter constants
    library.lua             -- behavior assembly/cache/execution runtime
  lua/                      -- Lua reference parser (for reference)
  grammar/                  -- grammar-based parser (for reference)
```

### Instruction runtime helpers (instructions.lua)

The runtime (in `instructions.lua` / `main/data/instructions.lua`) provides register access helpers used by instruction `func` implementations:
- `InstGet(comp, state, i)` — read register i (handles stack frames, memory, owner regs, faction radio)
- `InstGetNum(comp, state, i)` — read register as number
- `InstGetEntity(comp, state, i)` — read register as entity
- `InstSet(comp, state, i, val)` — write register i
- `GetStack(state, i)` — resolve stack-relative register index
- `CallRadio(fn, comp, state, j, setval)` — access faction radio storage registers

Register index conventions: positive = component register, negative (-1..-4) = frame register, negative (<= -100) = faction radio register.

### Game data files (main/data/)

- **items.lua** — all game items with `name`, `slot_type`, `stack_size`, `mining_recipe` / `production_recipe`
- **components.lua** — all components with slots, registers, activation modes, recipes, callbacks
- **values.lua** — constants: alien signals, colors, entity filters (radar), coordinate types
- **behaviors.lua** — encoded strings of built-in behaviors (Formation Move, Loop Recipe, etc.)
- **library.lua** — `GetFactionBehaviorAsm()` assembler: converts behavior JSON to executable asm array, handles sub-calls, memory, faction registers

---

## Implementation status

- Base tokenizer — DONE (base/tokenizer.lua)
- Base parser — DONE (base/parser.lua)
- Beh tokenizer — STUB — needs keywords/symbols from .beh spec
- Beh parser — PARTIAL — only `params` block; missing everything else
- Beh AST nodes — STUB — empty
- Code generator — NOT STARTED — must emit Desynced JSON

## Next steps (compiler pipeline)

1. **beh/tokenizer.lua** — add all keywords: `params`, `vars`, `repeat`, `compare`, `equal`, `larger`, `smaller`, `foreach`, `if`, `then`, `else`, `end`, `break`, `goto`, `function`, `return`, `not`
2. **beh/ast.lua** — define node types for all constructs
3. **beh/parser.lua** — complete parser for all statement/expression types
4. **codegen.lua** — walk AST and emit numbered instruction JSON matching Example.json format
5. Wire up in **main.lua** and test against known `.beh` + expected `.json`

## Running

```sh
lua main.lua            # parses src2.beh, prints AST
lua main.lua --example  # decodes Example.base -> Example.json
```

Requires: Lua 5.x, Node.js (for dsconvert.js), `dkjson` Lua library, and `ext.*` libraries (ext.class, ext.table, ext.string, ext.assert).
