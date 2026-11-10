#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Run the addon's Lua code outside of the game.

    pip install lupa
    python tools/test_lua.py [path/to/another/lua/folder]

1. every Lua file of the addon is compiled with LuaJIT (the Lua dialect of Garry's Mod without
   its C-style extensions, which the addon does not use);
2. the scenarios in tools/lua_tests/ are executed against a small imitation of the Garry's Mod
   API and of the parts of Z-City the addon talks to.

This catches typos, nil calls and logic mistakes. It does NOT replace a test in the game: the
imitation only behaves the way the author believes the game behaves.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import zcg_layout as L  # noqa: E402

LUA_ROOT = os.path.normpath(os.path.join(HERE, '..', L.ADDON_DIRNAME, 'lua'))
TESTS = os.path.join(HERE, 'lua_tests')


def runtime():
    try:
        from lupa import luajit21 as lua
    except ImportError:
        try:
            from lupa import luajit20 as lua
        except ImportError:
            try:
                from lupa import lua51 as lua
            except ImportError:
                raise SystemExit('lupa with LuaJIT or Lua 5.1 is required: pip install lupa')
    return lua.LuaRuntime(unpack_returned_tuples=True)


def main():
    global LUA_ROOT
    if len(sys.argv) > 1:  # another copy of the addon's lua folder
        LUA_ROOT = os.path.abspath(sys.argv[1])
    failed = 0

    rt = runtime()
    compile_ = rt.eval('function(src, name) local f, err = loadstring(src, "@" .. name) if f then return nil end return err end')
    count = 0
    for dp, _, files in os.walk(LUA_ROOT):
        for fn in sorted(files):
            if not fn.endswith('.lua'):
                continue
            path = os.path.join(dp, fn)
            with open(path, encoding='utf-8') as f:
                err = compile_(f.read(), os.path.relpath(path, LUA_ROOT))
            count += 1
            if err:
                failed += 1
                print('SYNTAX  %s' % err)
    print('syntax: %d files checked' % count)

    for name in sorted(os.listdir(TESTS)):
        if not (name.startswith('test_') and name.endswith('.lua')):
            continue
        rt = runtime()  # a fresh Lua state per file: the mock replaces globals
        run = rt.eval('function(path, testdir, luaroot)\n'
                      '  local ok, a, b = xpcall(function() return dofile(path)(testdir, luaroot) end, debug.traceback)\n'
                      '  if not ok then return -1, a end\n'
                      '  return a, table.concat(b, "\\n")\n'
                      'end')
        checks, text = run(os.path.join(TESTS, name).replace('\\', '/'), TESTS.replace('\\', '/'), LUA_ROOT.replace('\\', '/'))
        if checks == -1:
            failed += 1
            print('%-18s CRASHED\n%s' % (name, text))
            continue
        problems = [line for line in (text or '').split('\n') if line]
        failed += len(problems)
        print('%-18s %d checks, %d failed' % (name, checks, len(problems)))
        for line in problems:
            print('    FAILED  ' + line)

    print('RESULT: %s' % ('OK' if not failed else '%d problem(s)' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
