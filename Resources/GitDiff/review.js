/* TweakForge read-only review. All source HTML is escaped by diff2html / highlight.js. */
'use strict';
let payload={}, mode=innerWidth>=700?'side-by-side':'line-by-line', hunks=[], current=-1;
const $=id=>document.getElementById(id), reduced=()=>matchMedia('(prefers-reduced-motion: reduce)').matches;
function conflictPatch(item){
 const side=(text,deleted)=>deleted?[]:String(text||'').replace(/\n$/,'').split('\n');
 const ours=side(item.ours,item.oursDeleted), theirs=side(item.theirs,item.theirsDeleted);
 const name=String(item.path||'Conflict').replace(/[\r\n]/g,' ');
 return `diff --git a/${name} b/${name}\n--- a/${name}\n+++ b/${name}\n@@ -${ours.length?1:0},${ours.length} +${theirs.length?1:0},${theirs.length} @@\n`+ours.map(x=>'-'+x+'\n').join('')+theirs.map(x=>'+'+x+'\n').join('');
}
function versionLabels(){
 let old='原始版本', next='当前工作区';const note=payload.note||'';
 if(payload.compact){old='修改前';next='修改后';}
 else if(payload.conflict){old='本地 · Ours';next='合入方 · Theirs';}
 else if(note.includes('恢复后')){old='当前内容';next='恢复后';}
 else if(note.includes('暂存区')){old='HEAD';next='暂存区';}
 else if(note.includes('所选版本'))old='所选版本';else old='HEAD';
 $('old-label').textContent=old;$('new-label').textContent=next;
}
function render(){
 const target=$('diff'), patch=payload.conflict?conflictPatch(payload.conflict):payload.patch||'';
 target.replaceChildren();
 const ui=new Diff2HtmlUI(target,patch,{drawFileList:false,outputFormat:mode,matching:'lines',diffStyle:'word',renderNothingWhenEmpty:false,highlight:true,fileContentToggle:false,stickyFileHeaders:false,synchronisedScroll:true,maxLineSizeInBlockForComparison:1500,matchingMaxComparisons:1500,highlightLanguages:{xm:'objectivec',x:'objectivec',mm:'objectivec'},diffMaxChanges:4000,diffMaxLineLength:20000,diffTooBigMessage:()=> '此文件差异较大，请在编辑器中查看完整内容。'},window.hljs);
 ui.draw();
 let add=0,del=0,partial=false;const files=[...target.querySelectorAll('.d2h-file-wrapper')];
 files.forEach(file=>{
  const a=file.querySelectorAll('td.d2h-ins .d2h-code-line-ctn').length, d=file.querySelectorAll('td.d2h-del .d2h-code-line-ctn').length;
  add+=a;del+=d;const count=document.createElement('span');count.className='file-count';
  for(const [value,cls] of [[`+${a}`,'added'],[`−${d}`,'deleted']]){const span=document.createElement('span');span.className=cls;span.textContent=value;count.append(span);}
  const header=file.querySelector('.d2h-file-header');header?.append(count);
  if(file.textContent.includes('此文件差异较大')){partial=true;count.textContent='大文件';count.classList.add('partial');}
  file.querySelector('.d2h-file-collapse')?.remove();
  const toggle=document.createElement('button');toggle.className='fold-file';toggle.textContent='⌄';toggle.setAttribute('aria-label','折叠文件差异');toggle.setAttribute('aria-expanded','true');header?.prepend(toggle);
  toggle.onclick=()=>{const closed=file.classList.toggle('folded');toggle.textContent=closed?'›':'⌄';toggle.setAttribute('aria-expanded',String(!closed));toggle.setAttribute('aria-label',closed?'展开文件差异':'折叠文件差异');updatePosition();};
  file.querySelectorAll('.d2h-code-line-ctn').forEach(line=>{if(line.textContent==='File without changes')line.textContent='文件内容未变化（仅名称或属性变更）';if(line.textContent==='Empty file')line.textContent='空文件';});
  const binary=file.querySelector('.d2h-code-line-ctn');if(binary&&/^(Binary files|Binary file)/.test(binary.textContent)){binary.textContent='二进制文件发生变化，请使用对应应用查看。';}
 });
 $('summary').textContent=`${files.length} 个文件已更改`;
 $('stats').replaceChildren();for(const [text,cls]of [[`+${add}`,'added'],[`−${del}`,'deleted']]){const span=document.createElement('span');span.className=cls;span.textContent=text;$('stats').append(span);}
 if(partial)$('stats').textContent='部分差异';
 $('empty').hidden=files.length>0;
 $('unified').setAttribute('aria-pressed',String(mode==='line-by-line'));$('split').setAttribute('aria-pressed',String(mode==='side-by-side'));
 $('footer-mode').textContent=mode==='line-by-line'?'合并视图 · 双侧行号':'左右对照 · 同步滚动';
 // Only navigate visible left/unified hunk markers, avoiding duplicate split markers.
 hunks=[...target.querySelectorAll('tr')].filter(row=>row.querySelector('.d2h-info')&&!row.closest('.d2h-file-side-diff')?.previousElementSibling);
 current=-1;updatePosition();
 target.querySelectorAll('.d2h-file-collapse').forEach(button=>button.addEventListener('click',()=>requestAnimationFrame(updatePosition)));
 document.body.dataset.ready='true';
}
function visibleHunks(){return hunks.filter(h=>h.getClientRects().length>0);}
function updatePosition(){const list=visibleHunks();$('position').textContent=`${list.length?current<0?1:Math.min(current+1,list.length):0} / ${list.length}`;$('previous').disabled=$('next').disabled=list.length===0;}
function navigate(delta){const list=visibleHunks();if(!list.length)return;current=current<0?(delta>0?0:list.length-1):(current+delta+list.length)%list.length;document.querySelectorAll('.selected-hunk').forEach(x=>x.classList.remove('selected-hunk'));const row=list[current];row.classList.add('selected-hunk');window.scrollTo({top:Math.max(0,scrollY+row.getBoundingClientRect().top-document.querySelector('.review-toolbar').offsetHeight-12),behavior:reduced()?'auto':'smooth'});updatePosition();}
window.renderDiff=function(data){payload=data||{};document.body.classList.toggle('compact',!!payload.compact);document.documentElement.dataset.theme=payload.dark?'dark':'light';$('note').textContent=payload.note||'';$('info').hidden=!payload.note;versionLabels();render();};
$('unified').onclick=()=>{if(mode!=='line-by-line'){mode='line-by-line';render();}};
$('split').onclick=()=>{if(mode!=='side-by-side'){mode='side-by-side';render();}};
$('wrap').onclick=()=>{const on=document.body.classList.toggle('wrap');$('wrap').setAttribute('aria-pressed',String(on));};
$('previous').onclick=()=>navigate(-1);$('next').onclick=()=>navigate(1);
$('info').onclick=()=>{$('note').hidden=!$('note').hidden;$('info').setAttribute('aria-expanded',String(!$('note').hidden));};
