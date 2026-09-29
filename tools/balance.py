import sys
def check(path):
    s=open(path,encoding='utf-8').read()
    i=0;depth=0;in_str=False;in_com=False;line=1;starts=[]
    while i<len(s):
        c=s[i]
        if c=='\n': line+=1; in_com=False
        if in_com: i+=1; continue
        if in_str:
            if c=='\\': i+=2; continue
            if c=='"': in_str=False
            i+=1; continue
        if c==';': in_com=True; i+=1; continue
        if c=='"': in_str=True; i+=1; continue
        if c=='#' and i+1<len(s) and s[i+1]=='\\': i+=3; continue
        if c=='(': depth+=1; starts.append(line)
        elif c==')':
            depth-=1
            if starts: starts.pop()
            if depth<0: print(f"{path}: EXTRA ) at line {line}"); return
        i+=1
    # An unterminated string is the other way a file reads as nonsense. It does
    # not unbalance the parens -- a stray quote just swaps which half of the file
    # is code and which is text -- so this is its own check. It catches an ODD
    # number of stray quotes; an even number (a quoted phrase inside a docstring)
    # still slips through, and only running the file finds that.
    if in_str: print(f"{path}: UNTERMINATED STRING (opened and never closed)"); return
    if depth: print(f"{path}: depth {depth}, unclosed opened at lines {starts[-4:]}")
    else: print(f"{path}: balanced")
for p in sys.argv[1:]: check(p)
