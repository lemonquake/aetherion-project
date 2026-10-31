from pathlib import Path
import html
from PIL import Image

p=Path('website/index.html')
s=p.read_text(encoding='utf8').replace('0.18.0','0.19.0').replace('1.1.0','1.2.0')
start=s.index('    <ul class="notes" id="notes-list">')
end=s.index('    </ul>',start)
notes=[x[2:].strip() for x in Path('tools/release/notes/0.19.0.md').read_text(encoding='utf8').splitlines() if x.startswith('- ')]
s=s[:start]+'    <ul class="notes" id="notes-list">\n'+''.join('      <li>'+html.escape(x)+'</li>\n' for x in notes)+s[end:]
s=s.replace('a five-storey mall with working escalators and glass that shatters, now the night after the outbreak: dark the whole match, wrecked and bloodied, with each team starting on its own floor',
 'a five-storey mall with damaged shops, two bloodied elevators and hiding spots along the upper galleries, with each team starting on its own floor')
a=s.index('      <li><a href="/assets/img/mall.webp">')
b=s.index('      <li><a href="/assets/img/menu.webp">',a)
shots=[('mall','Cracked tiles and cold light across the Grand Atrium','The Grand Atrium, rebuilt for 0.19.0'),
 ('mall-shops','Two open elevator cabins in the damaged north lobby, lit by failing white lights','Open elevators in the Level 1 north lobby'),
 ('mall-tree','An upper gallery with damaged cover overlooking the atrium','New cover and hiding spots on the upper floors')]
s=s[:a]+''.join('      <li><a href="/assets/img/'+n+'.webp"><img src="/assets/img/'+n+'-thumb.webp" width="640" height="360" loading="lazy" alt="'+alt+'"></a><span>'+cap+'</span></li>\n' for n,alt,cap in shots)+s[b:]
feature='''<section class="band band-alt" aria-labelledby="mall-title">
  <div class="wrap mall-feature">
    <figure><a href="/assets/img/mall-shops.webp"><img src="/assets/img/mall-shops.webp" width="1600" height="900" loading="lazy" alt="Two damaged elevators in Malasugue Mall with white lights, blood trails and debris"></a><figcaption>Actual game capture · Level 1 north lobby</figcaption></figure>
    <div><p class="update-label">Map update · 0.19.0</p><h2 id="mall-title">Malasugue Mall</h2>
      <p>Malasugue Mall has been rebuilt with damaged shops, bloodied elevators and more places to hide.</p>
      <ul><li>Explore two damaged elevators in the Level 1 north lobby.</li><li>Find new cover and hiding spots along the upper galleries.</li><li>Hear different footsteps on tile, rubber and escalators.</li></ul>
      <a class="text-link" href="#download">Get the update →</a>
    </div>
  </div>
</section>

'''
if 'id="mall-title"' in s:
 a=s.index('<section class="band band-alt" aria-labelledby="mall-title">')
 b=s.index('<section class="band band-alt" aria-labelledby="shots-title">',a)
 s=s[:a]+feature+s[b:]
else:
 s=s.replace('<section class="band band-alt" aria-labelledby="shots-title">',feature+'<section class="band band-alt" aria-labelledby="shots-title">')
extra = '<li><a href="/assets/img/mall-hall.webp"><img src="/assets/img/mall-hall-thumb.webp" width="640" height="360" loading="lazy" alt="Patterned stone walkways and damaged shops in Malasugue Mall"></a><span>The mall walkways</span></li>\n<li><a href="/assets/img/mall-shaft.webp"><img src="/assets/img/mall-shaft-thumb.webp" width="640" height="360" loading="lazy" alt="Looking up through a torn elevator roof into the shaft above"></a><span>Inside the damaged elevator</span></li>\n'
if '/assets/img/mall-hall.webp' not in s:
 s=s.replace('      <li><a href="/assets/img/menu.webp">',extra+'      <li><a href="/assets/img/menu.webp">')
p.write_text(s,encoding='utf8')
Image.open('work/r19/final/atrium.png').convert('RGB').save('launcher/shared/background.jpg',quality=90)
for out,src in [('mall','atrium'),('mall-shops','lobby'),('mall-tree','gallery'),('mall-hall','hall'),('mall-shaft','shaft_up')]:
 im=Image.open('work/r19/final/'+src+'.png').convert('RGB')
 for tail,w,q in [('',1600,86),('-thumb',640,80)]:
  im.resize((w,round(im.height*w/im.width)),Image.Resampling.LANCZOS).save('website/assets/img/'+out+tail+'.webp',quality=q,method=6)
p=Path('docs/ASSET_MANIFEST.md')
if '## Malasugue Mall 0.19.0' not in p.read_text(encoding='utf8'):
 with p.open('a',encoding='utf8') as f:
  f.write('\n\n## Malasugue Mall 0.19.0\n\nOriginal generated horror material artwork and PBR atlas packing: `game/assets/mall/horror`, `tools/build_mall_horror.py`. Sixteen material families; dedicated porcelain and plaster sources. Prompts and source details: `docs/MALL_HORROR.md`.\n\nRecorded metal footsteps: [Footsteps on Metal by IENBA](https://freesound.org/people/IENBA/sounds/698697/), CC0; six isolated, filtered variants. Tile and rubber use filtered existing Kenney CC0 footstep recordings. Provenance: `game/assets/audio/mall/source.json`.\n')
print('Website source and screenshots, launcher artwork and asset manifest updated.')
