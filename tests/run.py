"""Run with Python + lupa (Lua 5.4): python tests/run.py"""
import os
from pathlib import Path
from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[1]
os.chdir(root)
lua = LuaRuntime(unpack_returned_tuples=True)
check = lua.eval("function(s,n) local f,e=load(s,n); return f ~= nil,e end")
files = list(root.rglob("*.lua"))
for file in files:
    ok, error = check(file.read_text(encoding="utf-8"), str(file))
    assert ok, error
print(f"PASS: {len(files)} Lua files compile in Lua 5.4", flush=True)
table = root.parent / "noted_knucklebones"
for name in ("shared/game.lua", "server/match.lua"):
    if (table / name).exists():
        assert (table / name).read_bytes() == (root / name).read_bytes(), f"{name} drifted from noted_knucklebones"
print("PASS: rules and match logic identical to noted_knucklebones", flush=True)
lua.execute("dofile('shared/game.lua'); dofile('server/match.lua'); dofile('tests/phone.lua')")
