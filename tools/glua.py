# -*- coding: utf-8 -*-
"""Garry's Mod Lua ("GLua") -> plain Lua, good enough to compile it.

The Lua of other addons that ends up in the build (the drop-in archives, see zcg_layout.py) is
written in the dialect of the game: C-style comments and operators, the keyword `continue`.
LuaJIT does not read that, so before tools/test_lua.py compiles such a file it is passed through
to_lua().  The result compiles exactly when the original would in the game; it must not be run:
`continue` becomes an empty statement.
"""


def _long_bracket(src, pos):
    """level of the long bracket that opens at src[pos] == '[', or None"""
    j = pos + 1
    while j < len(src) and src[j] == '=':
        j += 1
    if j < len(src) and src[j] == '[':
        return j - pos - 1
    return None


def to_lua(src):
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        two = src[i:i + 2]

        # ---- comments
        if two == '--':
            level = _long_bracket(src, i + 2) if src[i + 2:i + 3] == '[' else None
            if level is not None:
                close = ']' + '=' * level + ']'
                end = src.find(close, i + 4 + level)
                end = n if end < 0 else end + len(close)
            else:
                end = src.find('\n', i)
                end = n if end < 0 else end
            out.append(src[i:end])
            i = end
            continue
        if two == '//':
            end = src.find('\n', i)
            end = n if end < 0 else end
            out.append('--' + src[i + 2:end])
            i = end
            continue
        if two == '/*':
            end = src.find('*/', i + 2)
            body = src[i + 2:(n if end < 0 else end)]
            out.append('--[==[' + body.replace(']==]', ']= =]') + ']==]')
            i = n if end < 0 else end + 2
            continue

        # ---- strings
        if c == '"' or c == "'":
            j = i + 1
            while j < n and src[j] != c and src[j] != '\n':
                j += 2 if src[j] == '\\' else 1
            out.append(src[i:j + 1])
            i = j + 1
            continue
        if c == '[':
            level = _long_bracket(src, i)
            if level is not None:
                close = ']' + '=' * level + ']'
                end = src.find(close, i + 2 + level)
                end = n if end < 0 else end + len(close)
                out.append(src[i:end])
                i = end
                continue

        # ---- operators of the dialect
        if two == '!=':
            out.append('~=')
            i += 2
            continue
        if c == '!':
            out.append(' not ')
            i += 1
            continue
        if two == '&&':
            out.append(' and ')
            i += 2
            continue
        if two == '||':
            out.append(' or ')
            i += 2
            continue

        # ---- words
        if c.isalpha() or c == '_':
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] == '_'):
                j += 1
            word = src[i:j]
            if word == 'continue' and not (out and out[-1][-1:] in ('.', ':')):
                word = 'do end'
            out.append(word)
            i = j
            continue

        out.append(c)
        i += 1
    return ''.join(out)
