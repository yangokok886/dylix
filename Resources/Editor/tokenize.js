// Source text is passed as data to the bundled grammar; it is never evaluated.
function studioTokens(source, language) {
  const html = hljs.highlight(source, {language: language, ignoreIllegals: true}).value;
  const parts = html.match(/<[^>]*>|[^<]+/g) || [], scopes = [], tokens = [];
  let offset = 0, plain = '';
  const decode = t => t.replace(/&(amp|lt|gt|quot|apos|#x27|#39);/g, (_, x) => ({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'",'#x27':"'",'#39':"'"}[x]));
  for (const p of parts) {
    if (p.startsWith('</span')) scopes.pop();
    else if (p.startsWith('<span')) {const m=p.match(/class="([^"]+)"/);scopes.push(m?m[1]:'');}
    else if (!p.startsWith('<')) {const t=decode(p);if(t.length&&scopes.length)tokens.push([offset,t.length,scopes.join(' ')]);plain+=t;offset+=t.length;}
  }
  if (plain !== source) return []; // UTF-16 offsets must match native NSString exactly.
  if (language==='objectivec'||language==='cpp'||language==='c') {
    // Keep the grammar's strings, comments, keywords and types authoritative.
    // Wrapper scopes (function/params) do not prevent finer lexical styling.
    const occupied = new Uint8Array(source.length);
    for (const t of tokens) if (/hljs-(comment|string|regexp|keyword|type|title|built_in|literal|number|meta|symbol)\b/.test(t[2])) occupied.fill(1,t[0],t[0]+t[1]);
    const add = (start, text, scope) => {
      for(let i=start;i<start+text.length;i++) if(occupied[i]) return;
      tokens.push([start,text.length,'hljs-'+scope]);occupied.fill(1,start,start+text.length);
    };
    const scan = (rx, group, scope) => {let m;while((m=rx.exec(source))) {const text=m[group];add(m.index+(group?m[0].lastIndexOf(text):0),text,scope);}};
    scan(/%[A-Za-z_]+/g,0,'keyword');
    if(language==='objectivec') {
      scan(/^[ \t]*[+-]\s*\([^\n)]*\)\s*([A-Za-z_]\w*)/gm,1,'title');
      scan(/\b[A-Za-z_]\w*(?=\s*:)/g,0,'title');
      scan(/\.\s*([A-Za-z_]\w*)/g,1,'property');
      // Receiver + no-argument message, e.g. [object description].
      scan(/\b([A-Za-z_]\w*)(?=\s*\])/g,1,'title');
    }
    scan(/\b[A-Za-z_]\w*(?=\s*\()/g,0,'title');
    scan(/\b[A-Z][A-Za-z_0-9]*\b/g,0,'type');
    scan(/\b[a-z_][A-Za-z_0-9]*\b/g,0,'variable');
    scan(/[=+*\/!%<>|&^~?:-]+/g,0,'operator');
    scan(/[{}()[\].,;]/g,0,'punctuation');
  }
  return tokens;
}
