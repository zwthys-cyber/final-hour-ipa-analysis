import struct,json,pathlib
root=pathlib.Path('evidence/native');m=json.loads((root/'metadata.json').read_text());f=open('/tmp/finalhour-binary','rb')
f.seek(0);h=f.read(32);n=struct.unpack_from('<I',h,16)[0]
for _ in range(n):
 c,s=struct.unpack('<II',f.read(8));d=f.read(s-8)
 if c==2:so,count,stro,sz=struct.unpack('<IIII',d)
a=0x10eb22400;end=0x10eb22490
rows=[]
for start in range(0,count,8192):
 f.seek(so+start*16);block=f.read(min(8192,count-start)*16)
 for idx in range(0,len(block),16):
  strx,typ,sect,desc,val=struct.unpack_from('<IBBHQ',block,idx)
  if a<=val<end:
   f.seek(stro+strx);name=f.read(300).split(b'\0',1)[0].decode(errors='replace');rows.append(dict(name=name,address=hex(val),type=typ,section=sect))
seg=next(s for s in m['segments'] if s['vm']<=a<s['vm']+s['filesize']);f.seek(seg['offset']+a-seg['vm']);data=f.read(end-a)
print('SYMBOLS',rows)
for i in range(0,len(data),4):
 raw=data[i:i+4];print(hex(a+i),raw.hex(),struct.unpack('<i',raw)[0],struct.unpack('<f',raw)[0])
(root/'aim-globals.json').write_text(json.dumps(dict(address=hex(a),bytes=data.hex(),symbols=rows),indent=2))
