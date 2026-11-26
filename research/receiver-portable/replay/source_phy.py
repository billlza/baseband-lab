"""Decode the pinned public coax windows in their source PHY. NumPy only."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

import numpy as np


N, CP = 64, 16
USED = np.array([k for k in range(-26,27) if k])
PILOTS = np.array([-21,-7,7,21])
DATA = np.array([k for k in USED if k not in PILOTS])
POLARITY = np.array([1,1,1,-1])
HEADER = struct.Struct("<4sHHH")


def source_constellation(mod):
    if mod == "qpsk":
        return np.array([1+1j,-1+1j,-1-1j,1-1j])/np.sqrt(2)
    if mod == "qam16":
        g = np.array([-3,-1,3,1])
        return (np.repeat(g,4)+1j*np.tile(g,4))/np.sqrt(10)
    raise ValueError(mod)


def descramble(bits):
    state = 127
    out = np.empty_like(bits)
    for i,b in enumerate(bits):
        msb = state >> 6
        out[i] = int(b) ^ msb
        state = ((state << 1) | (msb ^ ((state >> 3) & 1))) & 127
    return out


def payload_result(frame, reference):
    body, tail = frame[:-4], frame[-4:]
    payload = body[HEADER.size:]
    if len(payload) != len(reference):
        raise ValueError("payload does not agree with the selected reference length")
    return dict(bits=8*len(payload),
                bit_errors=sum((a^b).bit_count() for a,b in zip(payload,reference)),
                crc32_received=tail.hex(),
                crc32_computed=zlib.crc32(body).to_bytes(4,"little").hex(),
                crc32_pass=zlib.crc32(body).to_bytes(4,"little")==tail)


def project_label_bits(symbols, order):
    """Mooring's ideal scalar hard-decision regions, translated to source labels."""
    bits = [symbols.real < 0, symbols.imag < 0]
    if order == 16:
        bits.extend([abs(symbols.real) > 2 / np.sqrt(10), abs(symbols.imag) > 2 / np.sqrt(10)])
    width = len(bits)
    labels = ((np.arange(order)[:,None] >> np.arange(width-1,-1,-1)) & 1)
    project = ((1-2*labels[:,0]) + 1j*(1-2*labels[:,1]))/np.sqrt(2)
    if order == 16:
        project = ((1-2*labels[:,0])*(1+2*labels[:,2])+1j*(1-2*labels[:,1])*(1+2*labels[:,3]))/np.sqrt(10)
    other = source_constellation("qpsk" if order==4 else "qam16")
    label_map = np.argmin(abs(project[:,None]-other[None,:]),axis=1)
    if len(set(label_map)) != order or np.max(abs(project-other[label_map]))>1e-12:
        raise ValueError("constellation mismatch")
    indexes = sum(b.astype(int) << (width-1-i) for i,b in enumerate(bits))
    return labels[label_map[indexes]].astype(np.uint8).ravel()


