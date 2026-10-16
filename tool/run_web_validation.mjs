// Serve a previously built probe and run an isolated browser with a temp profile.
import http from 'node:http';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, extname } from 'node:path';
import { spawn } from 'node:child_process';
const browser = process.argv[2];
const paths = { firefox:'C:/Program Files/Mozilla Firefox/firefox.exe', chrome:'C:/Program Files/Google/Chrome/Application/chrome.exe', edge:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe' };
if (!paths[browser]) throw new Error('Choose firefox, chrome or edge');
const root=resolve(process.argv[4] ?? 'example/build/web');
const profile=mkdtempSync(join(tmpdir(),'lux-web-validation-'));
let finish;
const completed=new Promise(r=>finish=r);
const server=http.createServer((req,res)=>{
  if(req.url==='/report' && req.method==='POST') {
    let body='';req.on('data',b=>body+=b);req.on('end',()=>{res.end('ok');finish(JSON.parse(body));});return;
  }
  const path=resolve(root,'.'+new URL(req.url,'http://localhost').pathname.replace(/\/$/,'/index.html'));
  if(!path.startsWith(root+'/') && !path.startsWith(root+'\\')){res.writeHead(403);res.end();return;}
  try {const bytes=readFileSync(path);res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.wasm':'application/wasm','.json':'application/json'})[extname(path)]??'application/octet-stream');res.end(bytes);}
  catch {res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(18763,'127.0.0.1',r));
const expectedWasm = process.argv[3];
if (!['true','false'].includes(expectedWasm)) throw new Error('Pass expected Wasm runtime: true or false');
const url=`http://127.0.0.1:18763/?wasm=${expectedWasm}`;
const args=browser==='firefox'?['-headless','-no-remote','-profile',profile,url]:['--headless','--no-first-run','--no-default-browser-check',`--user-data-dir=${profile}`,url];
const child=spawn(paths[browser],args,{windowsHide:true,stdio:'ignore'});
let timer;
try {
  const result=await Promise.race([completed,new Promise((_,reject)=>timer=setTimeout(()=>reject(new Error('Browser report timed out')),90000))]);
  console.log(JSON.stringify(result,null,2));
  process.exitCode=Object.values(result.results).every(r=>r==='passed')?0:1;
} finally {
  clearTimeout(timer);
  if(process.platform==='win32') await new Promise(r=>{const killer=spawn('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});killer.on('close',r);});
  else child.kill();
  server.closeAllConnections();server.close();
  // mkdtemp created this directory; verify the resolved target before cleanup.
  if (!resolve(profile).startsWith(resolve(tmpdir(), 'lux-web-validation-'))) throw new Error('Unsafe profile cleanup path');
  try {rmSync(profile,{recursive:true,force:true});}catch{/* browser may still release locks */}
}
