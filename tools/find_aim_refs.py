"""Find ARM64 ADRP references to the verified aim globals page, statically."""
import pathlib,json,struct,time,resource
resource.setrlimit(resource.RLIMIT_AS,(64*1024*1024,64*1024*1024))
resource.setrlimit(resource.RLIMIT_CPU,(30,30))
root=pathlib.Path('evidence/native');m=json.loads((root/'metadata.json').read_text());sec=next(x for x in m['sections'] if x['name']=='__text');out=[]
with open('/tmp/finalhour-binary','rb') as f:
 for rel in range(0,sec['size'],4096):
  addr=sec['address']+rel;size=min(4096,sec['size']-rel);f.seek(sec['offset']+rel);b=f.read(size+160)
  # Sections need not begin on a 4K page boundary: split address arithmetic by instruction PC page.
  for pcpage in set([addr&~4095,(addr+size-1)&~4095]):
   delta=(0x10eb22000-pcpage)>>12;op=0x90000000|((delta&3)<<29)|(((delta>>2)&0x7ffff)<<5);upper=struct.pack('<I',op)[1:];pos=0
   while True:
    j=b.find(upper,pos)
    if j<0:break
    i=j-1;pos=j+1
    if i<0 or i>=size or i%4 or ((addr+i)&~4095)!=pcpage or b[i]&224!=op&224:continue
    code=b[i:i+160];words=struct.unpack('<'+'I'*(len(code)//4),code[:len(code)//4*4])
    # Keep references to the aim settings portion, including ADD or load/store forms.
    hit=False
    for w in words[1:18]:
     if (w&0x7f000000)==0x11000000 and 0x430<=((w>>10)&4095)<=0x458:hit=True
     scale=(w>>30)&3;imm=((w>>10)&4095)<<scale
     if (w&0x3b000000)==0x39000000 and 0x430<=imm<=0x458:hit=True
    if hit:
     start=max(0,i-100);start-=start%4;entry=dict(address=addr+start,size=len(b[start:i+160]),ref=addr+i)
     name=f"ref-{addr+i:x}.bin";(root/name).write_bytes(b[start:i+160]);entry['file']=name;entry['name']='aim-global-reference';out.append(entry)
  if rel%(1024*1024)==0:time.sleep(.01)
(root/'references.json').write_text(json.dumps(out,indent=2));print('references',len(out))
