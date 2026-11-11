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
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import glua  # noqa: E402
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


def appearance_mod_source():
    """The menu file of the Z-City Appearance Mod (apperance.zip in the repository root), unpacked
    for the scenario in lua_tests/test_appmod.lua. None when the archive is not there."""
    archive = os.path.join(os.path.dirname(HERE), 'apperance.zip')
    if not os.path.isfile(archive):
        return None
    with zipfile.ZipFile(archive) as z:
        for name in z.namelist():
            if name.endswith('appearancemod_buttons.lua'):
                text = z.read(name).decode('utf-8-sig', 'replace').replace('\r\n', '\n')
                fd, path = tempfile.mkstemp(prefix='zcg_appmod_', suffix='.lua')
                with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f:
                    f.write(text)
                return path
    return None


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

    # The Lua of the drop-in archives is in the dialect of the game: compiled after a conversion.
    # A problem there is printed but does not fail the run - those files are not ours to fix.
    dropin = 0
    for archive in L.dropin_archives(ROOT):
        if not archive.lower().endswith('.zip'):
            continue
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                dest = None if info.is_dir() else L.dropin_destination(L.zip_name(info))
                if dest and dest.endswith('.lua'):
                    dropin += 1
                    err = compile_(glua.to_lua(z.read(info).decode('utf-8-sig', 'replace')), dest)
                    if err:
                        print('WARNING %s: %s' % (os.path.basename(archive), err))
    if dropin:
        print('syntax: %d Lua files of the drop-in archives checked' % dropin)

    # where the files of a drop-in archive go
    rules = {
        'z_city_appearance_mod/addon.json': None,
        'z_city_appearance_mod/lua/autorun/client/zzz_hg_appearance_patch.lua': 'lua/autorun/client/zzz_hg_appearance_patch.lua',
        'pack/addon 2/homigrad/new_appearance/sh_shared_bib.lua': 'lua/homigrad/new_appearance/sh_shared_bib.lua',
        'pack/addon 2.json': None,
        'pack/lua/autorun/sh_zcity_armbands.lua': 'lua/autorun/sh_zcity_armbands.lua',
        'Pack/Materials/Models/Humans/Male/Group01/Bib.VMT': 'materials/models/humans/male/group01/bib.vmt',
        'pack/models/zcband/band_team.mdl': 'models/zcband/band_team.mdl',
        'models/humans/male/group01/bib.vtf': 'materials/models/humans/male/group01/bib.vtf',
        'materials/models/humans/male/group01/bib.vtf': 'materials/models/humans/male/group01/bib.vtf',
        'addon\\sound\\zc\\step.wav': 'sound/zc/step.wav',
        'bib.vmt': None,
        'readme.txt': None,
        'a/../lua/x.lua': None,
        'lua': None,
    }
    for path, want in sorted(rules.items()):
        got = L.dropin_destination(path)
        if got != want:
            failed += 1
            print('RULE    %s -> %s, expected %s' % (path, got, want))
    print('drop-in rules: %d checked' % len(rules))

    mod_source = appearance_mod_source()
    if mod_source is None:
        print('note: apperance.zip is not in the repository, test_appmod.lua has nothing to run')

    for name in sorted(os.listdir(TESTS)):
        if not (name.startswith('test_') and name.endswith('.lua')):
            continue
        rt = runtime()  # a fresh Lua state per file: the mock replaces globals
        if mod_source is not None:
            rt.globals().ZCG_APPMOD_BUTTONS = mod_source.replace('\\', '/')
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

    if mod_source is not None:
        os.remove(mod_source)
    print('RESULT: %s' % ('OK' if not failed else '%d problem(s)' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
