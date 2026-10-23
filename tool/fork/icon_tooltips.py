#!/usr/bin/env python3
"""Reject IconButton constructors without an explicit, localized tooltip.

Mask literals/comments before balancing calls, so nested buttons and strings
containing `tooltip:` cannot accidentally satisfy the outer button.
"""
import pathlib
import re
import sys

missing = []
# Mask comments and strings while keeping offsets and line numbers unchanged.
pattern=re.compile(r"//[^\n]*|/\*[\s\S]*?\*/|(?:r)?'''[\s\S]*?'''|(?:r)?\"\"\"[\s\S]*?\"\"\"|(?:r)?'(?:\\.|[^'\\])*'|(?:r)?\"(?:\\.|[^\"\\])*\"")
for p in pathlib.Path('lib').rglob('*.dart'):
 s=p.read_text();masked=pattern.sub(lambda m:re.sub(r'[^\n]',' ',m[0]),s)
 for m in re.finditer(r'\bIconButton(?:\.(?:filled|filledTonal|outlined))?\s*\(',masked):
  start=m.end();depth=1;i=start;has=False
  while i<len(masked) and depth:
   if depth==1 and re.match(r'tooltip\s*:',masked[i:]):has=True
   depth+=(masked[i]=='(')-(masked[i]==')');i+=1
  if not has:
   missing.append(f'{p}:{s.count(chr(10), 0, m.start()) + 1}: IconButton needs tooltip')

print("\n".join(missing) if missing else "All IconButtons have tooltips.")
sys.exit(bool(missing))
