#!/usr/bin/env python3
"""Render staged unlock-order perk shorts in selected languages.
Requires Godot 4.7, an X11 display, FFmpeg/libass, numpy and Pillow.
Videos are staged training-room comparisons using real game simulation.
"""
import argparse, concurrent.futures, json, os, subprocess, time, wave
from pathlib import Path
import numpy as np
from PIL import ImageFont

ROOT = Path(__file__).resolve().parents[1]
IDS = ['rapid_fire','heavy_armor','sprinter','regen','quick_vent']
SECOND_IDS = ['evasion','scavenger','nitro','shield','double_shot']
LANGS = ['ru','en','fr','es']
SERIES_TOTAL = 5
ISO = {'ru':'rus','en':'eng','fr':'fra','es':'spa'}
LABELS = {
 'ru': ['Открывается на {n} уровне профиля', 'БЕЗ ПЕРКА', 'С ПЕРКОМ', 'ВЫСТРЕЛЫ', 'HP', 'СКОРОСТЬ', 'СЕРИЯ ПЕРКОВ'],
 'en': ['Unlocks at profile level {n}', 'NO PERK', 'WITH PERK', 'SHOTS', 'HP', 'SPEED', 'PERK SERIES'],
 'fr': ['Débloqué au niveau de profil {n}', 'SANS ATOUT', 'AVEC ATOUT', 'TIRS', 'PV', 'VITESSE', 'SÉRIE ATOUTS'],
 'es': ['Se desbloquea en el nivel de perfil {n}', 'SIN MEJORA', 'CON MEJORA', 'DISPAROS', 'PV', 'VELOCIDAD', 'SERIE DE MEJORAS'],
}
# These shorter editorial captions are checked against perks.json, dumped by Godot.
CAPTIONS = {
 'rapid_fire': {
  'ru': ['Перезарядка на 40% короче.', 'На 30% меньше нагрева за выстрел.', 'Больше выстрелов в каждой очереди.'],
  'en': ['40% shorter reload time.', '30% less heat per shot.', 'More shots in every burst.'],
  'fr': ['Temps de rechargement réduit de 40 %.', '30 % de chauffe en moins par tir.', 'Plus de tirs dans chaque rafale.'],
  'es': ['Tiempo de recarga un 40 % menor.', 'Un 30 % menos de calor por disparo.', 'Más disparos en cada ráfaga.'],
 },
 'heavy_armor': {
  'ru': ['Максимальная прочность: +50%.', 'На базовом танке: 100 HP → 150 HP.', 'Выдержи больше попаданий.'],
  'en': ['Maximum hull health: +50%.', 'Base tank: 100 HP → 150 HP.', 'Survive more hits.'],
  'fr': ['Résistance maximale : +50 %.', 'Char de base : 100 PV → 150 PV.', 'Encaissez davantage de tirs.'],
  'es': ['Resistencia máxima: +50 %.', 'Tanque base: 100 PV → 150 PV.', 'Resiste más impactos.'],
 },
 'sprinter': {
  'ru': ['Максимальная скорость: +25%.', 'Быстрее двигайся по карте.', 'Займи позицию раньше противника.'],
  'en': ['Maximum movement speed: +25%.', 'Move across the map faster.', 'Reach your position before the enemy.'],
  'fr': ['Vitesse maximale : +25 %.', 'Traversez la carte plus vite.', 'Prenez position avant l’ennemi.'],
  'es': ['Velocidad máxima: +25 %.', 'Recorre el mapa más rápido.', 'Toma posición antes que el enemigo.'],
 },
 'regen': {
  'ru': ['Восстанавливает 1 HP в секунду.', 'Это 60 HP за минуту.', 'Ремонт продолжается прямо в бою.'],
  'en': ['Restores 1 HP every second.', 'That is 60 HP per minute.', 'Keep repairing during combat.'],
  'fr': ['Restaure 1 PV par seconde.', 'Soit 60 PV par minute.', 'Réparez même pendant le combat.'],
  'es': ['Recupera 1 PV por segundo.', 'Son 60 PV por minuto.', 'Sigue reparándote durante el combate.'],
 },
 'quick_vent': {
  'ru': ['Раньше возвращает огонь после перегрева.', 'Порог возврата: 55% нагрева вместо 30%.', 'Снова в бой примерно на треть раньше.'],
  'en': ['Resume firing sooner after overheating.', 'Resume at 55% heat instead of 30%.', 'Back in action about a third sooner.'],
  'fr': ['Reprenez le tir plus tôt après surchauffe.', 'Reprise à 55 % de chaleur au lieu de 30 %.', 'De nouveau en action environ un tiers plus tôt.'],
  'es': ['Vuelve a disparar antes tras sobrecalentarte.', 'Reanuda al 55 % de calor en vez del 30 %.', 'Vuelve a la acción casi un tercio antes.'],
 },
}
CAPTIONS.update({
 'evasion': {'en': ['15% chance to dodge an enemy hit.', 'A successful dodge prevents all hit damage.', 'Chance-based defense. Every hit rolls again.']},
 'scavenger': {'en': ['Destroy a building with your fire: +3 HP.', 'Healing stops at your maximum hull health.', 'Turn enemy cover into repairs.']},
 'nitro': {'en': ['Activate a speed burst for 2.5 seconds.', '50% faster movement. 7-second cooldown.', 'Close the gap or escape incoming fire.']},
 'shield': {'en': ['A barrier absorbs the first 30 damage.', 'The shield recharges on a 30-second cycle.', 'Keep more hull health after the same hits.']},
 'double_shot': {'en': ['Fire two parallel shells in every volley.', 'Each shell deals 60% damage. Total: 120%.', 'Land both shells for the full damage bonus.']},
})
OVERRIDE = '''[display]\nwindow/size/viewport_width=1080\nwindow/size/viewport_height=1920\nwindow/size/window_width_override=1080\nwindow/size/window_height_override=1920\nwindow/vsync/vsync_mode=0\n[editor]\nmovie_writer/fps=30\nmovie_writer/mjpeg_quality=0.95\n'''


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def probe(path):
    return json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))


