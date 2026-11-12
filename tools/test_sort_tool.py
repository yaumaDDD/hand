#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests sort_content as it is shipped: the folder the build puts into the addon, started the way
its owner starts it.

    python tools/test_sort_tool.py

An addon is made up in a temporary folder - its Lua, its own content, clothing content dropped in
by hand - with the scripts the build ships (build_addon.step_sort_tool) and sort_content.bat next
to them. Then:
  * everywhere: the script is run by a Python that knows nothing but its own library ("-I", like
    the portable Python sort_content.bat fetches), from another folder; once more with Lua that
    names its materials in a table, and the list of names the build makes for that by running it;
    and with the folders of an owner thrown at the addon the way he collects them - materials1,
    models2 ... in materials, in models, beside them, handed over; and in the addons folder of
    a made-up game, whose archives it has to look into for what the addon lacks;
  * on Windows: sort_content.bat itself is run, with the Python that is installed and - when
    ZCG_TEST_PORTABLE is set, it needs the internet - with the portable one it fetches, kept in a
    folder with a Russian name as the profile of a Russian user has.
The logic itself is tested in tools/test_content.py; this is about the packaging.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT)
import build_addon  # noqa: E402
import sort_content  # noqa: E402
import test_content as T  # noqa: E402
import zcg_layout as L  # noqa: E402

check = T.check
BAT = 'sort_content.bat'


def shipped(folder):
    """an installed addon with content to sort; returns {path: content} as it has to be afterwards"""
    files = T.an_addon(folder)
    build_addon.step_sort_tool(folder)
    shutil.copyfile(os.path.join(ROOT, L.ADDON_DIRNAME, BAT), os.path.join(folder, BAT))
    want = dict((T.SORTED.get(rel, rel), data if isinstance(data, bytes) else data.encode('utf-8'))
                for rel, data in files.items())
    return want


def Told(names):
    """what running the Lua tells (a lua_names.Result), written by hand where Lua cannot be run"""
    result = build_addon.lua_names.Result()
    result.names = dict((name, {'by': T.TABLE_LUA, 'who': 'clothes'}) for name in names)
    return result


def shipped_with_names(folder):
    """an installed addon whose Lua names materials in a table, with the list of them the build
    leaves for the tool. Returns (was the Lua really run, the names in the list)."""
    T.a_table_addon(folder)
    ran = build_addon.run_lua(folder)
    real = ran['result'] is not None
    if not real:
        ran['result'] = Told(T.TABLE_NAMES)
    _scripts, _stock, listed = build_addon.step_sort_tool(folder, ran)
    return real, listed


def shipped_thrown(folder, how, outside):
    """an installed addon with numbered folders thrown at it (test_content.thrown); returns
    ({path: content} as it has to be afterwards, what to hand to the tool)"""
    want, handed = T.thrown(folder, how, outside)
    build_addon.step_sort_tool(folder)
    shutil.copyfile(os.path.join(ROOT, L.ADDON_DIRNAME, BAT), os.path.join(folder, BAT))
    return want, handed


def result(folder):
    """the files of the addon without the tool, its report and the list the build writes for the game"""
    got = T.tree(folder)
    report = got.pop(sort_content.REPORT, None)
    got.pop('lua/' + build_addon.BOUND_LUA, None)
    for rel in list(got):
        if rel == BAT or rel.startswith(build_addon.SORT_TOOL_DIR + '/'):
            del got[rel]
    return got, report


def show(label, done):
    text = (done.stdout or b'').decode('utf-8', 'replace')
    print('---- %s: exit code %s' % (label, done.returncode))
    for line in text.splitlines()[-25:]:
        print('    ' + line.encode('ascii', 'backslashreplace').decode('ascii'))


def start(bat, *dropped, **kw):
    """Starts a batch file the way Windows does on a double click, or when folders are dropped
    onto it: cmd.exe /c ""the file" "what was dropped"" - the whole line in quotes of its own, so
    that a "&" in a name stays a part of the name."""
    line = u' '.join(u'"%s"' % part for part in (bat,) + dropped)
    return subprocess.run(u'cmd.exe /d /c "%s"' % line, **kw)


