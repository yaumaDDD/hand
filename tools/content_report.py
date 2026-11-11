# -*- coding: utf-8 -*-
"""What became of the materials and models of other addons - written down for the owner of the
addon, in Russian.  (used by build_addon.py and sort_content.py)

The pieces come from tools/place_content.py (a Report), which speaks plain English; here they
are put into the words of the README.
"""
import collections
import io
import os
import posixpath
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import place_content as P  # noqa: E402
import zcg_layout as L  # noqa: E402

WHY = {
    P.REPLACED: u'на его место взят другой файл с тем же путём — из более позднего источника или папки, см. «Замечания»',
    P.COPY: u'точная копия файла, который лежит на этом месте',
    P.ORPHAN: u'файл модели, место которой занято другой моделью: к чужой модели он не подкладывается',
    P.OWN_FILE: u'на этом месте лежит файл самого аддона',
    P.NAMESAKES: u'не отличить от тёзок, см. «Замечания»',
    P.UNNAMED: u'его никто не называет, и лежит он не в папке materials или models',
    P.PLACE_TAKEN: u'его место занял другой файл',
}

NOTES = {
    'version': u'%s: файл пришёл в двух разных версиях — из «%s» и из «%s»; взята вторая',
    'version here': u'%s: на это место есть два разных файла — «%s» и «%s»; взят второй (из папки, которая позже по '
                    u'имени, или тот, что уже лежал на месте), первый убран',
    'equal': u'%s: одинаково подходят «%s» и «%s»; взят первый',
    'several names': u'«%s» подходит по имени сразу к нескольким названным файлам (%d — в папках %s) и никуда не '
                     u'положен: назовите его папку так же, как называется папка, из которой он взят',
    'several files': u'%s: на это имя есть несколько разных файлов (%d), и нечем решить, какой нужен; не взят ни '
                     u'один: назовите их папки так же, как называются папки, из которых они взяты',
    'unreadable': u'«%s» не читается: %s',
    'no materials': u'%s: материалы этой модели не прослежены (%s)',
    'also here': u'%s: файла там не было, а материал, который лежит в %s, берёт текстуру именно с этим именем — значит, '
                 u'это он и есть; он положен и сюда (копией). Если в %s должен лежать другой материал, того не хватает',
    'same name': u'«%s» теперь лежит в %s, где его никто не называет. А файл с таким именем Lua называет в %s, '
                 u'и там его нет: этот туда не взят, потому что ничто не говорит, что это он. Если он оттуда, '
                 u'переложите его в ту папку сами и запустите ещё раз',
    'same name unused': u'«%s» не использован. А файл с таким именем Lua называет в %s, и там его нет: этот туда не '
                        u'взят, потому что ничто не говорит, что это он. Если он оттуда, переложите его в ту папку '
                        u'сами и запустите ещё раз',
    'other version': u'«%s» положен в %s: %s, а это место файла в другой версии аддона, которой в этой сборке нет. '
                     u'Файл с таким именем Lua сборки называет в %s, и там его нет: этот туда не взят. Если это всё же '
                     u'он, переложите его в ту папку сами и запустите ещё раз',
    'compiled for other': u'Моделей, которые лежат там, где модель называет Lua сборки, а сами говорят, что собраны для '
                          u'пути из другой версии аддона (её в сборке нет): %d (%s). Возможно, это модели той версии: '
                          u'если в игре они выглядят не так, замените их',
    'came back': u'Моделей, которые лежали на местах другой версии аддона (её в сборке нет), а сами говорят, что '
                 u'собраны для путей, которые называет Lua этой сборки, и там было пусто: %d — они переложены туда (%s)',
}
# the reasons in an 'other version' note
REASONS = {
    P.SPARE_SAYS: u'модель сама говорит, что собрана для этого пути',
    P.SPARE_TEXTURE: u'свою текстуру материал называет в этой папке',
    P.SPARE_FOLDERS: u'так называются его папки',
}


