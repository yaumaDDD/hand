# -*- coding: utf-8 -*-
"""Cut the bare arm inside the glove models down to what a glove leaves uncovered.

Every glove model contains, next to the glove itself, the bare CS:GO arm it was made for (one
mesh, material "bare_arm_*"): the whole arm from the shoulder down, and in the fingerless models
also the fingers that stick out of the glove. Z-City players have arms of their own, so the arm
must never be drawn - but the fingers are exactly what a fingerless glove needs, and they share
their material with the arm.

fingers_only() therefore removes the arm from the triangle lists (.dx90.vtx): a triangle of the
bare arm is kept only when all three of its corners move with a hand or a finger bone. What is
left are the fingers and the skin that shows through the cut-outs of a glove. Removed triangles
are not deleted but collapsed (all three corners become the same vertex), so nothing else in the
file moves; the .mdl and .vvd stay as they are.

    python tools/patch_models.py MODEL.mdl [...]      report only, nothing is written

Pure Python on purpose: build_addon.py runs this on machines that have nothing else.
"""
import struct
import sys

import mdl_lite

BARE_PREFIX = 'bare_arm'

VVD_VERTEX = 48
VTX_BODYPART, VTX_MODEL, VTX_LOD, VTX_MESH, VTX_GROUP, VTX_STRIP, VTX_VERTEX = 8, 8, 12, 9, 25, 27, 9
STRIP_IS_TRILIST = 1


class PatchError(Exception):
    pass


def is_hand_bone(name):
    """bones that carry what a glove can leave uncovered: the hand and the fingers"""
    name = name.lower()
    return name.endswith('_hand') or '_finger' in name


def read_vvd_bones(vvd):
    """dominant bone of every vertex of the highest detail level, in mesh order"""
    ident, version, _checksum, _numlods = struct.unpack_from('<4s3i', vvd, 0)
    if ident != b'IDSV' or version != 4:
        raise PatchError('not a supported .vvd file')
    lodverts = struct.unpack_from('<8i', vvd, 16)
    numfix, fixstart, vstart, _tstart = struct.unpack_from('<4i', vvd, 48)

    def dominant(index):
        o = vstart + index * VVD_VERTEX
        w0, w1, w2, b0, b1, b2, n = struct.unpack_from('<3f4B', vvd, o)
        best, bone = w0, b0
        if n > 1 and w1 > best:
            best, bone = w1, b1
        if n > 2 and w2 > best:
            bone = b2
        return bone

    if not numfix:
        return [dominant(i) for i in range(lodverts[0])]
    out = []
    for i in range(numfix):
        lod, src, count = struct.unpack_from('<3i', vvd, fixstart + i * 12)
        if lod >= 0:
            out.extend(dominant(src + k) for k in range(count))
    return out


def walk_vtx(vtx):
    """yields (bodypart, model, lod, mesh, group offset) for every strip group of the file"""
    version = struct.unpack_from('<i', vtx, 0)[0]
    if version != 7:
        raise PatchError('unsupported .vtx version %d' % version)
    numbp, bpoff = struct.unpack_from('<2i', vtx, 28)
    for i in range(numbp):
        bo = bpoff + i * VTX_BODYPART
        nummodels, modeloff = struct.unpack_from('<2i', vtx, bo)
        for j in range(nummodels):
            mo = bo + modeloff + j * VTX_MODEL
            numlods, lodoff = struct.unpack_from('<2i', vtx, mo)
            for l in range(numlods):
                lo = mo + lodoff + l * VTX_LOD
                nummeshes, meshoff = struct.unpack_from('<2i', vtx, lo)
                for k in range(nummeshes):
                    meo = lo + meshoff + k * VTX_MESH
                    numgroups, groupoff = struct.unpack_from('<2i', vtx, meo)
                    for s in range(numgroups):
                        yield i, j, l, k, meo + groupoff + s * VTX_GROUP