def decode(x, hint, cfg):
    mod, length = cfg["modulation"], cfg["ref_len"]
    bps = cfg["bps"]
    header = HEADER.pack(b"AIS1",0,1,length)
    frame_bytes = HEADER.size + length + 4
    ndata = int(np.ceil(frame_bytes*8 / (len(DATA)*bps)))
    stf = CP+N*cfg["stf_repeats"]
    ltf = cfg["ltf_symbols"]
    expected = (ltf+ndata)*(N+CP)
    if hint < 0 or hint + stf+expected+CP > len(x):
        return None, {"status":"no_complete_candidate"}
    x = x[max(0,hint-CP):hint+stf+expected+CP].astype(np.complex128)
    start = min(hint,CP)
    training = x[start:start+stf]
    omega = np.angle(np.vdot(training[:-32], training[32:]))/32
    corrected = x * np.exp(-1j*omega*np.arange(len(x)))
    ref = np.zeros(N,complex)
    ref[USED%N] = (-1.)**np.arange(len(USED))
    useful = np.fft.ifft(np.fft.ifftshift(ref))*np.sqrt(N)
    template = np.r_[useful[-CP:],useful]
    opt = corrected[start+stf-CP:start+stf+CP+len(template)]
    corr = np.abs(np.correlate(opt,template,mode="valid"))
    window_energy = np.convolve(abs(opt)**2,np.ones(len(template)),mode="valid")
    scores = corr/np.sqrt(np.maximum(window_energy*np.vdot(template,template).real,1e-35))
    if not np.all(np.isfinite(scores)) or scores.max()==0:
        return None, {"status":"no_training"}
    ltf0 = start+stf-CP+int(np.argmax(scores))
    meta = dict(ltf_offset=int(ltf0-start-stf), training_correlation=float(scores.max()),
                cfo_hz=float(omega*cfg["fs"]/(2*np.pi)))
    raw = corrected[ltf0:ltf0+expected].reshape(ltf+ndata,N+CP)[:,CP:]
    constellation = source_constellation(mod)
    candidates = []
    for conjugate in (False, True):
        y = np.fft.fftshift(np.fft.fft(raw.conj() if conjugate else raw,axis=1),axes=1)
        h = y[:ltf].mean(axis=0)[USED%N] / ref[USED%N]
        if np.any(abs(h)<1e-12): continue
        eq = np.zeros((ndata,N),complex)
        eq[:,USED%N] = y[ltf:,USED%N] / h
        pilot = (-1.)**np.arange(ndata)[:,None]*POLARITY
        cpe = np.angle((eq[:,PILOTS%N]*pilot).sum(axis=1))
        data = (eq[:,DATA%N]*np.exp(-1j*cpe[:,None])).ravel()
        for turn in range(4):
            label = np.argmin(abs(data[:,None]*(1j**turn)-constellation[None,:]),axis=1)
            bits = ((label[:,None] >> np.arange(bps-1,-1,-1)) & 1).astype(np.uint8).ravel()
            # Resolve orientation with the known ten-byte header alone. Never
            # choose a hypothesis by its payload bits or CRC.
            if np.packbits(descramble(bits[:HEADER.size*8])).tobytes() == header:
                decoded = np.packbits(descramble(bits[:frame_bytes*8])).tobytes()
                mapped = project_label_bits(data*(1j**turn), 2**bps)
                payload_slice = slice(HEADER.size*8, (HEADER.size+length)*8)
                mismatch = int(np.count_nonzero(mapped[payload_slice]!=bits[payload_slice]))
                candidates.append((decoded,conjugate,turn,mismatch))
    if len(candidates)!=1:
        return None, dict(meta,status="unidentified_header" if not candidates else "ambiguous_header")
    frame,conjugate,turn,mismatch = candidates[0]
    return frame, dict(meta,status="header_identified",conjugated=conjugate,quarter_turns=turn,
                       mapped_hard_decision_disagreements=mismatch)


def run(folder):
    manifest=json.loads((folder/"manifest.json").read_text())
    rows=[]
    for m in manifest["files"]:
        mod=m["modulation"]
        parent=folder/mod
        cfg=json.loads((parent/"rx_config.json").read_text())
        if cfg["modulation"]!=mod or cfg["repeat"]!=1 or cfg["ref_len"]!=cfg["chunk_bytes"] or cfg["ref_len"]<=0:
            raise ValueError("unsupported or unidentified transmitter reference")
        reference = np.random.default_rng(cfg["ref_seed"]).integers(0,256,size=cfg["ref_len"],dtype=np.uint8).tobytes()
        p=parent/Path(m["path"]).name
        if hashlib.sha256(p.read_bytes()).hexdigest()!=m["sha256"]:
            raise ValueError("source file hash changed")
        with np.load(p,allow_pickle=False) as archive:
            x=archive["rxw"]
            meta=json.loads(archive["meta_json"].item())
            if x.dtype!=np.complex64 or x.ndim!=1 or not np.isfinite(x).all():
                raise ValueError("invalid source IQ")
            frame,info=decode(x,int(meta["stf_idx"]),cfg)
        score=payload_result(frame,reference) if frame is not None else dict(bits=0,bit_errors=None,crc32_pass=None)
        rows.append(dict(file=p.name,modulation=mod,reference_sha256=hashlib.sha256(reference).hexdigest(),
                         source_stf_hint=int(meta["stf_idx"]),**info,**score))
    sums={}
    for mod in ("qpsk","qam16"):
        batch=[r for r in rows if r["modulation"]==mod]
        scored=[r for r in batch if r["bits"]]
        sums[mod]=dict(windows=len(batch),header_identified=len(scored),unknown=len(batch)-len(scored),
                       crc32_pass=sum(r["crc32_pass"] for r in scored),
                       crc32_fail=sum(not r["crc32_pass"] for r in scored),
                       payload_bits=sum(r["bits"] for r in scored),
                       payload_errors=sum(r["bit_errors"] for r in scored),
                       mapped_hard_decision_disagreements=sum(r["mapped_hard_decision_disagreements"] for r in scored))
    return dict(revision=manifest["revision"], sums=sums, windows=rows)

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("samples",type=Path);parser.add_argument("out",type=Path)
    args=parser.parse_args(); outcome=run(args.samples)
    args.out.write_text(json.dumps(outcome,indent=2,allow_nan=False)+"\n")
    print(json.dumps(outcome["sums"],indent=2))
