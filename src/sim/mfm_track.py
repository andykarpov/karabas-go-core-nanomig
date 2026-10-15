#!/usr/bin/env python3
# Amiga trackdisk MFM track: 11 sectors of an ADF track, as the words a disk dma write sends.
# Usage: mfm_track.py <file.adf> <track> <out.hex> [first sector]
import sys

def odd_even(data):  # bytes -> (odd longs, even longs) of the data bits
    longs = [int.from_bytes(data[i:i+4], 'big') for i in range(0, len(data), 4)]
    return [(l >> 1) & 0x55555555 for l in longs], [l & 0x55555555 for l in longs]

def add_clock(words, prev_bit):  # 16-bit words of data bits at the odd positions -> mfm
    out = []
    for w in words:
        m = 0
        for b in range(7, -1, -1):
            d = (w >> (2 * b)) & 1
            c = 1 if (prev_bit == 0 and d == 0) else 0
            m = (m << 2) | (c << 1) | d
            prev_bit = d
        out.append(m)
    return out, prev_bit

def longs_to_words(longs):
    w = []
    for l in longs:
        w += [(l >> 16) & 0xFFFF, l & 0xFFFF]
    return w

def sector_words(adf, track, sector):
    data = adf[(track * 11 + sector) * 512:(track * 11 + sector + 1) * 512]
    info = bytes([0xFF, track, sector, 11 - sector])
    label = bytes(16)
    io, ie = odd_even(info)
    lo, le = odd_even(label)
    do, de = odd_even(data)
    hcs = 0
    for l in io + ie + lo + le: hcs ^= l
    hcs &= 0x55555555
    dcs = 0
    for l in do + de: dcs ^= l
    dcs &= 0x55555555
    co, ce = (hcs >> 1) & 0x55555555, hcs & 0x55555555
    dco, dce = (dcs >> 1) & 0x55555555, dcs & 0x55555555
    raw = longs_to_words(io + ie + lo + le + [co, ce, dco, dce] + do + de)
    mfm, _ = add_clock(raw, 1)  # after the sync word (ends with a 1 bit)
    return [0xAAAA, 0xAAAA, 0x4489, 0x4489] + mfm

adf = open(sys.argv[1], 'rb').read()
track = int(sys.argv[2])
first = int(sys.argv[4]) if len(sys.argv) > 4 else 0
words = [0xAAAA] * 8
for k in range(11):
    words += sector_words(adf, track, (first + k) % 11)
words += [0xAAAA] * 64
open(sys.argv[3], 'w').write("\n".join("%04x" % w for w in words) + "\n")
print(len(words))