def fingers_only(mdl_path, vvd, vtx):
    """returns (patched .vtx bytes, stats); stats = dict(meshes, kept, removed, first): meshes of
    the bare arm, its triangles that stay / were removed, and the file offset of the first one
    removed (None if there was none). Applying it to an already patched file changes nothing."""
    info = mdl_lite.read(mdl_path)
    hand = [is_hand_bone(b['name']) for b in info['bones']]
    bare = [t.lower().startswith(BARE_PREFIX) for t in info['textures']]
    bones = read_vvd_bones(vvd)
    on_hand = [hand[b] if b < len(hand) else False for b in bones]

    out = bytearray(vtx)
    stats = dict(meshes=0, kept=0, removed=0, first=None)
    seen = set()
    for bp, model, lod, mesh, so in walk_vtx(vtx):
        try:
            m = info['bodyparts'][bp]['models'][model]
            me = m['meshes'][mesh]
        except IndexError:
            raise PatchError('.vtx and .mdl do not describe the same model')
        if not bare[me['material']]:
            continue
        if lod != 0:
            raise PatchError('the bare arm has several levels of detail, which this tool does not handle')
        if (bp, model, mesh) not in seen:
            seen.add((bp, model, mesh))
            stats['meshes'] += 1

        base = m['vertexindex'] // VVD_VERTEX + me['vertoffset']
        numverts, vertoff, numindices, indexoff, numstrips, stripoff = struct.unpack_from('<6i', vtx, so)
        # strip group vertex -> does it move with the hand?
        keep = []
        for v in range(numverts):
            mesh_vertex = struct.unpack_from('<H', vtx, so + vertoff + v * VTX_VERTEX + 4)[0]
            if mesh_vertex >= me['numverts']:
                raise PatchError('a vertex of the bare arm is outside of its mesh')
            keep.append(on_hand[base + mesh_vertex])

        for t in range(numstrips):
            sth = so + stripoff + t * VTX_STRIP
            count, first = struct.unpack_from('<2i', vtx, sth)
            flags = vtx[sth + 18]
            if not flags & STRIP_IS_TRILIST or count % 3 or first + count > numindices:
                raise PatchError('the bare arm is not stored as a plain triangle list')
            for q in range(first, first + count, 3):
                at = so + indexoff + q * 2
                a, b, c = struct.unpack_from('<3H', vtx, at)
                if a == b == c:
                    continue  # collapsed earlier
                if keep[a] and keep[b] and keep[c]:
                    stats['kept'] += 1
                else:
                    struct.pack_into('<3H', out, at, a, a, a)
                    stats['removed'] += 1
                    if stats['first'] is None or at < stats['first']:
                        stats['first'] = at
    return bytes(out), stats


def is_removed(vtx, offset):
    """is the triangle stored at this file offset one that fingers_only() removed?"""
    if offset < 0 or offset + 6 > len(vtx):
        return False
    a, b, c = struct.unpack_from('<3H', vtx, offset)
    return a == b == c


def count_bare(mdl_path, vvd, vtx):
    """(triangles of the bare arm that are drawn, those of them that are not on a hand)"""
    info = mdl_lite.read(mdl_path)
    hand = [is_hand_bone(b['name']) for b in info['bones']]
    bare = [t.lower().startswith(BARE_PREFIX) for t in info['textures']]
    bones = read_vvd_bones(vvd)
    drawn = wrong = 0
    for bp, model, _lod, mesh, so in walk_vtx(vtx):
        m = info['bodyparts'][bp]['models'][model]
        me = m['meshes'][mesh]
        if not bare[me['material']]:
            continue
        base = m['vertexindex'] // VVD_VERTEX + me['vertoffset']
        numverts, vertoff, numindices, indexoff, _numstrips, _stripoff = struct.unpack_from('<6i', vtx, so)
        ids = [struct.unpack_from('<H', vtx, so + vertoff + v * VTX_VERTEX + 4)[0] for v in range(numverts)]
        for q in range(0, numindices - 2, 3):
            a, b, c = struct.unpack_from('<3H', vtx, so + indexoff + q * 2)
            if a == b == c:
                continue
            drawn += 1
            if not all(hand[bones[base + ids[x]]] for x in (a, b, c)):
                wrong += 1
    return drawn, wrong


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    for mdl_path in argv:
        stem = mdl_path[:-4]
        with open(stem + '.vvd', 'rb') as f:
            vvd = f.read()
        with open(stem + '.dx90.vtx', 'rb') as f:
            vtx = f.read()
        patched, stats = fingers_only(mdl_path, vvd, vtx)
        changed = sum(1 for x, y in zip(vtx, patched) if x != y)
        print('%s: bare arm in %d meshes, %d triangles stay (hands and fingers), %d would be removed (%d bytes differ)'
              % (mdl_path, stats['meshes'], stats['kept'], stats['removed'], changed))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
