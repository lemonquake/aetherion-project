"""Prepare recorded surface footsteps. Source and licence: docs/MALL_HORROR.md.

Uses IENBA's CC0 shoe-on-metal recording, with isolated transients and short
natural tails. Tile/rubber variants use the existing CC0 Sleep recorded foley.
"""
from pathlib import Path
import json
import subprocess
import wave
import numpy as np
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/audio/mall'
FF = imageio_ffmpeg.get_ffmpeg_exe()
RATE = 44100


def read(path):
    data = subprocess.run([FF, '-v','error','-i',str(path),'-ac','1','-ar',str(RATE),
                           '-f','f32le','-'], capture_output=True, check=True).stdout
    return np.frombuffer(data,dtype='<f4').copy()


def save(name, a):
    a = a - np.mean(a)
    # Gentle sub-bass cleanup and fades keep short samples free of clicks.
    a *= .74 / max(float(np.max(np.abs(a))), .01)
    fade = min(256,len(a)//8)
    a[:fade] *= np.linspace(0,1,fade)
    a[-fade*3:] *= np.linspace(1,0,fade*3)
    path = OUT / (name+'.wav')
    with wave.open(str(path),'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(RATE)
        f.writeframes((np.clip(a,-1,1)*32767).astype('<i2').tobytes())
    return path.relative_to(ROOT/'game').as_posix()


def build():
    from scipy.signal import butter, sosfilt
    OUT.mkdir(parents=True,exist_ok=True)
    metal = read(ROOT/'work/r19/source/metal_steps.mp3')
    files=[]
    for i, onset in enumerate([1.48,2.98,4.50,6.00,7.47,8.99]):
        a=metal[int(onset*RATE):int((onset+.55)*RATE)]
        a=sosfilt(butter(2,[100,5600],btype='bandpass',fs=RATE,output='sos'),a)
        files.append(save('escalator_%02d'%i,a))
    defs=json.loads((ROOT/'game/data/sounds.json').read_text())
    template={'files':files,'db':-5.5,'dist':28.0,'pitch':.035,'prio':4,'unit':2.5}
    defs['sounds']['step_escalator']=template
    for surface,source,cut,db in [('tile','concrete',8500,-2.5),('rubber','carpet',2100,-2.0)]:
        files=[]
        for i in range(5):
            a=read(ROOT/('game/assets/audio/sleep/footsteps/footstep_%s_%03d.ogg'%(source,i)))
            a=sosfilt(butter(2,cut,fs=RATE,output='sos'),a)
            files.append(save('%s_%02d'%(surface,i),a))
        defs['sounds']['step_'+surface]=dict(template,files=files,db=db,pitch=.045)
    (ROOT/'game/data/sounds.json').write_text(json.dumps(defs,indent=1)+'\n')
    print('Prepared 16 recorded footsteps: escalator, ceramic tile and rubber.')


if __name__=='__main__':
    build()
