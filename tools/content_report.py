# -*- coding: utf-8 -*-
"""What became of the materials and models of other addons - written down for the owner of the
addon, in Russian.  (used by build_addon.py and sort_content.py)

The pieces come from tools/place_content.py (a Report), which speaks plain English; here they
are put into the words of the README.
"""
import io
import os
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
    'several names': u'«%s» подходит по имени сразу к нескольким названным файлам (%d) и не использован: '
                     u'положите его вместе с его папками',
    'several files': u'%s: на это имя есть несколько разных файлов (%d), и нечем решить, какой нужен; '
                     u'не взят ни один',
    'unreadable': u'«%s» не читается: %s',
    'no materials': u'%s: материалы этой модели не прослежены (%s)',
}


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


def lines(sources, result, named, written_by, more=()):
    """the report as a list of lines. sources: [{'name', 'kind', 'no_place': [paths]}];
    more: lines that go right below the heading (what a tool did with the result)"""
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

    out += [u'', u'Не использовано — файлов: %d' % len(result.left_out)]
    for item, reason in result.left_out:
        out.append(u'    %s    (%s)' % (item, why(reason)))

    out += [u'', u'Замечания — %d' % len(result.notes)]
    out += [u'    ' + note(text) for text in result.notes]

    out += [u'', u'Lua называет, а файла нет — %d из %d (такой файл может быть частью игры или Z-City)'
            % (len(result.missing_named), len(named))]
    out += [u'    ' + name for name in result.missing_named]

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


def write(path, sources, result, named, written_by, more=()):
    """writes the report (UTF-8 with a mark, so that Notepad shows the Russian text)"""
    text = u'\n'.join(lines(sources, result, named, written_by, more)) + u'\n'
    with io.open(path, 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write(text)