def capture_one(args, out, perk):
    path = out/'raw'/f'{perk}.avi'
    log = out/'logs'/f'capture-{perk}.log'
    env = os.environ.copy()
    env.update(DISPLAY=args.display, LP_NUM_THREADS='2', XDG_CONFIG_HOME='/workspace/.config', XDG_CACHE_HOME='/workspace/.cache', XDG_DATA_HOME=str(out/'.profiles'/perk))
    cmd = [args.godot,'--path',str(ROOT/'godot'),'--audio-driver','Dummy','--resolution','1080x1920','--write-movie',str(path),'--fixed-fps','30','tests/perk_short.tscn','--',f'--perk={perk}','--frames=450',f'--dump={out / "perks.json"}',f'--telemetry={out / "logs" / (perk+"-telemetry.json")}']
    # Only the first process writes shared metadata.
    if perk != IDS[0]: cmd = [s for s in cmd if not s.startswith('--dump=')]
    with log.open('w') as f:
        process = subprocess.Popen(cmd, env=env, stdout=f, stderr=subprocess.STDOUT)
        start = time.monotonic()
        while process.poll() is None:
            time.sleep(10)
            tail = log.read_text(errors='replace').splitlines()[-3:]
            print('CAPTURE',perk,f'{time.monotonic()-start:.0f}s', ' | '.join(tail)[-250:], flush=True)
        if process.returncode: raise RuntimeError(f'{perk}: capture failed, see {log}')
    if 'SCRIPT ERROR:' in log.read_text(): raise RuntimeError(f'{perk}: script error, see {log}')
    p = probe(path); v = next(s for s in p['streams'] if s['codec_type']=='video')
    assert (v['width'],v['height']) == (1080,1920), (perk,v)
    assert abs(float(p['format']['duration'])-15) < .1, p
    print('CAPTURE OK',perk,flush=True)


