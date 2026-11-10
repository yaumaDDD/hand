# -*- coding: utf-8 -*-
"""Tiny Valve KeyValues (VMT) reader/writer - enough for material files."""
import re

_TOKEN = re.compile(r'''
    \s*(?:
        (?P<comment>//[^\n]*)
      | (?P<open>\{)
      | (?P<close>\})
      | "(?P<quoted>[^"\n]*)"
      | (?P<bare>[^\s{}"]+)
    )''', re.X)


def tokenize(text):
    pos, out = 0, []
    text = text.replace('\r', '')
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            if text[pos:].strip() == '':
                break
            raise ValueError('bad VMT syntax near %r' % text[pos:pos + 30])
        pos = m.end()
        if m.group('comment') is not None:
            continue
        if m.group('open'):
            out.append(('{', None))
        elif m.group('close'):
            out.append(('}', None))
        elif m.group('quoted') is not None:
            out.append(('s', m.group('quoted')))
        else:
            out.append(('s', m.group('bare')))
    return out


def _block(toks, i):
    """parse after '{' ; returns (list of (key, value), next index). value is str or list"""
    items = []
    while i < len(toks):
        kind, val = toks[i]
        if kind == '}':
            return items, i + 1
        if kind != 's':
            raise ValueError('unexpected token %r' % (toks[i],))
        key = val
        i += 1
        if i >= len(toks):
            break
        kind, val = toks[i]
        if kind == '{':
            sub, i = _block(toks, i + 1)
            items.append((key, sub))
        elif kind == 's':
            items.append((key, val))
            i += 1
        else:
            # "key" followed by "}" : dangling key, ignore it
            continue
    return items, i


def parse(text):
    """returns (shader, items). Trailing garbage (e.g. a stray '}') is ignored."""
    toks = tokenize(text)
    if len(toks) < 2 or toks[0][0] != 's' or toks[1][0] != '{':
        raise ValueError('not a VMT')
    items, _ = _block(toks, 2)
    return toks[0][1], items


def dump(shader, items, header=None):
    out = []
    if header:
        for line in header.splitlines():
            out.append('// ' + line if line else '//')
    out.append('"%s"' % shader)
    out.append('{')

    def emit(items, depth):
        pad = '\t' * depth
        width = max([len(k) for k, v in items if isinstance(v, str)] + [0]) + 2
        for k, v in items:
            if isinstance(v, str):
                out.append('%s%-*s "%s"' % (pad, width, '"%s"' % k, v))
            else:
                out.append('%s"%s"' % (pad, k))
                out.append(pad + '{')
                emit(v, depth + 1)
                out.append(pad + '}')

    emit(items, 1)
    out.append('}')
    return '\n'.join(out) + '\n'
