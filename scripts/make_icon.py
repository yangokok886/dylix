#!/usr/bin/env python3
"""Render the Studio bracket-dot vector mark into an iOS icon catalog."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

folder = Path(__file__).resolve().parents[1] / 'Resources/Assets.xcassets/AppIcon.appiconset'
folder.mkdir(parents=True, exist_ok=True)
# Flat bracket-dot mark from the Studio prototype; iOS supplies its own mask.
scale = 3
image = Image.new('RGB', (1024 * scale, 1024 * scale), '#111315')
draw = ImageDraw.Draw(image)
gold = '#EDC484'
for points in [[(360,285),(275,285),(275,739),(360,739)],[(664,285),(749,285),(749,739),(664,739)]]:
    draw.line([(x*scale,y*scale) for x,y in points],fill=gold,width=42*scale,joint='curve')
draw.ellipse(tuple(v*scale for v in (469,469,555,555)),fill=gold)
entries=[]
def save(idiom,points,factor):
    filename=f'{idiom}-{points}-{factor}.png'
    size=round(points*factor)
    image.resize((size,size),Image.Resampling.LANCZOS).save(folder/filename)
    entries.append(dict(idiom=idiom,size=f'{points}x{points}',scale=f'{factor}x',filename=filename))
for idiom,sizes,factors in [('iphone',[20,29,40,60],[2,3]),('ipad',[20,29,40,76],[1,2])]:
    for points in sizes:
        for factor in factors:
            save(idiom,points,factor)
save('ipad',83.5,2)
save('ios-marketing',1024,1)
(folder/'Contents.json').write_text(json.dumps(dict(images=entries,info=dict(author='xcode',version=1)),indent=2))
print(folder)
