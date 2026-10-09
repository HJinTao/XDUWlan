// 使用虚构输入，以 JavaScript 原生 UTF-16 与位运算生成离线协议向量。
const crypto = require('node:crypto');
const alphabet = 'LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA';
const standard = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function pack(s, length) {
  const words = [];
  for (let i = 0; i < s.length; i += 4) {
    words.push(s.charCodeAt(i) | s.charCodeAt(i + 1) << 8 |
      s.charCodeAt(i + 2) << 16 | s.charCodeAt(i + 3) << 24);
  }
  if (length) words.push(s.length);
  return words;
}
function xencode(message, key) {
  const v = pack(message, true), k = pack(key, false);
  while (k.length < 4) k.push(0);
  const n = v.length - 1;
  let z = v[n], y = v[0], sum = 0;
  for (let q = Math.floor(6 + 52 / (n + 1)); q > 0; q--) {
    sum = (sum + 0x9e3779b9) >>> 0;
    const e = sum >>> 2 & 3;
    for (let p = 0; p <= n; p++) {
      y = v[(p + 1) % v.length];
      let m = (z >>> 5 ^ y << 2) + (y >>> 3 ^ z << 4 ^ sum ^ y);
      m += k[p & 3 ^ e] ^ z;
      z = v[p] = (v[p] + m) >>> 0;
    }
  }
  const bytes = Buffer.alloc(v.length * 4);
  v.forEach((word, i) => bytes.writeUInt32LE(word >>> 0, i * 4));
  return bytes;
}
const vectors = [
  ['student@example.test', 'fictional-password'],
  ['fictional-学生', '虚构密码'],
  ['fictional-emoji', 'test-😀-pass'],
].map(([username, password]) => {
  const ip = '192.0.2.10', acid = '8', challenge = '0123456789abcdef0123456789abcdef';
  const hmd5 = crypto.createHmac('md5', challenge).update(password).digest('hex');
  const plain = JSON.stringify({username, password, ip, acid, enc_ver: 'srun_bx1'});
  const info = '{SRBX1}' + xencode(plain, challenge).toString('base64')
    .replace(/[A-Za-z0-9+/]/g, c => alphabet[standard.indexOf(c)]);
  const checksum = crypto.createHash('sha1').update(
    [username, hmd5, acid, ip, '200', '1', info].map(v => challenge + v).join('')).digest('hex');
  return {username, password, ip, acid, challenge, hmd5, info, checksum};
});
process.stdout.write(JSON.stringify(vectors, null, 2) + '\n');
