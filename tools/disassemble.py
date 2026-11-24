import json,pathlib,sys
from capstone import Cs,CS_ARCH_ARM64,CS_MODE_LITTLE_ENDIAN
root=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else 'evidence/native');m=json.loads((root/'metadata.json').read_text());cs=Cs(CS_ARCH_ARM64,CS_MODE_LITTLE_ENDIAN)
out=pathlib.Path('disassembly');out.mkdir(exist_ok=True)
entries=m['symbols']
if (root/'references.json').exists(): entries+=json.loads((root/'references.json').read_text())
for s in entries:
 if 'file' not in s:continue
 lines=[f"; {s['name']} size={s['size']}"]
 for i in cs.disasm((root/s['file']).read_bytes(),s['address']):lines.append(f'{i.address:016x}  {i.mnemonic:8} {i.op_str}')
 (out/(s['file']+'.txt')).write_text('\n'.join(lines)+'\n')
