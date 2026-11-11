#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests sort_content as it is shipped: the folder the build puts into the addon, started the way
its owner starts it.

    python tools/test_sort_tool.py

An addon is made up in a temporary folder - its Lua, its own content, clothing content dropped in
by hand - with the scripts the build ships (build_addon.step_sort_tool) and sort_content.bat next
to them. Then:
  * everywhere: the script is run by a Python that knows nothing but its own library ("-I", like
    the portable Python sort_content.bat fetches), from another folder;
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


def result(folder):
    """the files of the addon without the tool and its report"""
    got = T.tree(folder)
    report = got.pop(sort_content.REPORT, None)
    for rel in list(got):
        if rel == BAT or rel.startswith(build_addon.SORT_TOOL_DIR + '/'):
            del got[rel]
    return got, report


def show(label, done):
    text = (done.stdout or b'').decode('utf-8', 'replace')
    print('---- %s: exit code %s' % (label, done.returncode))
    for line in text.splitlines()[-25:]:
        print('    ' + line.encode('ascii', 'backslashreplace').decode('ascii'))


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

        if os.name != 'nt':
            print('  (not on Windows: sort_content.bat itself is not run)')
        else:
            env = dict(os.environ, ZCG_NO_PAUSE='1', PYTHONIOENCODING='utf-8')
            # ---- the batch file, with the Python that is installed; a folder dropped onto it
            addon = os.path.join(tmp, u'Steam (x86)', u'\u0434\u0440\u0443\u0433\u043e\u0439 \u0430\u0434\u0434\u043e\u043d', L.ADDON_DIRNAME)
            want = shipped(addon)
            outside = os.path.join(tmp, u'content \u2014 \u043a\u043e\u043f\u0438\u044f & more')
            T.write(os.path.join(outside, 'materials', 'gate', 'jacket.vmt'), T.material('models/gate/jacket'))
            T.write(os.path.join(outside, 'materials', 'gate', 'jacket.vtf'), T.texture('jacket'))
            want['materials/models/gate/jacket.vmt'] = T.material('models/gate/jacket').encode('utf-8')
            want['materials/models/gate/jacket.vtf'] = T.texture('jacket')
            done = subprocess.run(['cmd', '/c', os.path.join(addon, BAT), outside], cwd=tmp, env=env, **quiet)
            judge('sort_content.bat', addon, want, done)
            show('sort_content.bat', done)

            # ---- a failure is passed on: no folder "sort_content" next to the batch file
            lonely = os.path.join(tmp, 'lonely')
            os.makedirs(lonely)
            shutil.copyfile(os.path.join(ROOT, L.ADDON_DIRNAME, BAT), os.path.join(lonely, BAT))
            done = subprocess.run(['cmd', '/c', os.path.join(lonely, BAT)], cwd=tmp, env=env, **quiet)
            check(done.returncode == 1 and b'is not next to this file' in done.stdout,
                  'sort_content.bat without its scripts says so: %s %r' % (done.returncode, done.stdout[-200:]))

            # ---- the batch file fetches a Python of its own
            if os.environ.get('ZCG_TEST_PORTABLE'):
                addon = os.path.join(tmp, u'portable (1)', L.ADDON_DIRNAME)
                want = shipped(addon)
                profile = os.path.join(tmp, u'\u0412\u0430\u0441\u044f', 'AppData', 'Local')
                os.makedirs(profile)
                env2 = dict(env, ZCG_PORTABLE_PYTHON='1', LOCALAPPDATA=profile)
                done = subprocess.run(['cmd', '/c', os.path.join(addon, BAT)], cwd=tmp, env=env2, **quiet)
                judge('sort_content.bat with a portable Python', addon, want, done)
                show('sort_content.bat with a portable Python', done)
                check(os.path.isfile(os.path.join(profile, 'zcg_python', 'python.exe')), 'the portable Python is kept in the profile')
                check(not os.path.isfile(os.path.join(profile, 'zcg_python', 'python.zip')), 'its archive is removed')
                check(b'Fetching a portable copy' in done.stdout, 'the batch file says that it fetches one')
                # the second start uses it without fetching again
                addon = os.path.join(tmp, u'portable (2)', L.ADDON_DIRNAME)
                want = shipped(addon)
                done = subprocess.run(['cmd', '/c', os.path.join(addon, BAT)], cwd=tmp, env=env2, **quiet)
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
