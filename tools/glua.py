# -*- coding: utf-8 -*-
"""Garry's Mod Lua ("GLua") -> plain Lua.

The Lua of other addons that ends up in the build (the drop-in archives, see zcg_layout.py) is
written in the dialect of the game: C-style comments and operators, the keyword `continue`.
LuaJIT does not read that, so such a file is passed through to_lua() first:

    to_lua(src)             good enough to compile it (tools/test_lua.py) and to read its text
                            (tools/list_content.py). The result compiles exactly when the original
                            would in the game; it must not be run: `continue` becomes an empty
                            statement.
    to_lua(src, run=True)   to run it (tools/lua_names.py): `continue` becomes a jump to the end
                            of the loop body, which LuaJIT 2.1 and Lua 5.2+ understand (goto).
"""


def _long_bracket(src, pos):
    """level of the long bracket that opens at src[pos] == '[', or None"""
    j = pos + 1
    while j < len(src) and src[j] == '=':
        j += 1
    if j < len(src) and src[j] == '[':
        return j - pos - 1
    return None


def to_lua(src, run=False):
    out = []
    # for run=True: the open blocks, innermost last. A loop is [kind, piece of `out` where its
    # body starts, label or None]; anything else is [kind] ('head': a `for` or `while` whose
    # `do` has not come yet - there may be whole functions in between).
    blocks, labels = [], [0]
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

        # ---- numbers (so that the exponent of 1e5 or the digits of 0xdo are not read as words)
        if c.isdigit():
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] == '.'):
                j += 1
            out.append(src[i:j])
            i = j
            continue

        # ---- words
        if c.isalpha() or c == '_':
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] == '_'):
                j += 1
            word = src[i:j]
            field = bool(out) and out[-1][-1:] in ('.', ':')    # x.continue, x:end() are names
            if word == 'continue' and not field:
                if not run:
                    word = 'do end'
                else:
                    # the innermost loop of this function
                    loop = None
                    for block in reversed(blocks):
                        if block[0] == 'function':
                            break
                        if block[0] in ('loop', 'repeat'):
                            loop = block
                            break
                    if loop is not None:
                        if loop[2] is None:
                            labels[0] += 1
                            loop[2] = '__continue_%d' % labels[0]
                        word = 'goto ' + loop[2]
            elif run and not field:
                if word in ('for', 'while'):
                    blocks.append(['head'])
                elif word == 'do':
                    if blocks and blocks[-1][0] == 'head':
                        # the body of the loop: `do` is put down twice when a `continue` turns
                        # up in it, so that the label can follow a body that ends in a return
                        blocks[-1] = ['loop', len(out), None]
                    else:
                        blocks.append(['do'])
                elif word in ('function', 'if'):
                    blocks.append([word])
                elif word == 'repeat':
                    blocks.append(['repeat', len(out), None])
                elif word == 'end' and blocks:
                    block = blocks.pop()
                    if block[0] == 'loop' and block[2]:
                        out[block[1]] = 'do do'
                        word = 'end ::%s:: end' % block[2]
                elif word == 'until' and blocks:
                    block = blocks.pop()
                    if block[0] == 'repeat' and block[2]:
                        # (the condition may use the locals of the body, so no block of its own)
                        word = '::%s:: until' % block[2]
            out.append(word)
            i = j
            continue

        out.append(c)
        i += 1
    return ''.join(out)
