import {chromium} from "playwright-core";
import assert from "node:assert/strict";
const base=process.env.SMOKE_BASE_URL||"http://127.0.0.1:3000";
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||"/usr/bin/chromium",headless:true});
try{
 for(const width of [1440,390]){
  const page=await browser.newPage({viewport:{width,height:900}});
  const errors=[];page.on("pageerror",e=>errors.push(e.message));
  await page.goto(base);await page.getByRole("heading",{name:/Seu negócio/}).waitFor();
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true,"Sem overflow horizontal");
  if(process.env.SMOKE_SCREENSHOT_DIR)await page.screenshot({path:process.env.SMOKE_SCREENSHOT_DIR+"/landing-"+width+".png",fullPage:true});
  await page.getByRole("link",{name:"Entrar",exact:true}).click();
  await page.getByRole("heading",{name:"Bem-vindo de volta."}).waitFor();
  await page.getByRole("link",{name:"Cadastre-se"}).click();
  await page.getByRole("heading",{name:"Comece agora."}).waitFor();
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);
  assert.deepEqual(errors,[]);
  await page.close();
 }
 const response=await fetch(base+"/api/pedidos",{method:"POST",headers:{"Content-Type":"application/json"},body:"{}"});
 assert.equal(response.status,400,"Checkout inválido é rejeitado sem banco");
 const protectedPage=await fetch(base+"/painel",{redirect:"manual"});
 assert.ok([302,303,307,308].includes(protectedPage.status));
 console.log("Smoke: desktop, mobile, navegação, proteção do painel e validação HTTP passaram.");
}finally{await browser.close()}