def judge(label, folder, want, done):
    got, report = result(folder)
    check(done.returncode == 0, '%s: exit code %s' % (label, done.returncode))
    check(sorted(got) == sorted(want), '%s: every file is at its place; only in one of the two: %s'
          % (label, sorted(set(got) ^ set(want))))
    check(got == want, '%s: no file was changed' % label)
    check(report is not None and report.startswith(b'\xef\xbb\xbf'), '%s: the report is written' % label)
    check(not any('__pycache__' in base for base, _dirs, _files in os.walk(folder)),
          '%s: Python leaves no cache folder in the addon' % label)
    text = (report or b'').decode('utf-8-sig', 'replace')
    check(u'models/humans/male/group01/normal' not in text and u'materials/models/gate/gone.vmt' in text,
          '%s: the list of the names of Z-City is used' % label)
    if done.returncode != 0 or got != want:
        show(label, done)


def main():
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='replace')
    tmp = tempfile.mkdtemp(prefix='zcg_tool_')
    quiet = dict(stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        # ---- the script alone, by a Python that sees nothing but its own library
        addon = os.path.join(tmp, u'Program Files (x86)', u'\u0438\u0433\u0440\u0430', 'addons', L.ADDON_DIRNAME)
        want = shipped(addon)
        script = os.path.join(addon, build_addon.SORT_TOOL_DIR, 'sort_content.py')
        names = sorted(os.listdir(os.path.dirname(script)))
        check(names == sorted(build_addon.SORT_TOOL + ('stock_names.txt',)), 'the shipped folder holds the scripts and the list: %s' % names)
        env = dict(os.environ, PYTHONIOENCODING='utf-8')
        env.pop('PYTHONPATH', None)
        done = subprocess.run([sys.executable, '-I', '-B', script], cwd=tmp, env=env, **quiet)
        judge('the shipped script', addon, want, done)
        text = done.stdout.decode('utf-8', 'replace')
        check(u'\u0413\u043e\u0442\u043e\u0432\u043e' in text, 'it tells in Russian that it is done')

        # ---- names that only running the Lua shows: the build leaves them beside the script
        addon = os.path.join(tmp, u'names (1)', 'addons', L.ADDON_DIRNAME)
        real, listed = shipped_with_names(addon)
        script = os.path.join(addon, build_addon.SORT_TOOL_DIR, 'sort_content.py')
        names = sorted(os.listdir(os.path.dirname(script)))
        check(names == sorted(build_addon.SORT_TOOL + ('stock_names.txt', 'lua_names.txt')),
              'the shipped folder holds the list of the names found by running: %s' % names)
        check(listed == 3, 'the three names of the made-up Lua are in it (%s; the Lua was %s)'
              % (listed, 'run' if real else 'not run here: written by hand'))
        check(real == os.path.isfile(os.path.join(addon, 'lua', build_addon.BOUND_LUA)),
              'where the Lua was run the build leaves the list of what it adds for the game (and only there)')
        done = subprocess.run([sys.executable, '-I', '-B', script], cwd=tmp, env=env, **quiet)
        got, report = result(addon)
        text = done.stdout.decode('utf-8', 'replace')
        check(done.returncode == 0 and sorted(got) == T.TABLE_SORTED,
              'the shipped script puts a material named in a table at its own place, not at its namesake\'s: %s' % sorted(got))
        check(u'\u0412\u041d\u0418\u041c\u0410\u041d\u0418\u0415' not in text, 'and has nothing to warn of')
        if done.returncode != 0 or sorted(got) != T.TABLE_SORTED:
            show('the shipped script, names by running', done)

        # ---- folders thrown in the way they were collected: materials1, models2 ...
        for number, how in enumerate(T.THROWN):
            home = os.path.join(tmp, u'thrown (%d)' % number)
            addon = os.path.join(home, u'\u0430\u0434\u0434\u043e\u043d\u044b', L.ADDON_DIRNAME)
            want, handed = shipped_thrown(addon, how, os.path.join(home, u'\u043d\u0430\u0448\u0451\u043b \u043a\u043e\u043d\u0442\u0435\u043d\u0442'))
            script = os.path.join(addon, build_addon.SORT_TOOL_DIR, 'sort_content.py')
            done = subprocess.run([sys.executable, '-I', '-B', script] + handed, cwd=tmp, env=env, **quiet)
            got, report = result(addon)
            check(done.returncode == 0 and sorted(got) == sorted(want),
                  'the shipped script, numbered folders %s: every file is at its place; only in one of the two: %s'
                  % (how, sorted(set(got) ^ set(want))))
            check(got == want, 'the shipped script, numbered folders %s: no file was changed' % how)
            if done.returncode != 0 or got != want:
                show('the shipped script, numbered folders %s' % how, done)

        # ---- the game: what the addon lacks is looked for in the game it lies in
        # (the tests keep the tool away from a game that is installed here: ZCG_GAME, see
        # test_content.py - these two runs are the ones that look for it the way the owner's will)
        seeking = dict(env)
        seeking.pop('ZCG_GAME', None)
        game = os.path.join(tmp, u'Steam Library', 'steamapps', 'common', 'GarrysMod')
        addon = os.path.join(game, 'garrysmod', 'addons', L.ADDON_DIRNAME)
        want = shipped(addon)
        T.write(os.path.join(game, 'garrysmod', 'gameinfo.txt'), 'x')
        T.write(os.path.join(game, 'garrysmod', 'garrysmod_dir.vpk'), T.a_vpk(['materials/models/gate/gone.vmt'], version=2))
        T.write(os.path.join(game, 'garrysmod', 'addons', 'pack.gma'), T.a_gma('A Pack', ['materials/models/gate/other.vmt']))
        script = os.path.join(addon, build_addon.SORT_TOOL_DIR, 'sort_content.py')
        done = subprocess.run([sys.executable, '-I', '-B', script], cwd=tmp, env=seeking, **quiet)
        judge('the shipped script in the addons folder of a game', addon, want, done)
        text = done.stdout.decode('utf-8', 'replace')
        _got, report = result(addon)
        check(u'\u0418\u0433\u0440\u0430 \u043d\u0430 \u044d\u0442\u043e\u043c \u043a\u043e\u043c\u043f\u044c\u044e\u0442\u0435\u0440\u0435: %s' % game in text,
              'it finds the game the addon lies in: %r' % text[-1500:])
        check(u'materials/models/gate/gone.vmt    \u2014 \u0432 \u0430\u0434\u0434\u043e\u043d\u0435 \u043d\u0435\u0442; \u0412 \u0418\u0413\u0420\u0415 \u0415\u0421\u0422\u042c: '
              u'\u0430\u0440\u0445\u0438\u0432 \u0438\u0433\u0440\u044b garrysmod/garrysmod_dir.vpk' in (report or b'').decode('utf-8-sig', 'replace'),
              'and tells that the game has the file the addon lacks, in which archive')
        # ... and an addon that lies elsewhere looks for the game Steam has: found or not, it says which
        addon = os.path.join(tmp, u'\u0440\u0430\u0431\u043e\u0447\u0438\u0439 \u0441\u0442\u043e\u043b', L.ADDON_DIRNAME)
        want = shipped(addon)
        script = os.path.join(addon, build_addon.SORT_TOOL_DIR, 'sort_content.py')
        done = subprocess.run([sys.executable, '-I', '-B', script], cwd=tmp, env=seeking, **quiet)
        judge('the shipped script, looking for the game of this computer', addon, want, done)
        text = done.stdout.decode('utf-8', 'replace')
        said = [line for line in text.splitlines() if line.startswith(u'\u0418\u0433\u0440\u0430 \u043d\u0430 \u044d\u0442\u043e\u043c \u043a\u043e\u043c\u043f\u044c\u044e\u0442\u0435\u0440\u0435')]
        check(len(said) == 1, 'it says whether this computer has the game: %r' % text[-1500:])
        print('  the game of this computer: %s' % (said[0].encode('ascii', 'backslashreplace').decode('ascii') if said else '?'))

        if os.name != 'nt':
            print('  (not on Windows: sort_content.bat itself is not run)')
        else:
            env = dict(os.environ, ZCG_NO_PAUSE='1', PYTHONIOENCODING='utf-8')
            # ---- the batch file and numbered folders: thrown into the addon, then handed over
            for number, how in enumerate(T.THROWN):
                home = os.path.join(tmp, u'bat (%d)' % number)
                addon = os.path.join(home, u'Steam (x86)', L.ADDON_DIRNAME)
                want, handed = shipped_thrown(addon, how, os.path.join(home, u'\u043a\u043e\u043d\u0442\u0435\u043d\u0442 & more'))
                done = start(os.path.join(addon, BAT), *handed, cwd=tmp, env=env, **quiet)
                got, report = result(addon)
                check(done.returncode == 0 and sorted(got) == sorted(want),
                      'sort_content.bat, numbered folders %s: every file is at its place; only in one of the two: %s'
                      % (how, sorted(set(got) ^ set(want))))
                check(got == want, 'sort_content.bat, numbered folders %s: no file was changed' % how)
                check(not any('__pycache__' in base for base, _dirs, _files in os.walk(addon)),
                      'sort_content.bat, numbered folders %s: Python leaves no cache folder in the addon' % how)
                if done.returncode != 0 or got != want:
                    show('sort_content.bat, numbered folders %s' % how, done)
            # ---- the batch file, with the Python that is installed; a folder dropped onto it
            addon = os.path.join(tmp, u'Steam (x86)', u'\u0434\u0440\u0443\u0433\u043e\u0439 \u0430\u0434\u0434\u043e\u043d', L.ADDON_DIRNAME)
            want = shipped(addon)
            outside = os.path.join(tmp, u'content \u2014 \u043a\u043e\u043f\u0438\u044f & more')
            T.write(os.path.join(outside, 'materials', 'gate', 'jacket.vmt'), T.material('models/gate/jacket'))
            T.write(os.path.join(outside, 'materials', 'gate', 'jacket.vtf'), T.texture('jacket'))
            want['materials/models/gate/jacket.vmt'] = T.material('models/gate/jacket').encode('utf-8')
            want['materials/models/gate/jacket.vtf'] = T.texture('jacket')
            done = start(os.path.join(addon, BAT), outside, cwd=tmp, env=env, **quiet)
            judge('sort_content.bat', addon, want, done)
            show('sort_content.bat', done)

            # ---- a failure is passed on: no folder "sort_content" next to the batch file
            lonely = os.path.join(tmp, 'lonely')
            os.makedirs(lonely)
            shutil.copyfile(os.path.join(ROOT, L.ADDON_DIRNAME, BAT), os.path.join(lonely, BAT))
            done = start(os.path.join(lonely, BAT), cwd=tmp, env=env, **quiet)
            check(done.returncode == 1 and b'is not next to this file' in done.stdout,
                  'sort_content.bat without its scripts says so: %s %r' % (done.returncode, done.stdout[-200:]))

            # ---- the batch file fetches a Python of its own
            if os.environ.get('ZCG_TEST_PORTABLE'):
                addon = os.path.join(tmp, u'portable (1)', L.ADDON_DIRNAME)
                want = shipped(addon)
                profile = os.path.join(tmp, u'\u0412\u0430\u0441\u044f', 'AppData', 'Local')
                os.makedirs(profile)
                env2 = dict(env, ZCG_PORTABLE_PYTHON='1', LOCALAPPDATA=profile)
                done = start(os.path.join(addon, BAT), cwd=tmp, env=env2, **quiet)
                judge('sort_content.bat with a portable Python', addon, want, done)
                show('sort_content.bat with a portable Python', done)
                check(os.path.isfile(os.path.join(profile, 'zcg_python', 'python.exe')), 'the portable Python is kept in the profile')
                check(not os.path.isfile(os.path.join(profile, 'zcg_python', 'python.zip')), 'its archive is removed')
                check(b'Fetching a portable copy' in done.stdout, 'the batch file says that it fetches one')
                # the second start uses it without fetching again
                addon = os.path.join(tmp, u'portable (2)', L.ADDON_DIRNAME)
                want = shipped(addon)
                done = start(os.path.join(addon, BAT), cwd=tmp, env=env2, **quiet)
                judge('sort_content.bat, the portable Python again', addon, want, done)
                check(b'Fetching a portable copy' not in done.stdout, 'the portable Python is fetched only once')
            else:
                print('  (ZCG_TEST_PORTABLE is not set: the fetching of a portable Python is not tried)')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('test_sort_tool.py  %d checks, %d failed' % tuple(T.CHECKS))
    return 1 if T.CHECKS[1] else 0


if __name__ == '__main__':
    sys.exit(main())
