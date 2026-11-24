"""Static Mach-O metadata and selected code extraction, bounded memory."""
import struct,json,sys,pathlib,resource
resource.setrlimit(resource.RLIMIT_AS,(120*1024*1024,120*1024*1024))
f=open(sys.argv[1],'rb');out=pathlib.Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
h=f.read(32);n=struct.unpack_from('<I',h,16)[0];segments=[];sym=None;uuid=None;sections=[]
for _ in range(n):
 c,s=struct.unpack('<II',f.read(8));d=f.read(s-8)
 if c==0x1b:uuid=d.hex()
 if c==2:sym=struct.unpack('<IIII',d)
 if c==0x19:
  name,vm,vs,off,sz,ma,ini,ns,flags=struct.unpack_from('<16sQQQQiiII',d)
  segments.append(dict(name=name.rstrip(b'\0').decode(),vm=vm,size=vs,offset=off,filesize=sz))
  for j in range(ns):
   sec,seg,addr,size,offset=struct.unpack_from('<16s16sQQI',d,64+j*80)
   sections.append(dict(name=sec.rstrip(b'\0').decode(),segment=seg.rstrip(b'\0').decode(),address=addr,size=size,offset=offset))
so,count,stro,strsize=sym
# Symbol names accessed only for plausible game/global candidates, one record at a time.
found=[]
for start in range(0,count,4096):
 f.seek(so+start*16);block=f.read(min(4096,count-start)*16)
 for idx in range(0,len(block),16):
  strx,typ,sect,desc,val=struct.unpack_from('<IBBHQ',block,idx)
  if not val or typ&0xe0 or (typ&0xe)!=0xe:continue
  f.seek(stro+strx);name=f.read(500).split(b'\0',1)[0].decode(errors='replace')
  if 'AimAssist' in name or ('CVar' in name and any(k in name for k in ['Aim','AA','Follow'])):found.append(dict(name=name,address=val,section=sect))
targets=[x for x in found if x['name'] in ['__ZN19AFHPlayerController13TickAimAssistEv','__ZN19AFHPlayerController20ApplyAimAssistFollowEv']]
for item in targets:item['end']=item['address']+24576
for start in range(0,count,4096):
 f.seek(so+start*16);block=f.read(min(4096,count-start)*16)
 for idx in range(0,len(block),16):
  strx,typ,sect,desc,val=struct.unpack_from('<IBBHQ',block,idx)
  if typ&0xe0 or (typ&0xe)!=0xe:continue
  for item in targets:
   if item['address']<val<item['end']:item['end']=val
for item in targets:
 val=item['address'];sect=sections[item['section']-1];size=item['end']-val
 off=sect['offset']+val-sect['address'];f.seek(off)
 filename=f'{val:x}.bin';(out/filename).write_bytes(f.read(size));item.update(file=filename,size=size,offset=off)
meta=dict(uuid=uuid,segments=segments,sections=sections,symbols=found,symbol_count=count)
(out/'metadata.json').write_text(json.dumps(meta,indent=2));print(json.dumps({'uuid':uuid,'symbols':len(found),'count':count}))
