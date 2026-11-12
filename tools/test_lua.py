#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Run the addon's Lua code outside of the game.

    pip install lupa
    python tools/test_lua.py [path/to/another/lua/folder]

1. every Lua file of the addon is compiled with LuaJIT (the Lua dialect of Garry's Mod without
   its C-style extensions, which the addon does not use);
2. the Lua of the clothing packs is run the way the build runs it (tools/lua_names.py) and the
   names it puts into the appearance tables are checked - with made-up files for the rules, and
   with the real ones of the drop-in archives;
3. the scenarios in tools/lua_tests/ are executed against a small imitation of the Garry's Mod
   API and of the parts of Z-City the addon talks to.

This catches typos, nil calls and logic mistakes. It does NOT replace a test in the game: the
imitation only behaves the way the author believes the game behaves.
"""
import collections
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import glua  # noqa: E402
import list_content  # noqa: E402
import lua_names  # noqa: E402
import zcg_layout as L  # noqa: E402

LUA_ROOT = os.path.normpath(os.path.join(HERE, '..', L.ADDON_DIRNAME, 'lua'))
TESTS = os.path.join(HERE, 'lua_tests')
LEGACY = 'Z-City Appearance Mod LEGACY'


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
    """The menu file of the Z-City Appearance Mod - of the version of it the build takes out of
    the drop-in archives - unpacked for the scenario in lua_tests/test_appmod.lua. Returns (the
    file, the title of its pack), or (None, None) when no archive brings it."""
    for dest, data, _archive, title in L.dropin_lua(ROOT)[0]:
        if dest.endswith('appearancemod_buttons.lua'):
            text = data.decode('utf-8-sig', 'replace').replace('\r\n', '\n')
            fd, path = tempfile.mkstemp(prefix='zcg_appmod_', suffix='.lua')
            with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f:
                f.write(text)
            return path, title
    return None, None


# ---- GLua that is run: `continue` --------------------------------------------------------------
CONTINUE = [
    ('a for loop', '''
        local out = {}
        for i = 1, 6 do
            if i % 2 == 0 then continue end
            local x = i * 10
            out[#out + 1] = x
        end
        return table.concat(out, ",")''', '10,30,50'),
    ('nested loops, a body that ends in a return', '''
        local function f(t)
            for k, v in ipairs(t) do
                if !v then continue end
                for j = 1, 3 do
                    if j == 2 then continue end
                    if j == 3 && v == "stop" then return "stopped at " .. k end
                end
                if v == "x" then continue end
                return v
            end
        end
        return f({false, "x", "stop"}) .. "|" .. f({false, "x", "y"})''', 'stopped at 3|y'),
    ('a while loop', '''
        local i, s = 0, 0
        while i < 10 do
            i = i + 1
            if i > 5 then continue end
            s = s + i
        end
        return s''', 15),
    ('a repeat loop', '''
        local i, s = 0, 0
        repeat
            i = i + 1
            if i == 2 then continue end
            s = s + i
        until i >= 4
        return s''', 8),
    ('a function made in a loop, with a loop of its own', '''
        local fs = {}
        for i = 1, 3 do
            if i == 2 then continue end
            fs[#fs + 1] = function()
                local t = 0
                for j = 1, 4 do
                    if j == i then continue end
                    t = t + j
                end
                return t
            end
        end
        return fs[1]() .. "," .. fs[2]()''', '9,7'),
    ('a function with a loop in the head of a loop', '''
        local s = ""
        for _, v in ipairs((function() local t = {} for i = 1, 3 do if i == 2 then continue end t[#t + 1] = i end return t end)()) do
            if v == 1 then continue end
            s = s .. v
        end
        return s''', '3'),
    ('a block inside a loop; comments and strings that say continue', '''
        local s = 0 // continue
        /* continue */
        local text = "continue" .. [[ continue ]]
        for i = 1, 4 do
            do
                local y = i
                if y == 3 then continue end
                s = s + y
            end
            s = s + 100
        end
        return s .. text''', '307continue continue '),
    ('numbers are not words', '''
        local a, b = 1e2, 0x1F
        for i = 1, 2 do if i == 1 then continue end a = a + b end
        return a''', 131),
]


def names_tests():
    """Returns (checks, [what failed])."""
    checks, problems = [0], []

    def check(ok, text):
        checks[0] += 1
        if not ok:
            problems.append(text)

    rt = runtime()
    compiles = rt.eval('function(src) return (loadstring(src)) ~= nil end')
    for label, source, want in CONTINUE:
        try:
            got = rt.execute(glua.to_lua(source, run=True))
        except Exception as err:     # a syntax error of the converted text
            got = 'ERROR: %s' % err
        check(got == want, 'continue, %s: got %r, expected %r' % (label, got, want))
        check(compiles(glua.to_lua(source)), 'continue, %s: the form that is only compiled compiles' % label)
    plain = 'for i = 1, 3 do s = s + i end while s < 9 do s = s + 1 end repeat s = s + 1 until s > 11'
    check(glua.to_lua(plain, run=True) == plain, 'a loop without continue is left as it is')

    # ---- the rules, with made-up files (and without the Lua of Z-City: its tables are made empty)
    def told(files, **kw):
        return lua_names.run(files, **kw)

    def errors_of(result, name):
        return sorted(set(message for _realm, path, message in result.errors if path == name))

    got = told({
        'autorun/zz_pack.lua': '''
            local entries = { {"Drill 07", "zcity_drill/sheet_16"}, {"Drill 08", "zcity_drill/sheet_31"} }
            for _, item in ipairs(entries) do
                hg.Appearance.Clothes[1][item[1]] = item[2]
                hg.Appearance.Clothes[2][item[1]] = item[2]
            end
            for i = 1, 4 do
                if i == 2 then continue end
                hg.Appearance.Clothes[1]["RP " .. i] = "zcity_rp/shirt_" .. i
            end
            hg.Appearance.Clothes[1].nothing = "null"
            hg.Appearance.Clothes[1].made = "!made_by_lua"
            hg.Appearance.Clothes[1].full = "materials/Models/Gate/Epl.vmt"
            hg.Appearance.PlayerModels[1]["Male 10"] = { mdl = "models/Slav/M/male_10.mdl" }
            hg.Appearance.FacemapsSlots["models/x/face"] = { ["Face 1"] = "models/x/face_1" }
            hg.Accessories.hat = { model = "models/x/hat.mdl", femmodel = "models/x/hat_f.mdl" }''',
    })
    want = ['materials/models/gate/epl.vmt', 'materials/models/x/face_1.vmt', 'materials/zcity_drill/sheet_16.vmt',
            'materials/zcity_drill/sheet_31.vmt', 'materials/zcity_rp/shirt_1.vmt', 'materials/zcity_rp/shirt_3.vmt',
            'materials/zcity_rp/shirt_4.vmt', 'models/slav/m/male_10.mdl', 'models/x/hat.mdl', 'models/x/hat_f.mdl']
    check(sorted(got.names) == want, 'names in a table, names put together, with and without materials/: %s' % sorted(got.names))
    check(not got.errors, 'such a file runs through: %s' % got.errors)
    check(got.names.get('materials/zcity_drill/sheet_16.vmt', {}).get('by') == 'autorun/zz_pack.lua',
          'the file that put a name there is known')
    check(got.names.get('materials/zcity_rp/shirt_3.vmt', {}).get('who') == 'male clothes RP 3', 'and what the name is for')
    # the entries of the tables themselves, for the list the game compares its tables with
    entries = got.entries['server']
    check(entries.get('Clothes/1/Drill 07') == ('zcity_drill/sheet_16', 'autorun/zz_pack.lua')
          and entries.get('Clothes/2/Drill 08') == ('zcity_drill/sheet_31', 'autorun/zz_pack.lua')
          and entries.get('Clothes/1/full') == ('materials/models/gate/epl.vmt', 'autorun/zz_pack.lua')
          and entries.get('PlayerModels/1/Male 10') == ('models/slav/m/male_10.mdl', 'autorun/zz_pack.lua')
          and entries.get('FacemapsSlots/models/x/face/Face 1') == ('models/x/face_1', 'autorun/zz_pack.lua')
          and entries.get('Accessories/hat/femmodel') == ('models/x/hat_f.mdl', 'autorun/zz_pack.lua'),
          'the entries of the tables are told, each with its value and its file: %s' % sorted(entries.items()))
    check(len(entries) == 12 and 'Clothes/1/nothing' not in entries and 'Clothes/1/made' not in entries
          and entries == got.entries['client'] and not got.if_installed,
          'what is no file is no entry; a file for both sides makes the same on both: %s' % sorted(entries))

    # the order of the files: Z-City's loader makes hg, its appearance file makes the tables
    got = told({
        'autorun/a_early.lua': 'hg.Appearance.Clothes[1].early = "models/a/early"',
        'autorun/z_late.lua': 'hg.Appearance.Clothes[1].late = "models/a/late"',
        'autorun/b_guarded.lua': '''
            local function add()
                if not hg or not hg.Appearance then return false end
                hg.Appearance.Clothes[1].guarded = "models/a/guarded"
                return true
            end
            if not add() then hook.Add("InitPostEntity", "b_guarded", add) end''',
    })
    check(sorted(got.names) == ['materials/models/a/guarded.vmt', 'materials/models/a/late.vmt'],
          'an autorun file that runs before the loader of Z-City does not reach its tables: %s' % sorted(got.names))
    check(errors_of(got, 'autorun/a_early.lua') == ["autorun/a_early.lua:1: attempt to index global 'hg' (a nil value)"],
          'and that is told as the error it is in the game: %s' % errors_of(got, 'autorun/a_early.lua'))
    stock = {'homigrad/new_appearance/sh_shared.lua': '''
        hg.Appearance = hg.Appearance or {}
        hg.Appearance.Clothes = { { normal = "models/humans/male/group01/normal" }, {} }
        hg.Appearance.PlayerModels = { {}, {} }
        hg.Appearance.FacemapsSlots = {}'''}
    files = dict(stock)
    files.update({
        'homigrad/new_appearance/sh_before.lua': 'hg.Appearance.Clothes[1].before = "models/a/before"',
        'homigrad/new_appearance/sh_shared_after.lua': 'hg.Appearance.Clothes[1].after = "models/a/after"',
        'homigrad/new_appearance/sv_server.lua': 'hg.Appearance.Clothes[1].server = "models/a/server"',
        'homigrad/new_appearance/cl_client.lua': 'hg.Appearance.Clothes[1].client = "models/a/client"',
        'homigrad/new_appearance/more/sh_folder.lua': 'hg.Appearance.Clothes[1].folder = "models/a/folder"',
        'homigrad/zz/tail_sv.lua': 'hg.Appearance.Clothes[1].tail = "models/a/tail"',
    })
    got = told(files, stock=list(stock))
    check(sorted(got.names) == ['materials/models/a/after.vmt', 'materials/models/a/folder.vmt', 'materials/models/a/server.vmt',
                                'materials/models/a/tail.vmt'],
          'files of a folder run in name order, then its folders: one before sh_shared.lua finds no tables: %s' % sorted(got.names))
    check(len(errors_of(got, 'homigrad/new_appearance/sh_before.lua')) == 1, 'and fails, as in the game')
    check(errors_of(got, 'homigrad/new_appearance/cl_client.lua') and not errors_of(got, 'homigrad/new_appearance/sv_server.lua'),
          '(so does a cl_ file there, "cl" comes before "sh"; an sv_ file comes after it)')
    check(got.stock == {'materials/models/humans/male/group01/normal.vmt'}, 'what the files of Z-City put there is kept apart: %s' % sorted(got.stock))
    check(got.ran['server'][:3] == ['autorun/loader.lua', 'homigrad/new_appearance/sh_before.lua', 'homigrad/new_appearance/sh_shared.lua']
          and 'homigrad/new_appearance/cl_client.lua' not in got.ran['server'] and 'homigrad/zz/tail_sv.lua' in got.ran['server']
          and 'homigrad/new_appearance/cl_client.lua' in got.ran['client'] and 'homigrad/new_appearance/sv_server.lua' not in got.ran['client']
          and 'homigrad/zz/tail_sv.lua' not in got.ran['client'],
          'sv_ and _sv files run on the server only, cl_ files on a client only: %s' % got.ran)

    # hooks, timers, include, file.Find, parts of the game that are not imitated
    got = told({
        'homigrad/new_appearance/sh_shared_hooks.lua': '''
            SomeFunctionOfTheGame("x")
            local w = ScrW() * 0.5 + SomeLibrary.Value
            MyPack = MyPack or {}
            if not MyPack.done then hg.Appearance.Clothes[1].once = "models/b/once" end
            MyPack.done = true
            hg.SomethingOfZCity.Call(1)
            hook.Add("Initialize", "pack", function() hg.Appearance.Clothes[1].init = "models/b/init" end)
            hook.Add("InitPostEntity", "pack", function()
                timer.Simple(5, function() hg.Appearance.Clothes[1].later = "models/b/later" end)
                local tries = 0
                timer.Create("pack", 0.25, 40, function()
                    tries = tries + 1
                    if tries < 3 then return end
                    hg.Appearance.Clothes[1].tried = "models/b/tried"
                    timer.Remove("pack")
                end)
            end)
            for _, name in ipairs((file.Find("mypack/*.lua", "LUA"))) do include("mypack/" .. name) end
            include("beside.lua")
            if CLIENT then hg.Appearance.Clothes[1].seen = "models/b/client" end
            if SERVER then AddCSLuaFile() util.AddNetworkString("pack") end''',
        'homigrad/new_appearance/beside.lua': 'hg.Appearance.Clothes[2].beside = "models/b/beside"',
        'mypack/one.lua': 'hg.Appearance.Clothes[2].one = "models/b/one"',
        'mypack/two.lua': 'local t = string.Explode("/", "models/b/two") hg.Appearance.Clothes[2].two = table.concat(t, "/")',
    })
    want = ['materials/models/b/%s.vmt' % name for name in ('beside', 'client', 'init', 'later', 'once', 'one', 'tried', 'two')]
    check(sorted(got.names) == want, 'hooks of the start, timers, include, file.Find, both sides: %s' % sorted(got.names))
    check(not got.errors, 'a part of the game that is not imitated does not stop a file: %s' % got.errors)
    check('SomeFunctionOfTheGame' in got.stubs and 'SomeLibrary' in got.stubs and 'hg.SomethingOfZCity' in got.stubs
          and 'MyPack' not in got.stubs, 'it is taken for one, a table the file makes itself is not: %s' % got.stubs)
    check('Clothes/1/seen' in got.entries['client'] and 'Clothes/1/seen' not in got.entries['server']
          and 'Clothes/1/later' in got.entries['server'], 'an entry only a client makes is told for the client only')

    # what a file adds only when its model or material is installed
    got = told({'homigrad/new_appearance/sh_shared_careful.lua': '''
        if file.Exists("models/d/found.mdl", "GAME") then hg.Appearance.PlayerModels[1].Found = { mdl = "models/d/found.mdl" } end
        if util.IsValidModel("models/d/valid.mdl") then hg.Appearance.PlayerModels[1].Valid = { mdl = "models/d/valid.mdl" } end
        hg.Appearance.Clothes[1].always = "models/d/always"'''})
    check(sorted(got.names) == ['materials/models/d/always.vmt', 'models/d/found.mdl', 'models/d/valid.mdl'],
          'a file that first asks whether a model is installed: its names are those of a game that has everything: %s' % sorted(got.names))
    check(got.if_installed == {'PlayerModels/1/Found', 'PlayerModels/1/Valid'},
          'and it is known which entries a game without those files rightly lacks: %s' % sorted(got.if_installed))

    # names that are not UTF-8 (a file saved as Windows-1251): Lua knows bytes, and so must this
    jacket, sweater = u'\u041a\u0443\u0440\u0442\u043a\u0430'.encode('cp1251'), u'\u0421\u0432\u0438\u0442\u0435\u0440'.encode('cp1251')
    source = (b'\xef\xbb\xbfhg.Appearance.Clothes[1]["' + jacket + b'"] = "pack/jacket"\n'
              b'hg.Appearance.Clothes[1]["' + sweater + b'"] = "pack/sweater"\n'
              b'hg.Appearance.Clothes[2]["' + u'\u041a\u0443\u0440\u0442\u043a\u0430 "x"'.encode('utf-8').replace(b'"', b'\\"') + b'"] = "pack/utf"\n')
    name = 'homigrad/new_appearance/sh_shared_cyrillic.lua'
    got = told({name: lua_names.lua_text(source)})
    check(sorted(got.names) == ['materials/pack/jacket.vmt', 'materials/pack/sweater.vmt', 'materials/pack/utf.vmt'] and not got.errors,
          'two names that are not UTF-8 stay two names: %s %s' % (sorted(got.names), got.errors))
    keys = sorted(lua_names.lua_bytes(key) for key in got.entries['server'])
    check(keys == sorted([b'Clothes/1/' + jacket, b'Clothes/1/' + sweater, u'Clothes/2/\u041a\u0443\u0440\u0442\u043a\u0430 "x"'.encode('utf-8')]),
          'and the entries come back byte for byte: %s' % keys)
    check(lua_names.lua_bytes(lua_names.lua_text(source)) == source[3:] and list_content.lua_fingerprint(lua_names.lua_text(source))
          == list_content.lua_fingerprint(source.decode('utf-8-sig', 'replace')),
          'a file read byte for byte gives its bytes back, and has the fingerprint sort_content.py makes of it')
    old = told({name: source.decode('utf-8-sig', 'replace')})
    check(len(old.names) == 2, '(read with question marks for what is not UTF-8 - as up to 2.3 - the two would be one: %s)' % sorted(old.names))

    # the list of the build, read back by the check of the addon itself (ZCG.BoundMissing)
    files = {'homigrad/new_appearance/sh_shared_pack.lua': '''
        hg.Appearance.Clothes[1].shirt = "models/e/shirt"
        if CLIENT then hg.Appearance.Clothes[1].seen = "models/e/seen" end'''}
    listed = '''ZCGloves.Bound = { ["homigrad/new_appearance/sh_shared_pack.lua"] = {
        { "Clothes/1/shirt", "models/e/shirt" }, { "Clothes/1/seen", "models/e/seen", 2 }, { "Clothes/1/gone", "models/e/gone" } } }'''
    got = told(files, bound=listed)
    check(got.bound == {'server': (2, [('Clothes/1/gone', 'models/e/gone', 'homigrad/new_appearance/sh_shared_pack.lua', None)]),
                        'client': (3, [('Clothes/1/gone', 'models/e/gone', 'homigrad/new_appearance/sh_shared_pack.lua', None)])},
          'a list is read back by the check of the addon, each side with its entries: %s' % got.bound)
    check(told(files).bound == {}, 'without a list there is nothing to read back')

    # a name that a later file replaces or drops
    got = told({
        'homigrad/new_appearance/sh_shared_a.lua': '''
            hg.Appearance.Clothes[1].jacket = "models/a/jacket"
            hg.Appearance.Clothes[1].shirt = "models/a/shirt"
            hg.Appearance.Clothes[1].keeps = "models/a/keeps"''',
        'homigrad/new_appearance/sh_shared_b.lua': '''
            hg.Appearance.Clothes[1].jacket = "models/b/jacket"
            hg.Appearance.Clothes[1].shirt = nil
            hg.Appearance.Clothes[1].keeps = "Models/A/Keeps"''',
    })
    lost = [(entry['path'], entry['by'], entry['during'], entry['now']) for entry in got.lost]
    check(lost == [('materials/models/a/jacket.vmt', 'homigrad/new_appearance/sh_shared_a.lua', 'homigrad/new_appearance/sh_shared_b.lua',
                    'materials/models/b/jacket.vmt'),
                   ('materials/models/a/shirt.vmt', 'homigrad/new_appearance/sh_shared_a.lua', 'homigrad/new_appearance/sh_shared_b.lua', None)],
          'a name one file put there and a later one replaced or dropped is told: %s' % lost)
    check(sorted(got.names) == ['materials/models/a/keeps.vmt', 'materials/models/b/jacket.vmt'], 'the tables at the end: %s' % sorted(got.names))

    # an error half-way
    got = told({'homigrad/new_appearance/sh_shared_broken.lua': '''
        hg.Appearance.Clothes[1].first = "models/c/first"
        local t = nil
        t.x = 1
        hg.Appearance.Clothes[1].second = "models/c/second"'''})
    check(sorted(got.names) == ['materials/models/c/first.vmt'], 'a file that breaks half-way: what it did before counts: %s' % sorted(got.names))
    check(errors_of(got, 'homigrad/new_appearance/sh_shared_broken.lua')
          == ["homigrad/new_appearance/sh_shared_broken.lua:4: attempt to index local 't' (a nil value)"],
          'and the error is told with its line: %s' % got.errors)

    # ---- the real Lua of the drop-in archives, on top of Z-City's own
    files = dict((path, text) for path, (text, _archive) in lua_names.dropin_files(ROOT).items())
    if not files or not lua_names.stock_files():
        print('note: the drop-in archives or z_city.zip are not in the repository: their Lua is not run')
        return checks[0], problems
    got = lua_names.run_addon(files)[0]
    check(not got.errors, 'every Lua file of the drop-in archives runs through: %s' % got.errors)
    drill = sorted(name for name in got.names if name.startswith('materials/zcity_drill/'))
    check(len(drill) == 22 and 'materials/zcity_drill/sheet_16.vmt' in drill and 'materials/zcity_drill/players_sheet_02.vmt' in drill,
          'the 22 materials of the Drill clothes are found: %s' % drill)
    check(set(got.names[name]['by'] for name in drill) == {'autorun/zcity_drill_clothes.lua'}, 'with the file that names them')
    for realm in lua_names.REALMS:
        bound = sorted(key for key, (_value, by) in got.entries[realm].items() if by == 'autorun/zcity_drill_clothes.lua')
        check(len(bound) == 44 and 'Clothes/1/Drill 07' in bound and 'Clothes/2/Drill 22' in bound,
              'on the %s the Drill clothes are 22 entries for each sex: %d' % (realm, len(bound)))
    check(not got.if_installed, 'no entry of these packs waits for its file to be installed: %s' % sorted(got.if_installed))
    text = set()
    for source in files.values():
        text |= list_content.names_in(source)
    text -= list_content.stock_names()
    check(not [name for name in drill if name in text], '(the text of that file does not show them)')
    # (the Appearance Mod has two versions, zcg_layout.PACK_VERSIONS: the numbers are those of the
    # one the build takes - the other one with --pack)
    legacy = LEGACY in set(title for _dest, _data, _archive, title in L.dropin_lua(ROOT)[0])
    faces = sorted(name for name in set(got.names) - text if '_facemap' in name)
    check(len(faces) == (12 if legacy else 13) and 'materials/models/bloo_ltcom_zel/citizens/facemaps/lake_facemap6.vmt' in faces,
          'and %d faces whose names are put together in loops: %s' % (12 if legacy else 13, faces))
    check(sorted(set(got.names) - text) == sorted(drill + faces), 'nothing else is found by running only: %s'
          % sorted(set(got.names) - text - set(drill) - set(faces)))
    check('materials/null.vmt' not in got.names, '"null", the material that draws nothing, is no file to look for')
    check(len(got.stock) > 150 and 'materials/models/humans/male/group01/normal.vmt' in got.stock
          and not (got.stock & set(got.names)), 'the names of Z-City itself are kept apart (%d)' % len(got.stock))
    kinds = sorted(set(entry['entry'].split('/')[0] for entry in got.lost))
    check(kinds == ['PlayerModels'], 'only player models are replaced by a later file, no clothes and no faces: %s' % kinds)
    own = [entry for entry in got.lost if entry['by'] not in lua_names.stock_files()]
    if legacy:
        check(not own, 'the LEGACY Appearance Mod leaves the player models of Clothing+ as they are: %d' % len(own))
    else:
        check(len(own) == 15 and all(entry['path'].startswith('models/zcityadodser/') and entry['now'].startswith('models/slav/')
                                     for entry in own), 'the 15 of Clothing+, by those of the Appearance Mod: %d' % len(own))
    ported = lua_names.run_addon(files, port=True)[0]
    check(got.ran == ported.ran and got.names == ported.names and got.lost == ported.lost and got.stock == ported.stock,
          'the copy of the loader of Z-City loads the files in the order the loader itself does')
    patch = 'autorun/client/zzz_hg_appearance_patch.lua'     # (only the version that is not LEGACY has it)
    check(got.ran['server'][0] == 'autorun/loader.lua' and 'autorun/zcity_drill_clothes.lua' in got.ran['server']
          and (patch in got.ran['client']) == (not legacy) and patch not in got.ran['server'],
          'the autorun files run, each on its side')
    again = lua_names.run_addon(files)[0]
    check(again.names == got.names and again.lost == got.lost, 'running it twice tells the same')
    listed = dict((title, wanted) for _archive, title, wanted in list_content.collect()[0])
    check(len(listed.get('[ZCITY] Drill Clothes', ())) == 22, 'the listing of tools/list_content.py has the Drill clothes: %s'
          % sorted(listed))

    # ---- two versions of one pack: one is taken whole, the other is left out whole
    current = 'Z-City Appearance Mod'
    titles = collections.Counter(title for _dest, _data, _archive, title in L.dropin_lua(ROOT)[0])
    out = L.dropin_lua(ROOT)[1]
    check((LEGACY in titles) != (current in titles) and len(out) == 1 and out[0][0] == (current if legacy else LEGACY)
          and out[0][1] == (LEGACY if legacy else current),
          'of the two versions of the Appearance Mod one is taken: %s; left out: %s'
          % (sorted(title for title in titles if title in (LEGACY, current)), [entry[:3] for entry in out]))
    paths = [dest for dest, _data, _archive, _title in L.dropin_lua(ROOT)[0]]
    check(len(paths) == len(set(paths)), 'and so no Lua file comes twice: %s'
          % sorted(dest for dest in set(paths) if paths.count(dest) > 1))
    for chosen, taken_title, count, left_count in (([], current, 5, 4), ([LEGACY], LEGACY, 4, 5), ([current], current, 5, 4)):
        taken, left = L.dropin_lua(ROOT, chosen=chosen)
        mine = [dest for dest, _data, _archive, title in taken if title == taken_title]
        check(len(mine) == count and len(left) == 1 and len(left[0][3]) == left_count
              and not [title for _dest, _data, _archive, title in taken if title == left[0][0]],
              'asked for %s: the %d Lua files of "%s" are taken, the %d of the other version are not: %d, %s'
              % (chosen or 'nothing', count, taken_title, left_count, len(mine), [(e[0], len(e[3])) for e in left]))
    other = dict((title, wanted) for _archive, title, _instead, wanted in list_content.left_out())
    spare = sorted(other.get(current if legacy else LEGACY, ()))
    if legacy:
        check(len(spare) > 50 and 'models/slav/m/male_10.mdl' in spare and not [name for name in spare if name in got.names],
              'the files only the other version names are known: %d' % len(spare))
    else:
        check(len(spare) == 15 and len([name for name in spare if name.startswith('models/zcity/')]) == 13
              and 'models/zcity/m/male_10.mdl' in spare and 'materials/models/humans/slav/mossman/mossman_face.vmt' in spare
              and not [name for name in spare if name in got.names],
              'the files only the LEGACY version names are known - 13 models and 2 materials: %s' % spare)
    check(not [name for name in spare if any(name in wanted for wanted in listed.values())],
          'and none of them is in the listing of the build')
    # the version that is left out runs through as well: it can be built with --pack
    saved = list(L.CHOSEN_PACKS)
    L.CHOSEN_PACKS[:] = [current if legacy else LEGACY]
    try:
        swapped = dict((path, text) for path, (text, _archive) in lua_names.dropin_files(ROOT).items())
    finally:
        L.CHOSEN_PACKS[:] = saved
    theirs = lua_names.run_addon(swapped)[0]
    check(not theirs.errors and len(theirs.names) > 500 and set(theirs.names) != set(got.names),
          'the Lua of the other version runs through too, and names other files: %d names, %s' % (len(theirs.names), theirs.errors))
    check(L.versions_left_out(['a', 'b']) == {} and L.versions_left_out([LEGACY]) == {} and L.versions_left_out([current]) == {}
          and L.versions_left_out([LEGACY, current, 'a'], chosen=[]) == {LEGACY: current}
          and L.versions_left_out([LEGACY, current], chosen=[LEGACY]) == {current: LEGACY}
          and L.versions_left_out([LEGACY, current], chosen=['a']) == {LEGACY: current},
          'the rule: of the versions that are there the first one listed, or the one that was asked for')
    return checks[0], problems


def main():
    global LUA_ROOT
    args = sys.argv[1:]
    # --pack TITLE: as for build_addon.py - the version of a pack to take (zcg_layout.PACK_VERSIONS)
    while '--pack' in args:
        at = args.index('--pack')
        if at + 1 >= len(args):
            raise SystemExit('--pack needs the title of a pack')
        L.CHOSEN_PACKS.append(args[at + 1])
        del args[at:at + 2]
    if args:  # another copy of the addon's lua folder
        LUA_ROOT = os.path.abspath(args[0])
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
    # (a pack that is a version of one the build takes is left out there, and here)
    dropin = 0
    taken, left_out = L.dropin_lua(ROOT)
    for dest, data, archive, _title in taken:
        dropin += 1
        err = compile_(glua.to_lua(data.decode('utf-8-sig', 'replace')), dest)
        if err:
            print('WARNING %s: %s' % (archive, err))
    if dropin:
        print('syntax: %d Lua files of the drop-in archives checked' % dropin)
    for title, instead, archive, files in left_out:
        for dest, data in files:
            err = compile_(glua.to_lua(data.decode('utf-8-sig', 'replace')), dest)
            if err:
                print('WARNING %s: %s' % (archive, err))
        print('note: "%s" (%s) is a version of "%s", which is the one the build takes. Its %d Lua files are checked '
              'as well, and are not in the build: python tools/test_lua.py --pack "%s" runs everything with them'
              % (title, archive, instead, len(files), title))

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

    checks, problems = names_tests()
    failed += len(problems)
    print('%-18s %d checks, %d failed' % ('names by running', checks, len(problems)))
    for line in problems:
        print('    FAILED  ' + line)

    mod_source, mod_title = appearance_mod_source()
    if mod_source is None:
        print('note: no drop-in archive brings the Appearance Mod, test_appmod.lua has nothing to run')
    elif L.CHOSEN_PACKS:
        print('note: the scenarios run with the menu of "%s"' % mod_title)

    for name in sorted(os.listdir(TESTS)):
        if not (name.startswith('test_') and name.endswith('.lua')):
            continue
        rt = runtime()  # a fresh Lua state per file: the mock replaces globals
        if mod_source is not None:
            rt.globals().ZCG_APPMOD_BUTTONS = mod_source.replace('\\', '/')
            rt.globals().ZCG_APPMOD_TITLE = mod_title
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
