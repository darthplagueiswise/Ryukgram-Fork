#!/usr/bin/env python3
import hashlib, hmac, os, struct, subprocess, sys, zlib

MAGIC = b"RGSB"
VERSION = 1
ITERS = 20000
FLAG_DEFLATE = 0x01

MIX = 0x5B5486090AA25EE3
STORED = [0x64ECA42D62DC6C78, 0x72226F81A8CF5D9E, 0xF2C6CF91F7D0D235,
          0xB3C74F3E7A9AB07B, 0xFFFBE9CD98EAA363, 0x71B25E1436CCCB56]
M64 = (1 << 64) - 1


def _xs(x):
    x &= M64
    x ^= (x << 13) & M64
    x ^= (x >> 7)
    x ^= (x << 17) & M64
    return x & M64


def _secret():
    x = MIX
    words = []
    for st in STORED:
        x = _xs(x)
        words.append((st ^ x) & M64)
    return struct.pack("<6Q", *words)


def _pkcs7(data, block=16):
    pad = block - (len(data) % block)
    return data + bytes([pad]) * pad


def _aes_cbc_nopad(key, iv, padded):
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        e = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
        return e.update(padded) + e.finalize()
    except ImportError:
        pass
    try:
        from Crypto.Cipher import AES
        return AES.new(key, AES.MODE_CBC, iv).encrypt(padded)
    except ImportError:
        pass
    return subprocess.run(
        ["openssl", "enc", "-aes-256-cbc", "-nopad",
         "-K", key.hex(), "-iv", iv.hex()],
        input=padded, stdout=subprocess.PIPE, check=True).stdout


def encrypt(plaintext):
    secret = _secret()
    key = hashlib.pbkdf2_hmac("sha256", secret[:32], secret[32:], ITERS, 64)
    enc_key, mac_key = key[:32], key[32:]

    co = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed = co.compress(plaintext) + co.flush()

    iv = os.urandom(16)
    ct = _aes_cbc_nopad(enc_key, iv, _pkcs7(packed))

    hdr = MAGIC + bytes([VERSION, FLAG_DEFLATE]) + struct.pack("<I", len(plaintext)) + iv
    mac = hmac.new(mac_key, hdr + ct, hashlib.sha256).digest()
    return hdr + mac + ct


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: gen_mc_names.py <plaintext_in> <container_out>")
    with open(sys.argv[1], "rb") as f:
        plaintext = f.read()
    out = encrypt(plaintext)
    with open(sys.argv[2], "wb") as f:
        f.write(out)
    print("[gen_mc_names] %d -> %d bytes" % (len(plaintext), len(out)))


if __name__ == "__main__":
    main()
