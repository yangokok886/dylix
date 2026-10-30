#!/usr/bin/env python3
"""Exercise the exact bundled offline renderer, including untrusted patch text."""
import json, pathlib
from playwright.sync_api import sync_playwright
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'evidence/0.6.1-diff';OUT.mkdir(parents=True,exist_ok=True)
patch='''diff --git a/设置.m b/设置.m
index abc..def 100644
--- a/设置.m
+++ b/设置.m
@@ -1,5 +1,6 @@
 #import <Foundation/Foundation.h>
 @implementation Settings
-- (NSString *)title { return @"Mobile Tweak"; }
+- (NSString *)title { return @"TweakForge"; }
+- (BOOL)enabled { return YES; }
 @end
 // end
@@ -80,3 +81,3 @@
 // extra context
-int count = 1;
+int count = 2;
 // end
'''
checks=[]
def check(name,ok):
 assert ok,name
 checks.append(name)
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless=True,args=['--allow-file-access-from-files'])
 page=browser.new_page(viewport={'width':390,'height':760},device_scale_factor=2)
 errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto((ROOT/'Resources/GitDiff/index.html').as_uri());page.wait_for_load_state('networkidle')
 requests=[];page.on('request',lambda r:requests.append(r.url))
 def render(data):page.evaluate('data=>renderDiff(data)',data)
 render({'patch':patch,'dark':True,'note':'红色：HEAD；绿色：当前工作区'})
 check('Chinese path',page.locator('.d2h-file-name').inner_text()=='设置.m')
 check('added / deleted totals',page.locator('#stats').inner_text().split()==['+3','−2'])
 check('syntax coloring',page.locator('.hljs-keyword').count()>3)
 check('word-level diff',page.locator('ins').count()>0 and page.locator('del').count()>0)
 check('old and new line numbers',page.locator('.line-num1').all_text_contents().count('81')==1 and '82' in page.locator('.line-num2').all_text_contents())
 check('two hunks',page.locator('#position').inner_text()=='1 / 2')
 page.get_by_role('button',name='下一个变更',exact=True).click();check('next navigation selects hunk',page.locator('.selected-hunk').count()==1)
 page.get_by_role('button',name='下一个变更',exact=True).click();check('second hunk navigation',page.locator('#position').inner_text()=='2 / 2')
 page.get_by_role('button',name='上一个变更',exact=True).click();check('previous hunk navigation',page.locator('#position').inner_text()=='1 / 2')
 page.get_by_role('button',name='比较说明').click();check('details disclosure',page.locator('#note').is_visible())
 page.get_by_role('button',name='比较说明').click()
 page.get_by_role('button',name='折叠文件差异').click();check('collapse file',not page.locator('.d2h-file-diff').is_visible() and page.locator('#next').is_disabled())
 page.get_by_role('button',name='展开文件差异').click();check('expand file',page.locator('.d2h-file-diff').is_visible())
 page.get_by_role('button',name='自动换行',exact=True).click();check('wrap toggle',page.locator('body').evaluate("e=>e.classList.contains('wrap')"))
 check('gutters remain on the same row',page.locator('.line-num1').first.bounding_box()['y']==page.locator('.line-num2').first.bounding_box()['y'])
 check('mobile viewport contained',page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
 check('wrap preserves code width',page.locator('.d2h-code-line-ctn').first.bounding_box()['width']>220)
 page.screenshot(path=str(OUT/'unified-wrap.png'),full_page=True)
 page.get_by_role('button',name='自动换行',exact=True).click()
 page.screenshot(path=str(OUT/'unified-dark.png'),full_page=True)
 page.get_by_role('button',name='对照',exact=True).click();check('split layout',page.locator('.d2h-file-side-diff').count()==2)
 check('split stats stable',page.locator('#stats').inner_text().split()==['+3','−2'])
 page.screenshot(path=str(OUT/'split-mobile.png'),full_page=True)
 page.set_viewport_size({'width':1100,'height':760});page.screenshot(path=str(OUT/'split-wide.png'),full_page=True)
 left=page.locator('.d2h-file-side-diff').first
 left.evaluate('e=>{e.scrollLeft=30;e.dispatchEvent(new Event("scroll"));}')
 check('synchronized horizontal scroll',page.locator('.d2h-file-side-diff').evaluate_all('es=>es[0].scrollLeft===es[1].scrollLeft'))
 page.set_viewport_size({'width':390,'height':760});page.get_by_role('button',name='合并',exact=True).click()
 render({'patch':patch,'dark':False,'note':'红色是当前内容，绿色是恢复后的内容。'})
 check('restoration labels',page.locator('#old-label').inner_text()=='当前内容' and page.locator('#new-label').inner_text()=='恢复后')
 page.screenshot(path=str(OUT/'unified-light.png'),full_page=True)
 hostile='diff --git a/unsafe.m b/unsafe.m\n--- a/unsafe.m\n+++ b/unsafe.m\n@@ -1 +1 @@\n-old\n+<img src="https://example.invalid/x" onerror="window.PWNED=1"><script>window.PWNED=1</script>\n'
 render({'patch':hostile})
 check('HTML rendered as text',page.locator('.d2h-code-line-ctn').last.inner_text().startswith('<img src='))
 check('source does not execute',page.evaluate('window.PWNED===undefined') and page.locator('#diff img,#diff script').count()==0)
 render({'patch':'diff --git a/icon.png b/icon.png\nindex abc..def 100644\nBinary files a/icon.png and b/icon.png differ\n'})
 check('binary displayed',page.locator('.d2h-file-wrapper').count()==1)
 render({'patch':''});check('empty state',page.locator('#empty').is_visible() and page.locator('#next').is_disabled())
 render({'conflict':{'path':'冲突.mm','ours':'int local = 1;\n','theirs':'int remote = 2;\n'},'note':'请选择方案','dark':True})
 check('conflict comparison',page.locator('#old-label').inner_text()=='本地 · Ours' and page.locator('#stats').inner_text().split()==['+1','−1'])
 render({'conflict':{'path':'删除.m','oursDeleted':True,'ours':'','theirs':'int value = 1;\n'}})
 check('delete / modify conflict',page.locator('#stats').inner_text().split()==['+1','−0'])
 render({'patch':'diff --git a/old.m b/new.m\nsimilarity index 100%\nrename from old.m\nrename to new.m\n'})
 check('rename-only diff',page.locator('.d2h-file-wrapper').count()==1)
 render({'patch':'diff --git a/large.m b/large.m\n--- a/large.m\n+++ b/large.m\n@@ -0,0 +1,4002 @@\n'+'+int value = 1;\n'*4002})
 check('large diff limit is explicit',page.locator('#stats').inner_text()=='部分差异' and '此文件差异较大' in page.locator('#diff').inner_text())
 check('fully offline',not requests)
 check('no runtime errors',not errors)
 browser.close()
(OUT/'renderer-tests.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'errors':errors},ensure_ascii=False,indent=2))
print(f'{len(checks)} diff renderer checks passed')