def music(out):
    sr=48000; n=15*sr; signal=np.zeros(n,dtype=np.float64)
    rng=np.random.default_rng(20261024)
    notes=[146.832,174.614,220.0,196.0,146.832,174.614,261.626,220.0]
    for beat in range(30):
        start=int(beat*.5*sr)
        t=np.arange(min(int(.42*sr),n-start))/sr
        bass=.085*np.sin(2*np.pi*notes[(beat//2)%8]/2*t)*np.exp(-t*8)
        signal[start:start+len(t)]+=bass
        if beat%2==0:
            kick=.07*np.sin(2*np.pi*(48*t+40*(1-np.exp(-t*30))/30))*np.exp(-t*24)
            signal[start:start+len(t)]+=kick
        t=np.arange(min(int(.32*sr),n-start))/sr
        arp=.028*np.tanh(2*np.sin(2*np.pi*notes[beat%8]*2*t))*np.exp(-t*15)
        signal[start:start+len(t)]+=arp
    for beat in range(60):
        start=int(beat*.25*sr); length=min(int(.035*sr),n-start)
        noise=rng.normal(0,.008,length)*np.exp(-np.arange(length)/sr*120)
        signal[start:start+length]+=noise
    signal[:int(.25*sr)]*=np.linspace(0,1,int(.25*sr))
    signal[-int(.4*sr):]*=np.linspace(1,0,int(.4*sr))
    stereo=np.column_stack([signal,signal*.96])
    path=out/'music-original.wav'
    with wave.open(str(path),'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes((np.clip(stereo,-1,1)*32767).astype('<i2').tobytes())
    return path

FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'


def wrap(text, size, width, bold=False):
    font=ImageFont.truetype(BOLD if bold else FONT,size)
    lines=['']
    for word in text.split():
        candidate=(lines[-1]+' '+word).strip()
        if font.getlength(candidate)>width and lines[-1]: lines.append(word)
        else: lines[-1]=candidate
    return lines


def ass_escape(text):
    return text.replace('\\','\\\\').replace('{','\\{').replace('}','\\}').replace('\n',r'\N')


def srt_time(t):
    ms=int(round(t*1000)); return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'


def write_captions(out,item,index,lang):
    name=item['texts'][lang]['name']; level=LABELS[lang][0].format(n=item['level'])
    entries=[(0,3,name+'\n'+level),(3,8,CAPTIONS[item['id']][lang][0]),(8,12,CAPTIONS[item['id']][lang][1]),(12,15,CAPTIONS[item['id']][lang][2])]
    stem=f'{index:02}_{item["id"]}.{lang}'
    srt=out/'subtitles'/(stem+'.srt')
    srt.write_text('\n\n'.join(f'{i+1}\n{srt_time(a)} --> {srt_time(b)}\n{text}' for i,(a,b,text) in enumerate(entries))+'\n',encoding='utf-8')
    styles='''[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
ScaledBorderAndShadow: yes
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Brand,DejaVu Sans,40,&H00F4F4ED,&H000000FF,&H00101418,&H00000000,-1,0,0,0,100,100,3,0,1,0,0,7,0,0,0,1
Style: Title,DejaVu Sans,66,&H00F4F4ED,&H000000FF,&H00101418,&H00000000,-1,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1
Style: Small,DejaVu Sans,28,&H00B1C4CF,&H000000FF,&H00101418,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1
Style: Level,DejaVu Sans,32,&H0083DFC7,&H000000FF,&H00101418,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,8,0,0,0,1
Style: Label,DejaVu Sans,30,&H00E7F4EF,&H000000FF,&H00101418,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1
Style: Caption,DejaVu Sans,50,&H00F4F4ED,&H000000FF,&H00101418,&H00000000,-1,0,0,0,100,100,0,0,1,2,1,5,0,0,0,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
'''
    lines=[]
    def event(style,text,x,y,start=0,end=15,extra=''):
        def fmt(t): return f'0:{int(t)//60:02}:{t%60:05.2f}'
        lines.append(f'Dialogue: 0,{fmt(start)},{fmt(end)},{style},,0,0,0,,{{\\pos({x},{y})\\fad(140,100){extra}}}'+ass_escape(text))
    event('Brand','IRON STORM',64,76)
    event('Small',f'{index:02} / {SERIES_TOTAL:02}',900,86)
    event('Small',LABELS[lang][6],240,206)
    title_lines=wrap(name,66,740,True)
    assert len(title_lines)<=2,(name,title_lines)
    event('Title','\n'.join(title_lines),240,250)
    event('Level',level,540,416)
    for i in range(2):
        event('Label',LABELS[lang][1+i],90,546+i*424)
        unit='DAMAGE' if item['id']=='double_shot' else 'DISTANCE' if item['id']=='nitro' else LABELS[lang][4] if item['id'] in ['heavy_armor','regen','evasion','scavenger','shield'] else LABELS[lang][5] if item['id']=='sprinter' else LABELS[lang][3]
        if item['id'] not in ['heavy_armor','regen','evasion','scavenger','shield']:
            event('Small',unit,750,550+i*424,extra=r'\an9')
    for a,b,text in entries[1:]:
        wrapped=wrap(text,50,916,True)
        assert len(wrapped)<=3,(lang,text,wrapped)
        event('Caption','\n'.join(wrapped),540,1510,a,b)
    if item['id'] in SECOND_IDS:
        event('Small','STAGED TRAINING COMPARISON',64,1660)
    event('Small','IRON STORM',64,1780)
    event('Small',f'#{index:02}',950,1780)
    ass=out/'subtitles'/(stem+'.ass');ass.write_text(styles+'\n'.join(lines)+'\n',encoding='utf-8')
    return srt,ass


def encode_variant(out,index,item,lang,bed):
    stem=f'{index:02}_{item["id"]}.{lang}'
    srt,ass=write_captions(out,item,index,lang)
    target=out/lang/(stem+'.mp4')
    cmd=['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(out/'raw'/(item['id']+'.avi')),'-i',str(bed),'-filter_complex',f'[0:v]scale=in_range=pc:out_range=tv:out_color_matrix=bt709,ass={ass}:fontsdir=/usr/share/fonts/truetype/dejavu,format=yuv420p[v];[0:a]volume=0.85[a0];[1:a]volume=0.6[a1];[a0][a1]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.93[a]','-map','[v]','-map','[a]','-t','15','-r','30','-c:v','libx264','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-preset','fast','-crf','20','-threads','2','-c:a','aac','-b:a','160k','-ar','48000','-movflags','+faststart',str(target)]
    run(cmd)
    p=probe(target); v=next(s for s in p['streams'] if s['codec_type']=='video')
    assert (v['width'],v['height'],v['pix_fmt'])==(1080,1920,'yuv420p'),target
    assert abs(float(p['format']['duration'])-15)<.1,target
    poster=out/'posters'/(stem+'.jpg')
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss','4','-i',str(target),'-frames:v','1','-q:v','2',str(poster)])
    print('ENCODE OK',target.name,round(target.stat().st_size/1048576,2),'MiB',flush=True)
    return target


def make_master(out,item,index,bed):
    target=out/'masters'/f'{index:02}_{item["id"]}.multisub.mp4'
    # Burned variants above are ready to publish; this master keeps four selectable tracks.
    cmd=['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(out/'raw'/(item['id']+'.avi')),'-i',str(bed)]
    for lang in ['en','fr','es','ru']:cmd+=['-i',str(out/'subtitles'/f'{index:02}_{item["id"]}.{lang}.srt')]
    cmd+=['-filter_complex','[0:a]volume=0.85[a0];[1:a]volume=0.6[a1];[a0][a1]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.93[a]','-map','0:v','-map','[a]']
    for j in range(4):cmd+=['-map',f'{j+2}:s:0']
    cmd+=['-vf','scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p','-t','15','-c:v','libx264','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-preset','fast','-crf','20','-pix_fmt','yuv420p','-threads','2','-c:a','aac','-b:a','160k','-c:s','mov_text','-movflags','+faststart']
    for j,lang in enumerate(['en','fr','es','ru']):cmd += [f'-metadata:s:s:{j}',f'language={ISO[lang]}']
    cmd+=[str(target)];run(cmd)
    p=probe(target);assert len([s for s in p['streams'] if s['codec_type']=='subtitle'])==4
    print('MASTER OK',target.name,flush=True)


def main():
    global IDS, LANGS, SERIES_TOTAL
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path,required=True);parser.add_argument('--godot',default='godot');parser.add_argument('--display',default=':89');parser.add_argument('--capture',action='store_true');parser.add_argument('--jobs',type=int,default=2);parser.add_argument('--one',default='');parser.add_argument('--capture-ids',default=','.join(IDS))
    parser.add_argument('--batch',choices=['first','second'],default='first');parser.add_argument('--languages',default='ru,en,fr,es')
    args=parser.parse_args();out=args.out.resolve()
    if args.batch=='second':
        IDS=SECOND_IDS
        SERIES_TOTAL=10
        if args.capture_ids=='rapid_fire,heavy_armor,sprinter,regen,quick_vent':args.capture_ids=','.join(IDS)
    LANGS=args.languages.split(',')
    if args.batch=='second' and LANGS!=['en']:parser.error('Second batch currently has English captions only; use --languages en')
    start_index=6 if args.batch=='second' else 1
    os.environ.setdefault('XDG_CACHE_HOME','/workspace/.cache')
    for name in ['raw','ru','en','fr','es','subtitles','masters','posters','logs']:(out/name).mkdir(parents=True,exist_ok=True)
    if args.capture:
        override=ROOT/'godot/override.cfg';original=override.read_bytes() if override.exists() else None
        try:
            override.write_text(OVERRIDE)
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:list(pool.map(lambda perk:capture_one(args,out,perk),args.capture_ids.split(',')))
        finally:
            if original is None:override.unlink(missing_ok=True)
            else:override.write_bytes(original)
    items=json.loads((out/'perks.json').read_text())
    assert [x['id'] for x in items]==IDS
    if args.batch=='first':
        assert [x['level'] for x in items]==[1,1,1,2,2]
        assert items[0]['mods']['fireRateMult']==.6 and items[0]['mods']['heatPerShotMult']==.7
        assert items[1]['mods']['maxHPMult']==1.5 and items[2]['mods']['speedMult']==1.25
        assert items[3]['mods']['regenPerMinute']==60 and items[4]['mods']['heatResumeAdd']==.25
    else:
        assert [x['level'] for x in items]==[3,3,4,4,5]
        assert abs(items[0]['mods']['evasionChance']-.15)<1e-9
        assert items[1]['mods']['scavengeHeal']==3
    bed=out/'music-original.wav'
    if not bed.exists(): music(out)
    selected=[(index,item,lang) for index,item in enumerate(items,start_index) for lang in LANGS if not args.one or item['id']==args.one]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:list(pool.map(lambda row:encode_variant(out,*row,bed),selected))
    if not args.one and set(LANGS)=={'ru','en','fr','es'}:
        for index,item in enumerate(items,start_index):make_master(out,item,index,bed)
    print('DONE',out,flush=True)
if __name__=='__main__':main()
