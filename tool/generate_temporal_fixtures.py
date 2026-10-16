"""Generate silent synthetic temporal fixtures. Requires ffmpeg on PATH."""
import base64
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
fixtures = root / 'test/fixtures'
raw = root / '.dart_tool/temporal/frames.rgb'
raw.parent.mkdir(parents=True, exist_ok=True)
raw.write_bytes(b''.join(bytes(rgb) * (64 * 48)
                        for rgb in [(255, 0, 0), (255, 0, 0), (0, 0, 255), (0, 0, 255)]))


def ffmpeg(*arguments):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *arguments], check=True)


for name, rate in [('low_rate', '1/2'), ('long_gop', '10')]:
    ffmpeg('-f', 'lavfi', '-i', f'color=c=red:s=64x48:r={rate}:d=2',
           '-f', 'lavfi', '-i', f'color=c=blue:s=64x48:r={rate}:d=2',
           '-filter_complex', '[0:v][1:v]concat=n=2:v=1:a=0[v]', '-map', '[v]',
           '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-g', '100',
           '-keyint_min', '100', '-sc_threshold', '0', '-movflags', '+faststart',
           str(fixtures / f'{name}.mp4'))

ffmpeg('-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', '64x48',
       '-framerate', '4', '-i', str(raw), '-vf',
       "settb=1/1000,setpts='if(eq(N,0),0,if(eq(N,1),250,if(eq(N,2),2500,3750)))'",
       '-fps_mode', 'vfr', '-enc_time_base', '1/1000', '-c:v', 'libx264',
       '-pix_fmt', 'yuv420p', '-bf', '0', '-g', '100', '-sc_threshold', '0',
       '-video_track_timescale', '1000', '-movflags', '+faststart',
       str(fixtures / 'variable_rate.mp4'))

text = '// Synthetic temporal fixtures. See README.md.\n'
for name, file in [('variableRate', 'variable_rate'), ('lowRate', 'low_rate'), ('longGop', 'long_gop')]:
    encoded = base64.b64encode((fixtures / f'{file}.mp4').read_bytes()).decode()
    text += f"const {name}Base64 = '{encoded}';\n"
(fixtures / 'temporal_fixtures.dart').write_text(text, encoding='utf-8')
print('Temporal fixtures generated; format temporal_fixtures.dart with dart format.')
