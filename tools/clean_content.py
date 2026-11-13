#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Deletes the content of an installed addon that the clothes do not use.  (a step of sort_content.py)

Whole addons are thrown into the addon to get their clothes, and they bring the rest along: props,
weapons, maps, models nobody wears. The game reads none of it through this addon, it only takes
room - on the disk, in the upload to a server, in the download of every player. This step deletes
it. A file stays when it is USED or when it IS CLOTHING:

  used       the Lua of the addon names it (also the Lua of the other version of a pack, and the
             names of Z-City itself), or a file that stays needs it: a model its materials, its
             .vvd / .vtx / .phy / .ani and the models it includes; a material its textures and
             the materials it includes.  The addon's own content (the gloves) always stays.
  clothing   a material nobody names that the game may still put into the appearance menu
             (lua/zcity_csgo_gloves/sh_auto.lua does that for content without Lua): a face
             ("..._facemap...", "..._cylmap..."), a material in a folder the Lua names clothes in,
             a "...sheet..." in a folder .../male/... or .../female/...

Only files of the game are judged: .vmt .vtf .mdl .vvd .vtx .phy .ani below materials/ and
models/. Anything else there (a note, a picture) is left alone. Everything in _not_used goes: that
folder holds what had no place in the addon to begin with.

Deleting cannot be undone, so the step does nothing when the names are not known for certain
(no list of the names made by running the Lua - see list_content.py).
"""
import os
import posixpath
import re

import place_content as P

KINDS = ('.vmt', '.vtf', '.mdl', '.vvd', '.vtx', '.phy', '.ani')
_MODEL_IN_MODEL = re.compile(rb'[\w\-./\\]+\.mdl', re.I)
_TOKEN = re.compile(r'"([^"\r\n]*)"|([^\s"{}]+)')


def long_path(path):
    path = os.path.abspath(path)
    if os.name == 'nt' and not path.startswith('\\\\?\\'):
        return '\\\\?\\' + path
    return path


class Result(object):
    def __init__(self):
        self.deleted = []       # (path in the addon, bytes)
        self.failed = []        # (path in the addon, error)
        self.kept = 0           # files of the game that stay
        self.clothing = 0       # ... materials among them that nobody names and that stay as clothing
        self.aside = 0          # files deleted out of _not_used (they are in deleted as well)
        self.skipped = None     # why nothing was done

    @property
    def bytes(self):
        return sum(size for _path, size in self.deleted)


def stem_of(rel):
    """models/a/b.dx90.vtx -> models/a/b"""
    folder, name = posixpath.split(rel)
    return posixpath.join(folder, name.split('.')[0])


def is_clothing(rel, clothes_folders):
    """a material nobody names: may the game still wear it? (the rules of sh_auto.lua, a little wider)"""
    folder, name = posixpath.split(rel[len('materials/'):])
    name = name[:-len('.vmt')]
    if 'facemap' in name or 'cylmap' in name:
        return True
    if folder in clothes_folders:
        return True
    parts = folder.split('/')
    return 'sheet' in name and ('male' in parts or 'female' in parts)


def needs_of_model(full):
    """the paths (lower case) a model asks for, besides its own files"""
    out = set()
    try:
        folders, names = P.read_model(full)
    except (ValueError, OSError, IOError):
        folders, names = [], []
    for name in names:
        for folder in list(folders) + ['']:
            path = posixpath.normpath('materials/' + folder.strip('/') + '/' + name.strip('/')).lower()
            out.add(path + '.vmt')
    try:
        with open(full, 'rb') as f:
            data = f.read()
    except (OSError, IOError):
        return out
    for found in _MODEL_IN_MODEL.findall(data):
        path = found.decode('latin-1').replace('\\', '/').lower().lstrip('/')
        out.add(path if path.startswith('models/') else 'models/' + path)
    return out


def needs_of_material(full):
    """the paths (lower case) a material asks for - read generously: every word of the file that
    is the name of a file is one"""
    out = set()
    try:
        with open(full, 'r', encoding='latin-1') as f:
            text = f.read()
    except (OSError, IOError):
        return out
    for quoted, bare in _TOKEN.findall(text):
        word = (quoted or bare).strip().replace('\\', '/').lower().strip('/')
        if not word or len(word) > 260 or word.startswith('//'):
            continue
        for ext in ('.vtf', '.vmt'):
            if word.endswith(ext):
                word = word[:-len(ext)]
        base = word if word.startswith('materials/') else 'materials/' + word
        out.add(base + '.vtf')
        out.add(base + '.vmt')
    return out


def survey(addon, named, own):
    """-> (files to delete [(rel, full)], files that stay, materials that stay as clothing)
    named: the paths the Lua names (materials/x.vmt, models/y.mdl); own(rel): the addon's own content"""
    files = {}          # lower rel -> [(rel, full)]
    by_stem = {}        # models: lower stem -> [lower rel]
    for top in ('materials', 'models'):
        root = os.path.join(addon, top)
        for folder, _dirs, names in os.walk(long_path(root)):
            for name in names:
                full = os.path.join(folder, name)
                rel = top + '/' + os.path.relpath(full, long_path(root)).replace(os.sep, '/')
                low = rel.lower()
                files.setdefault(low, []).append((rel, full))
                if top == 'models':
                    by_stem.setdefault(stem_of(low), []).append(low)

    keep = set()

    def follow(start):
        queue = [path for path in start if path in files and path not in keep]
        while queue:
            path = queue.pop()
            if path in keep:
                continue
            keep.add(path)
            more = set()
            if path.endswith('.mdl'):
                more.update(by_stem.get(stem_of(path), ()))
                more |= needs_of_model(files[path][0][1])
            elif path.endswith('.vmt'):
                more |= needs_of_material(files[path][0][1])
            queue.extend(p for p in more if p in files and p not in keep)

    named = set(name.lower() for name in named)
    follow(named)
    follow(path for path in files if own(path))
    clothes_folders = set(posixpath.dirname(name[len('materials/'):]) for name in named
                          if name.startswith('materials/') and name.endswith('.vmt'))
    loose = [path for path in files if path.endswith('.vmt') and path.startswith('materials/')
             and path not in keep and is_clothing(path, clothes_folders)]
    follow(loose)

    doomed, stay = [], 0
    for low, same in files.items():
        if low in keep or not low.endswith(KINDS):
            stay += len(same) if low.endswith(KINDS) else 0
            continue
        doomed.extend(same)
    return sorted(doomed), stay, len(loose)


