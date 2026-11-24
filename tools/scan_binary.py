"""Bounded-memory static keyword contexts; never executes target code."""
import sys,re,struct,time,resource
resource.setrlimit(resource.RLIMIT_AS,(96*1024*1024,96*1024*1024))
resource.setrlimit(resource.RLIMIT_CPU,(20,20))
words=['FinalHour','AGGames','BattleRoyale','TeamDeathmatch','Hardpoint','SearchAndDestroy','++UE5']
patterns=[(w.encode(enc),enc) for w in words for enc in ['ascii','utf-16le']]
found=set()
with open(sys.argv[1],'rb') as f:
 h=f.read(32);n=struct.unpack_from('<I',h,16)[0]
 for _ in range(n):
  c,s=struct.unpack('<II',f.read(8));d=f.read(s-8)
  if c in (0x21,0x2c):print('ENCRYPTION offset,size,cryptid:',struct.unpack_from('<III',d),flush=True)
 f.seek(0);tail=b''
 while True:
  chunk=f.read(1024*1024)
  if not chunk:break
  b=tail+chunk;tail=b[-1024:]
  for needle,enc in patterns:
   pos=0
   while True:
    p=b.find(needle,pos)
    if p<0:break
    start=max(0,p-160);end=min(len(b),p+320)
    if enc=='utf-16le':start+=(p-start)%2;end-=(end-start)%2
    s=b[start:end].decode(enc,errors='replace')
    found.add(''.join(c if c.isprintable() else ' ' for c in s));pos=p+len(needle)
  time.sleep(.03)
for s in sorted(found):print(s)
