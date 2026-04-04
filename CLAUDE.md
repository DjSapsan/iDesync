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

### Key opcodes

- `turnon` / `shutdown` — Enable/disable component
- `unlock` / `lock_slots` — Slot management
- `set_reg` — Assign value to register: `0`=dest, `1`=src
- `wait` — Wait N ticks: `0`={num=N}
- `jump` — Unconditional jump: `0`=label id
- `label` — Jump target: `0`=label id
- `call` — Call sub-behavior: `0`=arg, `sub`=sub-index
- `for_inventory_item` — foreach loop over inventory
- `for_signal_match` — foreach loop over signals
- `check_number` — Conditional branch: `0`=next-if-false, `2`=value
- `is_a` — Type check
- `domove` — Move command
- `dodrop` — Drop items
- `notify` — Show notification
- `exit` — End execution
- `event_parameter` — Declare parameter

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
  lua/                      -- Lua reference parser (for reference)
  grammar/                  -- grammar-based parser (for reference)
```

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