def prune(root):
    """removes the folders below root that are empty"""
    for folder, _dirs, _names in os.walk(long_path(root), topdown=False):
        if os.path.normcase(folder) == os.path.normcase(long_path(root)):
            continue
        try:
            if not os.listdir(folder):
                os.rmdir(folder)
        except (OSError, IOError):
            pass


def clean(addon, named, own, aside='_not_used', dry=False):
    """deletes what the clothes do not use; returns a Result"""
    result = Result()
    doomed, result.kept, result.clothing = survey(addon, named, own)
    aside_root = os.path.join(addon, aside)
    if os.path.isdir(aside_root):
        for folder, _dirs, names in os.walk(long_path(aside_root)):
            for name in names:
                full = os.path.join(folder, name)
                doomed.append((aside + '/' + os.path.relpath(full, long_path(aside_root)).replace(os.sep, '/'), full))
                result.aside += 1
    for rel, full in doomed:
        try:
            size = os.path.getsize(full)
            if not dry:
                os.remove(full)
            result.deleted.append((rel, size))
        except (OSError, IOError) as err:
            result.failed.append((rel, str(err)))
    if not dry:
        for top in ('materials', 'models', aside):
            if os.path.isdir(os.path.join(addon, top)):
                prune(os.path.join(addon, top))
        try:
            if os.path.isdir(aside_root) and not os.listdir(aside_root):
                os.rmdir(aside_root)
        except (OSError, IOError):
            pass
    return result


def megabytes(size):
    return u'%.1f МБ' % (size / 1048576.0)


def short(result, dry=False):
    """what is said on the screen"""
    if result.skipped:
        return [u'Лишний контент не удалялся: %s' % result.skipped]
    if not result.deleted and not result.failed:
        return [u'Лишнего контента нет: все файлы материалов и моделей (%d) используются одеждой.' % result.kept]
    out = [u'%s контент, который не относится к одежде и не используется: файлов %d, %s.'
           % (u'Был бы удалён (--dry-run)' if dry else u'Удалён', len(result.deleted), megabytes(result.bytes))]
    if result.aside:
        out.append(u'  из них из папки _not_used — %d.' % result.aside)
    out.append(u'  Осталось файлов одежды: %d (материалов без Lua, оставленных как одежда, — %d). Список удалённого — в отчёте.'
               % (result.kept, result.clothing))
    if result.failed:
        out.append(u'  ВНИМАНИЕ: не удалось удалить файлов: %d (закройте игру и запустите ещё раз).' % len(result.failed))
    out.append(u'  Не удалять: sort_content.bat --keep-unused')
    return out


def lines(result, dry=False):
    """what goes into the report"""
    out = short(result, dry)
    if result.deleted:
        out += [u'', u'%s — %d:' % (u'Были бы удалены' if dry else u'Удалены', len(result.deleted))]
        folders = {}
        for rel, size in result.deleted:
            entry = folders.setdefault(posixpath.dirname(rel), [0, 0])
            entry[0] += 1
            entry[1] += size
        for folder in sorted(folders):
            out.append(u'    %s/ — файлов: %d, %s' % (folder, folders[folder][0], megabytes(folders[folder][1])))
    if result.failed:
        out += [u'', u'Не удалось удалить — %d:' % len(result.failed)]
        out += [u'    %s: %s' % pair for pair in result.failed[:200]]
    return out
