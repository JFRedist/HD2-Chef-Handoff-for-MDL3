// Renders promo/scenes.html (and promo/cover.html) with Playwright and encodes the video with ffmpeg.
//   node promo/render.js stills 3,14,40 [outdir]    PNG stills at those times (seconds), to check the layout
//   node promo/render.js video [out.mp4] [workers]  the whole video, 1920x1080, 30 fps, H.264 + a silent AAC track (4 workers by default)
//   node promo/render.js srt [out.srt]              the subtitles as an .srt
//   node promo/render.js cover [out.png]            the Bilibili cover, 1920x1200 (16:10)
//   node promo/render.js nexus [outdir]             the images for the Nexus Mods page (promo/nexus-images.html), 1920x1080 PNGs
// Needs node with playwright (and its chromium), ffmpeg, and a Chinese font (the layout uses WenQuanYi Zen Hei).
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

async function open(file, vp) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: vp });
  await page.goto('file://' + path.join(__dirname, file));
  await page.waitForFunction('window.READY === true');
  return { browser, page };
}
const ts = (s) => {
  const ms = Math.round(s * 1000), h = Math.floor(ms / 3600000), m = Math.floor(ms / 60000) % 60, sec = Math.floor(ms / 1000) % 60;
  const p = (n, w = 2) => String(n).padStart(w, '0');
  return `${p(h)}:${p(m)}:${p(sec)},${p(ms % 1000, 3)}`;
};

async function main() {
  const [cmd, a1, a2] = process.argv.slice(2);
  if (cmd === 'stills') {
    const dir = a2 || 'stills'; fs.mkdirSync(dir, { recursive: true });
    const { browser, page } = await open('scenes.html', { width: 1920, height: 1080 });
    for (const t of a1.split(',').map(Number)) {
      await page.evaluate((x) => window.setT(x), t);
      await page.screenshot({ path: path.join(dir, `t${String(t).padStart(5, '0')}.png`) });
    }
    await browser.close();
  } else if (cmd === 'srt') {
    const { browser, page } = await open('scenes.html', { width: 1920, height: 1080 });
    const cues = await page.evaluate(() => window.CUES);
    fs.writeFileSync(a1 || 'promo.srt', cues.map((c, i) => `${i + 1}\n${ts(c[0])} --> ${ts(c[1])}\n${c[2]}\n`).join('\n'));
    await browser.close();
  } else if (cmd === 'cover') {
    const { browser, page } = await open('cover.html', { width: 1920, height: 1200 });
    await page.screenshot({ path: a1 || 'cover.png' });
    await browser.close();
  } else if (cmd === 'nexus') {
    const dir = a1 || 'nexus'; fs.mkdirSync(dir, { recursive: true });
    const { browser, page } = await open('nexus-images.html', { width: 1920, height: 1080 });
    const n = await page.evaluate(() => window.COUNT);
    for (let i = 1; i <= n; i++) {
      const name = await page.evaluate((k) => window.show(k), i);
      await page.screenshot({ path: path.join(dir, name + '.png') });
      console.error('wrote', path.join(dir, name + '.png'));
    }
    await browser.close();
  } else if (cmd === 'chunk') {
    // internal: frames [from, to) of the video into a video-only mp4 (the `video` command runs several of these at once)
    const [out, from, to] = [a1, Number(a2), Number(process.argv[5])];
    const { browser, page } = await open('scenes.html', { width: 1920, height: 1080 });
    const fps = await page.evaluate(() => window.FPS);
    const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '16', '-pix_fmt', 'yuv420p', '-r', String(fps), '-g', '60', out],
      { stdio: ['pipe', 'inherit', 'inherit'] });
    for (let i = from; i < to; i++) {
      await page.evaluate((x) => window.setT(x), i / fps);
      const buf = await page.screenshot({ type: 'png' });
      if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
    }
    ff.stdin.end();
    await new Promise((r) => ff.on('close', r));
    await browser.close();
  } else if (cmd === 'video') {
    const out = path.resolve(a1 || 'promo.mp4');
    const workers = Number(a2 || 4);
    const probe = await open('scenes.html', { width: 1920, height: 1080 });
    const [fps, dur] = await probe.page.evaluate(() => [window.FPS, window.DURATION]);
    await probe.browser.close();
    const n = Math.round(fps * dur), per = Math.ceil(n / workers);
    const tmp = fs.mkdtempSync(path.join(path.dirname(out), '.promo-segments-'));
    const t0 = Date.now(), segs = [];
    await Promise.all(Array.from({ length: workers }, (_, k) => {
      const from = k * per, to = Math.min(n, from + per);
      if (from >= to) return Promise.resolve();
      const seg = path.join(tmp, `seg${k}.mp4`); segs.push(seg);
      return new Promise((resolve, reject) => {
        const c = spawn(process.execPath, [__filename, 'chunk', seg, String(from), String(to)], { stdio: 'inherit' });
        c.on('close', (code) => (code === 0 ? resolve() : reject(new Error(`chunk ${k} failed (${code})`))));
      }).then(() => console.error(`chunk ${k} done (frames ${from}-${to - 1}) after ${((Date.now() - t0) / 1000).toFixed(0)} s`));
    }));
    segs.sort();
    fs.writeFileSync(path.join(tmp, 'list.txt'), segs.map((s) => `file '${s}'`).join('\n') + '\n');
    await new Promise((resolve, reject) => {
      const c = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', path.join(tmp, 'list.txt'),
        '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo', '-shortest', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '96k',
        '-movflags', '+faststart', out], { stdio: 'inherit' });
      c.on('close', (code) => (code === 0 ? resolve() : reject(new Error('concat failed'))));
    });
    fs.rmSync(tmp, { recursive: true, force: true });
    console.error('done', out, ((Date.now() - t0) / 1000).toFixed(0) + ' s');
  } else {
    console.error(fs.readFileSync(__filename, 'utf8').split('\n').slice(0, 8).join('\n'));
    process.exit(2);
  }
}
main().catch((e) => { console.error(e); process.exit(1); });