STRAY_FILES = 2     # see of_the_other_version
FEW = 4             # ... "few of them": not more than one in four


def versions_found(result, instead, spare, only):
    """What the files say about which version of a pack the content at hand belongs to.
    instead: {title of a pack that is not in the addon: title of its version that is};
    spare: {a file only such a pack names: its title};
    only: {a file the addon names and such a pack does not: the title of that pack}.
    Returns, sorted by title, a dict for each such pack:
        title, instead;
        theirs, theirs_all - how many of the files only it names are there, and how many it names;
        taken - models that lie at a place of the version in the addon and say themselves that
                they were compiled for the place of this one;
        ours, ours_all - how many of the files only the version in the addon names are there
                (without those), and how many it names.
    (a file: a model or a material - what place() tells as missing)"""
    def counted(name):
        return name.endswith(('.mdl', '.vmt'))

    missing = set(result.missing_named)
    there = set(dest for dest, _item in getattr(result, 'spare', ()))
    found = []
    for title, taken in sorted(instead.items()):
        theirs_all = set(name for name, pack in spare.items() if pack == title and counted(name))
        ours_all = set(name for name, pack in only.items() if pack == title and counted(name))
        odd = set(dest for dest, says in getattr(result, 'misplaced', ()) if spare.get(says) == title)
        found.append(dict(title=title, instead=taken, theirs=len(theirs_all & there), theirs_all=len(theirs_all),
                          taken=len(odd), ours=len(ours_all - missing - odd), ours_all=len(ours_all)))
    return found


def of_the_other_version(entry):
    """is the content at hand that of the version that is not in the addon? (an entry of
    versions_found) Yes when files of that version are there and none of the files only the
    version in the addon names - or few of them while most of the other kind are there: a stray
    file or two, or not more than one in four. The content of one version carries some files
    of the other (the first one seen had 13 of the 15 files of its own version, all its models,
    and 9 of the 85 of the other, materials only): that does not make it the other one's."""
    theirs = entry['theirs'] + entry['taken']
    if not theirs or not entry['ours_all']:
        return False
    if not entry['ours']:
        return True
    few = entry['ours'] <= STRAY_FILES or entry['ours'] * FEW <= entry['ours_all']
    return few and theirs * 2 > max(entry['theirs_all'], 1)


def version_lines(found):
    """what versions_found() gives, as lines for the screen and the report"""
    out = []
    for entry in found:
        theirs = entry['theirs'] + entry['taken']
        if not theirs:
            continue
        title, taken = entry['title'], entry['instead']
        if of_the_other_version(entry):
            out.append(u'ВНИМАНИЕ: похоже, ваш контент — от «%s», а эта сборка — с «%s».' % (title, taken))
            out.append(u'  Файлов, которые называет только «%s»: %d из %d.' % (title, entry['theirs'], entry['theirs_all']))
            if entry['taken']:
                out.append(u'  Моделей, которые лежат на местах «%s», а собраны для путей «%s»: %d.' % (taken, title, entry['taken']))
            out.append(u'  Файлов, которые называет только «%s»: %d из %d.' % (taken, entry['ours'], entry['ours_all']))
            out.append(u'  С этой сборкой игра ищет файлы «%s» — и не найдёт их. Нужна сборка с «%s»:' % (taken, title))
            archive = L.VERSION_ZIPS.get(title)
            if archive:
                out.append(u'  в выпуске на GitHub это архив %s (свою делает build_addon.bat --pack "%s").' % (archive, title))
            else:
                out.append(u'  её делает build_addon.bat --pack "%s".' % title)
            out.append(u'  Скопируйте её папку поверх этой с заменой файлов (одежда останется на месте) и запустите')
            out.append(u'  sort_content.bat ещё раз.')
        else:
            line = u'Файлов версии «%s», которой в сборке нет: %d' % (title, entry['theirs'])
            if entry['theirs_all']:
                line += u' из %d' % entry['theirs_all']
            out.append(line + u' — лежат на своих местах, игре сейчас не нужны.')
            if entry['taken']:
                out.append(u'  Моделей, которые лежат на местах «%s», а собраны для путей «%s»: %d — см. отчёт, «Замечания».'
                           % (taken, title, entry['taken']))
            if entry['ours_all']:
                out.append(u'  Файлов, которые называет только «%s» (она в сборке): %d из %d.' % (taken, entry['ours'], entry['ours_all']))
    return out


