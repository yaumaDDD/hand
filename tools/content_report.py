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

WHY = {
    P.REPLACED: u'такой же файл есть в более позднем источнике',
    P.OWN_FILE: u'на этом месте лежит файл самого аддона',
    P.NAMESAKES: u'не отличить от тёзок, см. «Замечания»',
    P.UNNAMED: u'его никто не называет, и лежит он не в папке materials или models',
    P.PLACE_TAKEN: u'его место занял другой файл',
}

NOTES = {
    'version': u'%s: файл пришёл в двух разных версиях — из «%s» и из «%s»; взята вторая',
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
}


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
            return NOTES[kind] % tuple(text.args)
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


def lines(sources, result, named, written_by, more=(), who=None):
    """the report as a list of lines. sources: [{'name', 'kind', 'no_place': [paths]}];
    more: lines that go right below the heading (what a tool did with the result);
    who: name -> the pack that names it, to list the missing names pack by pack"""
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
        out.append(u'    %s    (%s)' % (item, why(reason)))

    out += [u'', u'Замечания — %d' % len(result.notes)]
    out += [u'    ' + note(text) for text in result.notes]

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


def write(path, sources, result, named, written_by, more=(), who=None):
    """writes the report (UTF-8 with a mark, so that Notepad shows the Russian text)"""
    text = u'\n'.join(lines(sources, result, named, written_by, more, who)) + u'\n'
    with io.open(path, 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write(text)
