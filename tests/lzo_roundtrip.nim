## Smoke test for the LZO bridge: compress -> decompress must round-trip.
import std/random
import "../src/lzo"

proc check(data: seq[byte]) =
  let comp = lzoCompress(data)
  let back = lzoDecompress(comp, data.len)
  doAssert back == data, "round-trip mismatch for len " & $data.len

# Empty, tiny, and a compressible + a random buffer.
check(@[])
check(@[byte 1, 2, 3])

var compressible = newSeq[byte](4096)
for i in 0 ..< compressible.len: compressible[i] = byte(i mod 7)
check(compressible)

var r = initRand(1234)
var noise = newSeq[byte](10000)
for i in 0 ..< noise.len: noise[i] = byte(r.rand(255))
check(noise)

echo "lzo round-trip OK"
