#!/usr/bin/env node
// Inspect only the isolated test browser through its loopback SSH tunnel.
import {writeFile} from 'node:fs/promises';

const endpoint = process.env.SNOWIUM_CDP_ENDPOINT || 'http://127.0.0.1:19225';
let pages;
for (let attempt = 0; attempt < 45; ++attempt) {
  try { pages = await (await fetch(endpoint + '/json/list')).json(); break; }
  catch (error) {
    if (attempt === 44) throw error;
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
}
const page = pages.find(p => p.type === 'page');
if (!page) throw new Error('No test page available');
const socketURL = new URL(page.webSocketDebuggerUrl);
socketURL.host = new URL(endpoint).host;
const ws = new WebSocket(socketURL);
await new Promise((resolve, reject) => {
  ws.addEventListener('open', resolve, {once: true});
  ws.addEventListener('error', reject, {once: true});
});
let sequence = 0;
let crashed = false;
const pending = new Map();
ws.addEventListener('message', event => {
  const message = JSON.parse(event.data);
  if (message.method === 'Inspector.targetCrashed') {
    crashed = true;
    process.exitCode = 1;
    console.log(JSON.stringify(message));
  }
  const request = pending.get(message.id);
  if (!request) return;
  pending.delete(message.id);
  clearTimeout(request.timer);
  if (message.error) request.reject(new Error(JSON.stringify(message.error)));
  else request.resolve(message.result);
});
function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(method + ' timeout'));
    }, 15000);
    pending.set(id, {resolve, reject, timer});
    ws.send(JSON.stringify({id, method, params}));
  });
}
try {
  await call('Page.enable');
  await call('Runtime.enable');
  console.log(JSON.stringify(await call('Page.navigate', {url: process.argv[2]})));
  let snapshot;
  for (let i = 0; i < Number(process.argv[3] || 30); ++i) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    if (crashed) throw new Error('Renderer crashed');
    const result = await call('Runtime.evaluate', {
      expression: `({url:location.href,title:document.title,ready:document.readyState,
        elements:document.querySelectorAll('*').length,regression:window.regression,
        text:document.body?.innerText.slice(0,180)})`,
      returnByValue: true
    });
    if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
    snapshot = result.result.value;
    console.log(JSON.stringify(snapshot));
    if (snapshot?.regression?.failures.length) throw new Error('Computed values differ');
  }
  if (!snapshot || snapshot.ready !== 'complete' || snapshot.elements < 5)
    throw new Error('Page did not finish loading');
  if (process.argv[2].endsWith('/style-custom-properties.html') &&
      !(snapshot.regression?.frames > 30)) throw new Error('Animation did not advance');
  if (process.argv[4]) {
    const screenshot = await call('Page.captureScreenshot', {format: 'png'});
    await writeFile(process.argv[4], Buffer.from(screenshot.data, 'base64'));
  }
} catch (error) {
  console.error(error);
  process.exitCode = 1;
} finally {
  ws.close();
}
