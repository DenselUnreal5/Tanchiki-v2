#!/usr/bin/env python3
"""Check media streams and recorded simulation telemetry for perk shorts."""
import argparse, json, subprocess
from pathlib import Path
IDS=['rapid_fire','heavy_armor','sprinter','regen','quick_vent']
LANGS=['ru','en','fr','es']
p=argparse.ArgumentParser();p.add_argument('out',type=Path);p.add_argument('--batch',choices=['first','second'],default='first');a=p.parse_args();out=a.out
if a.batch=='second':
    IDS=['evasion','scavenger','nitro','shield','double_shot']
    LANGS=['en']
start_index=6 if a.batch=='second' else 1
report={'videos':[], 'simulation':{}, 'errors':[]}
def check(condition,message):
    if not condition: report['errors'].append(message)
for id in IDS:
    path=out/'logs'/(id+'-telemetry.json');d=json.loads(path.read_text())
    check(len(d)==450,id+': 450 recorded frames')
    if id=='rapid_fire':
        counts=[row['lanes'][1]['shots']-row['lanes'][0]['shots'] for row in d]
        check(max(counts)>0,'rapid fire produces more shots')
        report['simulation'][id]={'baseline_shots':d[-1]['lanes'][0]['shots'],'perk_shots':d[-1]['lanes'][1]['shots']}
    elif id=='heavy_armor':
        check(d[0]['lanes'][0]['max_hp']==100 and d[0]['lanes'][1]['max_hp']==150,'armor raises max HP by 50%')
        check(any(r['lanes'][0]['hp']<=0<r['lanes'][1]['hp'] for r in d),'armor survives after baseline destroyed')
        report['simulation'][id]={'max_hp':[100,150]}
    elif id=='sprinter':
        x0=d[60]['lanes'][0]['x']-72;x1=d[60]['lanes'][1]['x']-72
        check(abs(x1/x0-1.25)<.01,'sprinter moves 25% farther before reaching finish')
        report['simulation'][id]={'distance_ratio_at_2_seconds':x1/x0}
    elif id=='regen':
        check(d[-1]['lanes'][0]['hp']==50 and d[-1]['lanes'][1]['hp']==65,'regeneration restores 15 HP in 15 seconds')
        check(d[-1]['lanes'][1]['shots']>0,'regeneration continues while firing')
        report['simulation'][id]={'initial_hp':50,'final_hp':[50,65]}
    elif id=='quick_vent':
        first=[next(r['frame'] for r in d if not r['lanes'][i]['overheated'])/30 for i in [0,1]]
        check(first[1]<first[0],'quick purge exits overheat earlier')
        report['simulation'][id]={'first_ready_seconds':first}
    elif id=='evasion':
        check(d[-1]['lanes'][1]['dodges']>0 and d[-1]['lanes'][0]['dodges']==0,'only evasion tank dodges native collisions')
        hp=[r['lanes'][1]['hp']-r['lanes'][0]['hp'] for r in d]
        check(max(hp)>0,'evasion prevents some real projectile damage')
        check(d[-1]['lanes'][0]['hp']<100,'evasion baseline is hit')
        report['simulation'][id]={'final_hp':[d[-1]['lanes'][i]['hp'] for i in [0,1]],'chance':0.15,'dodges':d[-1]['lanes'][1]['dodges']}
    elif id=='scavenger':
        heals=[d[i]['lanes'][1]['hp']-d[i-1]['lanes'][1]['hp'] for i in range(1,len(d))]
        heals=[h for h in heals if h>0]
        check(bool(heals) and all(abs(h-3)<.001 for h in heals),'each destroyed building heals exactly 3 HP')
        check(d[-1]['lanes'][0]['hp']==50,'scavenger baseline does not heal')
        report['simulation'][id]={'healing_events':heals,'final_hp':[d[-1]['lanes'][i]['hp'] for i in [0,1]]}
    elif id=='nitro':
        ratio=(d[30]['lanes'][1]['x']-72)/(d[30]['lanes'][0]['x']-72)
        check(abs(ratio-1.5)<.02,'nitro moves 50% farther during boost')
        check(d[0]['lanes'][1]['ability_timer']==149,'nitro begins with real 150-tick ability duration')
        check(d[75]['lanes'][1]['ability_timer']==0,'nitro expires at 2.5 seconds')
        report['simulation'][id]={'distance_ratio_at_1_second':ratio,'duration_seconds':2.5,'cooldown_seconds':7}
    elif id=='shield':
        check(d[0]['lanes'][1]['shield_hp']==30,'shield begins at 30 HP')
        delta=max(r['lanes'][1]['hp']-r['lanes'][0]['hp'] for r in d)
        check(abs(delta-30)<.01,'shield absorbs exactly 30 projectile damage')
        report['simulation'][id]={'shield_capacity':30,'maximum_hull_health_saved':delta}
    elif id=='double_shot':
        damage=[10000-d[-1]['lanes'][i]['target_hp'] for i in [0,1]]
        check(damage[0]>0 and abs(damage[1]/damage[0]-1.2)<.01,'double shot deals 120% total damage')
        check(d[-1]['lanes'][0]['shots']==d[-1]['lanes'][1]['shots'],'double shot uses same number of volleys')
        report['simulation'][id]={'damage':damage,'ratio':damage[1]/damage[0]}
for index,id in enumerate(IDS,start_index):
    for lang in LANGS:
        target=out/lang/f'{index:02}_{id}.{lang}.mp4'
        meta=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(target)]))
        video=next(s for s in meta['streams'] if s['codec_type']=='video')
        check((video['width'],video['height'])==(1080,1920),str(target)+': portrait 1080p')
        check(video['codec_name']=='h264' and video['pix_fmt']=='yuv420p',str(target)+': compatible codec')
        check(video['r_frame_rate']=='30/1',str(target)+': 30 fps')
        check(abs(float(meta['format']['duration'])-15)<.1,str(target)+': 15 seconds')
        check(any(s['codec_type']=='audio' and s['codec_name']=='aac' for s in meta['streams']),str(target)+': AAC sound')
        subs=out/'subtitles'/f'{index:02}_{id}.{lang}.srt'
        text=subs.read_text(encoding='utf-8')
        check(text.count('-->')==4,str(subs)+': four timed cues')
        check('{' not in text and '}' not in text,str(subs)+': no unresolved templates')
        subprocess.run(['ffmpeg','-v','error','-i',str(target),'-f','null','-'],check=True)
        report['videos'].append({'path':str(target.relative_to(out)),'bytes':target.stat().st_size,'duration':float(meta['format']['duration'])})
for index,id in (enumerate(IDS,start_index) if a.batch=='first' else []):
    path=out/'masters'/f'{index:02}_{id}.multisub.mp4'
    meta=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(path)]))
    langs={s.get('tags',{}).get('language') for s in meta['streams'] if s['codec_type']=='subtitle'}
    check(langs=={'eng','fra','spa','rus'},str(path)+': four subtitle languages')
(out/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'videos':len(report['videos']),'simulation':report['simulation'],'errors':report['errors']},ensure_ascii=False,indent=2))
raise SystemExit(1 if report['errors'] else 0)