# how many folders of files that stay as they were packed are listed
AS_PACKED_SHOWN = 60


def why(reason):
    """the reason a file was left out, in Russian"""
    return WHY.get(reason, reason)


def note(text):
    """a remark of place_content, in Russian (as it is when it is not one of the known ones)"""
    kind = getattr(text, 'kind', None)
    if kind in NOTES:
        try:
            return NOTES[kind] % tuple(REASONS.get(arg, arg) if isinstance(arg, str) else arg for arg in text.args)
        except TypeError:
            pass
    return u'%s' % (text,)


def moved_from(sources, source, folder):
    """the folder a file was moved out of, as somebody finds it: a folder of the repository (or
    of the addon) with its name in front, a folder of an archive as it is called there"""
    kinds = dict((entry['name'], entry['kind']) for entry in sources)
    if kinds.get(source) == 'folder':
        return '/'.join(part for part in (source, folder) if part) + '/'
    return (folder or '.') + '/'


def by_pack(names, who):
    """names sorted into the packs that name them: [(label of the pack, [names])], the pack with
    the most names first; who(name) -> label ('' when nobody is known to name it)"""
    packs = collections.defaultdict(list)
    for name in names:
        packs[who(name) or u''].append(name)
    return sorted(packs.items(), key=lambda kv: (kv[0] == u'', -len(kv[1]), kv[0]))


def folders_of(names, shown=3):
    """'materials/a/ — 4, materials/b/ — 2 и ещё папок: 5' for a list of names"""
    count = collections.Counter(posixpath.dirname(name) + u'/' for name in names)
    top = sorted(count.items(), key=lambda kv: (-kv[1], kv[0]))
    text = u', '.join(u'%s — %d' % pair for pair in top[:shown])
    if len(top) > shown:
        text += u' и ещё папок: %d' % (len(top) - shown)
    return text


