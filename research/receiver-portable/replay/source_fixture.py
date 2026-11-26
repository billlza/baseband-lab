# SPDX-License-Identifier: GPL-3.0-or-later
"""Create deterministic synthetic controls for the RF-Stream-PHY frame adapter.

The source PHY is documented at https://github.com/lkk688/RF-Stream-PHY .
All samples here are generated locally and have no physical provenance.
"""
import argparse
import cmath
import hashlib
import json
import math
from pathlib import Path
import struct
import zlib


USED = [k for k in range(-26,27) if k]
PILOTS = (-21,-7,7,21)
DATA = [k for k in USED if k not in PILOTS]
EVEN_SIGNS = (-1,1,1,-1,-1,1,-1,1,-1,-1,1,1,1,1,1,1,1,-1,1,-1,1,-1,-1,1,1,1)
DFT = {k: [cmath.exp(2j*math.pi*((k+32)%64)*n/64)/8 for n in range(64)] for k in USED}


def useful(symbols):
    return [sum(v*DFT[k][i] for k,v in symbols.items()) for i in range(64)]


def wrap(symbols):
    wave=useful(symbols)
    return wave[-16:]+wave


def source_symbol(bits):
    if len(bits)==2:
        return (1+1j,-1+1j,-1-1j,1-1j)[2*bits[0]+bits[1]]/math.sqrt(2)
    level=(-3,-1,3,1)
    return (level[2*bits[0]+bits[1]]+1j*level[2*bits[2]+bits[3]])/math.sqrt(10)


def frame(mod, payload, flip):
    width=2 if mod=="qpsk" else 4
    body=struct.pack("<4sHHH",b"AIS1",0,1,len(payload))+payload
    tx=bytearray(body+struct.pack("<I",zlib.crc32(body)))
    if flip: tx[10]^=0x80  # Keep the original checksum on the wire.
    bits=[]
    state=127
    for byte in tx:
        for shift in reversed(range(8)):
            top=state>>6
            bits.append(((byte>>shift)&1)^top)
            state=((state<<1) | (top ^ ((state>>3)&1))) & 127
    bits += [0]*(-len(bits)%(48*width))
    stf=useful(dict(zip((k for k in USED if k%2==0),EVEN_SIGNS)))
    samples=stf[-16:]+stf*6
    samples+=wrap(dict(zip(USED,(1,-1)*26)))*4
    for s in range(len(bits)//(48*width)):
        grid={k: (1-2*(s%2))*v for k,v in zip(PILOTS,(1,1,1,-1))}
        for n,k in enumerate(DATA):
            idx=(48*s+n)*width
            grid[k]=source_symbol(bits[idx:idx+width])
        samples+=wrap(grid)
    return samples,len(bits)//(48*width)


def write(folder):
    folder.mkdir(exist_ok=False,parents=True)
    ref=hashlib.shake_256(b"source-format-control-v1").digest(512)
    (folder/"reference.bin").write_bytes(ref)
    index=[]
    for label, mod, flip, silent in [("clean","qpsk",False,False),("bit-error","qam16",True,False),("empty","qpsk",False,True)]:
        tx,symbols=frame(mod,ref,flip)
        raw=[0j]*64+tx+[0j]*64
        output=bytearray()
        for n,value in enumerate(raw):
            z=0j if silent else .8*value.conjugate()*cmath.exp(1j*(.3+n*2*math.pi*420/3e6))
            output+=struct.pack("<ff",z.real,z.imag)
        path=label+".cf32"
        (folder/path).write_bytes(output)
        index.append(dict(file=path,source=label,modulation=mod,order=4 if mod=="qpsk" else 16,
                          sampleRateHz=3e6,stf=65,stfRepeats=6,ltfs=4,symbols=symbols,reference="reference.bin"))
    (folder/"index.json").write_text(json.dumps(index,indent=2)+"\n")

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("folder",type=Path);write(p.parse_args().folder)
