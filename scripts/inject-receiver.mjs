import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '../..');
const src = path.join(repoRoot, 'dist-standalone', 'decimen-receiver.html');
const dstDir = path.join(repoRoot, 'ohos', 'entry', 'src', 'main', 'resources', 'rawfile');
fs.mkdirSync(dstDir, { recursive: true });

let html = fs.readFileSync(src, 'utf8');

const bridge = `
<script>
(function () {
  var host = window.decimenHost;
  if (!host) return;
  function bytesToBase64Chunks(bytes) {
    var CHUNK = 1024 * 1024;
    var out = [];
    for (var i = 0; i < bytes.length; i += CHUNK) {
      var end = Math.min(i + CHUNK, bytes.length);
      var bin = '';
      for (var j = i; j < end; j++) bin += String.fromCharCode(bytes[j]);
      out.push(btoa(bin));
    }
    return out;
  }
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[download]') : null;
    if (!a) return;
    e.preventDefault();
    var name = a.getAttribute('download') || 'file';
    fetch(a.href).then(function (r) { return r.arrayBuffer(); }).then(function (buf) {
      var chunks = bytesToBase64Chunks(new Uint8Array(buf));
      host.beginSave(name);
      for (var i = 0; i < chunks.length; i++) host.appendChunk(chunks[i]);
      host.endSave();
    }).catch(function (err) { console.error('save bridge', err); });
  }, true);
  if (!navigator.clipboard) navigator.clipboard = {};
  navigator.clipboard.writeText = function (text) {
    try { host.copyText(String(text)); } catch (err) { console.error('copy bridge', err); }
    return Promise.resolve();
  };
})();
</script>
`;

if (html.indexOf('</body>') === -1) {
  console.error('inject-receiver: no </body> found');
  process.exit(1);
}
html = html.replace('</body>', bridge + '\n</body>');
const dst = path.join(dstDir, 'decimen-receiver.html');
fs.writeFileSync(dst, html, 'utf8');
console.log('injected save-bridge ->', dst, html.length, 'bytes');