def lines(sources, result, named, written_by, more=(), who=None, spare=None):
    """the report as a list of lines. sources: [{'name', 'kind', 'no_place': [paths]}];
    more: lines that go right below the heading (what a tool did with the result);
    who: name -> the pack that names it, to list the missing names pack by pack;
    spare: {path: title} - the files only a pack names whose Lua is not in the addon"""
    out = [u'Раскладка контента: материалы, текстуры и модели других аддонов.  (записано %s)' % written_by,
           u'Игра находит файл только по точному пути. Здесь — что куда положено, что не пригодилось и чего не хватает.',
           u'Разделы описаны в README.md, «Куда класть файлы».']
    if more:
        out.append(u'')
        out.extend(more)

    moves = sorted(result.moves.items(), key=lambda kv: (kv[0][0], kv[0][1]))
    out += [u'', u'Переложено (нашлись по имени или переехали вместе со своей папкой) — файлов: %d'
            % sum(result.moves.values())]
    for (source, src, dst), count in moves:
        out.append(u'    %s  ->  %s/    файлов: %d    [%s]' % (moved_from(sources, source, src), dst, count, source))

    # files nothing is known about: they are where they were packed, right or not
    folders = collections.Counter((item.source, posixpath.dirname(item.inner)) for item in result.as_packed)
    out += [u'', u'Оставлено в тех же папках — файлов: %d (про них ничего не известно: ни их, ни их папки никто не '
                 u'называет, или их не отличить от тёзок)' % len(result.as_packed)]
    for (source, folder), count in sorted(folders.items())[:AS_PACKED_SHOWN]:
        out.append(u'    %s    файлов: %d    [%s]' % (moved_from(sources, source, folder), count, source))
    if len(folders) > AS_PACKED_SHOWN:
        out.append(u'    ... и ещё папок: %d' % (len(folders) - AS_PACKED_SHOWN))

    out += [u'', u'Не использовано — файлов: %d' % len(result.left_out)]
    for item, reason in result.left_out:
        if reason != P.COPY:
            out.append(u'    %s    (%s)' % (item, why(reason)))
    # (a copy of a file that lies at its place needs no line of its own: there may be thousands,
    # when the same folders are handed over once more)
    copies = collections.Counter((item.source, posixpath.dirname(item.inner)) for item, reason in result.left_out
                                 if reason == P.COPY)
    if copies:
        out.append(u'    точные копии файлов, которые лежат на своих местах, — %d (их можно удалить); по папкам:'
                   % sum(copies.values()))
        for (source, folder), count in sorted(copies.items())[:AS_PACKED_SHOWN]:
            out.append(u'        %s    файлов: %d    [%s]' % (moved_from(sources, source, folder), count, source))
        if len(copies) > AS_PACKED_SHOWN:
            out.append(u'        ... и ещё папок: %d' % (len(copies) - AS_PACKED_SHOWN))

    out += [u'', u'Замечания — %d' % len(result.notes)]
    out += [u'    ' + note(text) for text in result.notes]

    if getattr(result, 'spare', None):
        # the files of a version of a pack that is not in the addon
        out += [u'', u'Файлы другой версии аддона, Lua которой в сборке нет — %d (лежат на своих местах; игре с этой '
                     u'сборкой они не нужны)' % len(result.spare)]
        by_title = collections.defaultdict(list)
        for dest, _item in result.spare:
            by_title[(spare or {}).get(dest) or u''].append(dest)
        for title, dests in sorted(by_title.items()):
            if title:
                out.append(u'  «%s» — %d' % (title, len(dests)))
            out += [u'    ' + dest for dest in sorted(dests)]

    out += [u'', u'Lua называет, а файла нет — %d из %d (такой файл может быть частью игры или Z-City)'
            % (len(result.missing_named), len(named))]
    if who is None:
        out += [u'    ' + name for name in result.missing_named]
    else:
        # (pack by pack: these files come with the content of that pack - or with what it depends on)
        for label, names in by_pack(result.missing_named, who):
            out.append(u'  %s — %d' % (label or u'(какой Lua называет — не известно)', len(names)))
            out += [u'    ' + name for name in names]

    out += [u'', u'Модель ищет материал, а его нет — %d из %d'
            % (len(result.missing_materials), result.materials_wanted)]
    for model, _name, group in result.missing_materials:
        out.append(u'    %s  <-  %s' % (u' | '.join(group), model))

    out += [u'', u'Материал ищет текстуру, а её нет — %d из %d'
            % (len(result.missing_textures), result.textures_wanted)]
    for material, key, texture in result.missing_textures:
        out.append(u'    %s  <-  %s  %s' % (texture, material, key))

    strangers = [entry for entry in sources if entry.get('no_place')]
    if strangers:
        out += [u'', u'Не часть аддона (над файлом нет папки lua, materials, models ...) — пропущено']
        for entry in strangers:
            out.append(u'    %s — файлов: %d' % (entry['name'], len(entry['no_place'])))
            out += [u'        ' + name for name in entry['no_place'][:200]]
            if len(entry['no_place']) > 200:
                out.append(u'        ... и ещё %d' % (len(entry['no_place']) - 200))
    return out


def write(path, sources, result, named, written_by, more=(), who=None, spare=None):
    """writes the report (UTF-8 with a mark, so that Notepad shows the Russian text)"""
    text = u'\n'.join(lines(sources, result, named, written_by, more, who, spare)) + u'\n'
    with io.open(path, 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write(text)
