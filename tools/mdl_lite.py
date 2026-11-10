# -*- coding: utf-8 -*-
"""Just enough of the Source .mdl format (v44-v49) to list materials, body groups and bones."""
import struct


def _cstr(buf, off):
    end = buf.index(b'\x00', off)
    return buf[off:end].decode('latin-1')


def read(path):
    """returns dict(textures=[...], cdtextures=[...], bones=[{name, parent, pose_to_bone}],
    bodyparts=[{name, models:[{name, materials:[idx], vertexindex, meshes:[{material, numverts, vertoffset}]}]}])"""
    b = open(path, 'rb').read()
    ident, version = struct.unpack_from('<4si', b, 0)
    if ident != b'IDST' or not 44 <= version <= 49:
        raise ValueError('%s: not a supported studio model (ident %r, version %d)' % (path, ident, version))
    numbones, boneindex = struct.unpack_from('<2i', b, 156)
    numtextures, textureindex, numcdtextures, cdtextureindex = struct.unpack_from('<4i', b, 204)
    numbodyparts, bodypartindex = struct.unpack_from('<2i', b, 232)

    textures = []
    for i in range(numtextures):
        o = textureindex + i * 64
        textures.append(_cstr(b, o + struct.unpack_from('<i', b, o)[0]))
    cdtextures = []
    for i in range(numcdtextures):
        o = struct.unpack_from('<i', b, cdtextureindex + i * 4)[0]
        cdtextures.append(_cstr(b, o).replace('\\', '/').strip('/').lower())

    bones = []
    for i in range(numbones):
        o = boneindex + i * 216
        sznameindex, parent = struct.unpack_from('<2i', b, o)
        bones.append(dict(name=_cstr(b, o + sznameindex), parent=parent, pose_to_bone=struct.unpack_from('<12f', b, o + 96)))

    bodyparts = []
    for i in range(numbodyparts):
        bo = bodypartindex + i * 16
        sznameindex, nummodels, _base, modelindex = struct.unpack_from('<4i', b, bo)
        models = []
        for j in range(nummodels):
            mo = bo + modelindex + j * 148
            name = b[mo:mo + 64].split(b'\x00')[0].decode('latin-1')
            nummeshes, meshindex, _numvertices, vertexindex = struct.unpack_from('<4i', b, mo + 72)
            meshes = []
            for k in range(nummeshes):
                material, _model, numverts, vertoffset = struct.unpack_from('<4i', b, mo + meshindex + k * 116)
                meshes.append(dict(material=material, numverts=numverts, vertoffset=vertoffset))
            models.append(dict(name=name, materials=[m['material'] for m in meshes], vertexindex=vertexindex, meshes=meshes))
        bodyparts.append(dict(name=_cstr(b, bo + sznameindex), models=models))
    return dict(version=version, textures=textures, cdtextures=cdtextures, bones=bones, bodyparts=bodyparts)
