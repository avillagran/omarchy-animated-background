#!/usr/bin/env node
// Render an animated SVG to a looping mp4 using headless Chromium via CDP
// screencast. Usage: svg2mp4 <input.svg> <output.mp4> [duration_s]
// Also writes <output.mp4>.poster.jpg (first frame).

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const INPUT = path.resolve(process.argv[2]);
const OUTPUT = path.resolve(process.argv[3]);
const DURATION_MS = Math.max(1000, parseFloat(process.argv[4] || '4') * 1000);
const W = 1280, H = 720;

const CHROMIUM = process.env.CHROMIUM_BIN || '/usr/bin/chromium';

function fail(msg) { console.error(msg); process.exit(1); }

// Wrap the SVG so it fills the viewport and keeps animating in <img>.
const wrapperPath = OUTPUT + '.wrapper.html';
fs.writeFileSync(wrapperPath, `<!doctype html><html><body style="margin:0;overflow:hidden;background:#000">
<img src="file://${INPUT}" style="width:100vw;height:100vh;object-fit:cover"/>
</body></html>`);

const ffmpeg = spawn('ffmpeg', [
  '-y', '-f', 'image2pipe', '-framerate', '30', '-i', '-',
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
  '-vf', `scale=trunc(iw/2)*2:trunc(ih/2)*2`,
  '-movflags', '+faststart', OUTPUT
], { stdio: ['pipe', 'ignore', 'ignore'] });

let posterWritten = false;
let frameCount = 0;

function cleanup(code) {
  try { fs.unlinkSync(wrapperPath); } catch (e) {}
  process.exit(code);
}

const chrome = spawn(CHROMIUM, [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
  '--disable-dev-shm-usage', '--force-device-scale-factor=1',
  '--allow-file-access-from-files',
  `--window-size=${W},${H}`, '--remote-debugging-port=0', 'about:blank'
], { stdio: ['ignore', 'ignore', 'pipe'] });

let wsUrl = null;
let wsBuf = '';
chrome.stderr.on('data', (d) => {
  wsBuf += d.toString();
  const m = wsBuf.match(/DevTools listening on (ws:\/\/\S+)/);
  if (m && !wsUrl) { wsUrl = m[1]; main(); }
});

chrome.on('exit', () => { if (!wsUrl) fail('chromium exited before devtools url'); });

const killTimer = setTimeout(() => { console.error('timeout'); cleanup(1); }, DURATION_MS + 25000);

async function main() {
  try {
    const httpBase = 'http://' + wsUrl.slice('ws://'.length).split('/')[0];
    // Create a target on the wrapper page
    const res = await fetch(httpBase + '/json/new?' + encodeURIComponent('file://' + wrapperPath), { method: 'PUT' });
    const target = await res.json();
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    let id = 0;
    const pending = new Map();
    const send = (method, params = {}) => new Promise((resolve, reject) => {
      const mid = ++id;
      pending.set(mid, { resolve, reject });
      ws.send(JSON.stringify({ id: mid, method, params }));
    });

    await new Promise(r => { ws.onopen = r; });
    ws.onmessage = (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id && pending.has(msg.id)) {
        const p = pending.get(msg.id); pending.delete(msg.id);
        msg.error ? p.reject(new Error(JSON.stringify(msg.error))) : p.resolve(msg.result);
      } else if (msg.method === 'Page.screencastFrame') {
        const { data, sessionId } = msg.params;
        if (frameCount % 2 === 0) {
          const buf = Buffer.from(data, 'base64');
          ffmpeg.stdin.write(buf);
          if (!posterWritten) { fs.writeFileSync(OUTPUT + '.poster.jpg', buf); posterWritten = true; }
        }
        frameCount++;
        ws.send(JSON.stringify({ id: ++id, method: 'Page.screencastFrameAck', params: { sessionId } }));
      }
    };

    await send('Page.enable');
    await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
    await send('Page.startScreencast', { format: 'jpeg', quality: 82, everyNthFrame: 1 });

    setTimeout(async () => {
      try { await send('Page.stopScreencast'); } catch (e) {}
      try { ws.close(); } catch (e) {}
      chrome.kill('SIGKILL');
      ffmpeg.stdin.end();
      ffmpeg.on('exit', () => {
        clearTimeout(killTimer);
        if (fs.existsSync(OUTPUT) && frameCount > 10) { console.log(OUTPUT); cleanup(0); }
        console.error('no frames captured (got ' + frameCount + ')');
        cleanup(1);
      });
    }, DURATION_MS);
  } catch (e) {
    console.error(String(e));
    cleanup(1);
  }
}
