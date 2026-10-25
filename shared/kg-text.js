/**
 * kg-text.js —— 教材文本 → 章节 / 关键词 / 共现短语（P2-8 第二个下沉边界）
 * ===========================================================
 * 从单文件 index.html 抽出的纯文本处理簇：分词、TextRank、PMI、依赖句式、
 * 标题有效性过滤、兜底分章、大纲抽取与加权术语。不依赖 DOM 与页面状态，
 * 浏览器与 Node 双端可用（Node 侧由 scripts/kg_text_runner.js 跑黄金用例）。
 *
 * 使用方式：
 *   浏览器：window.APKGText（由 scripts/gen_frontend_regions.py 内联进页面生成区）
 *   Node  ：require("./shared/kg-text.js")
 */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APKGText = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

function tokenize(text){return (String(text).match(/[一-鿿]{2,8}|[A-Za-z][A-Za-z0-9_\.]{1,20}/g)||[]).filter(function(t){return t.length>=2;});}
/* ── textRank：稀疏邻接表 ──────────────────────────────────────────────────────
   修复：原实现用稠密 n×n 矩阵（n=30433 时需 n²×8 B ≈ 7.41 GB）＋每行一个 Float64Array，
   教材级文本在浏览器里必然 OOM / 永不完成。改为 Map 邻接表累积 → CSR（Int32 列 + Float64 权重），
   内存 O(非零边)。迭代公式与原稠密实现等价：
     rank[i]=(1-d)/n + d·Σ_j (w[j][i]/rowSum[j])·rank[j]                      */
function textRank(tokens,window,iterations,damping){
  window=window||5;iterations=iterations||12;damping=damping||0.85;
  const vocab=[];const seen={};
  for(let i=0;i<tokens.length;i++){if(!seen[tokens[i]]){seen[tokens[i]]=1;vocab.push(tokens[i]);}}
  if(!vocab.length)return {};
  const idx=Object.create(null);for(let i=0;i<vocab.length;i++)idx[vocab[i]]=i;
  const n=vocab.length;
  const adj=new Array(n);for(let i=0;i<n;i++)adj[i]=null;   // 仅存非零边
  const link=function(a,b,v){var m=adj[a];if(!m){m=new Map();adj[a]=m;}var o=m.get(b);m.set(b,o===undefined?v:o+v);};
  for(let i=0;i<tokens.length;i++){
    const a=idx[tokens[i]];
    for(let j=i+1;j<Math.min(tokens.length,i+window);j++){
      const b=idx[tokens[j]];const v=1/(j-i);link(a,b,v);link(b,a,v);
    }
  }
  const rowPtr=new Int32Array(n+1);
  let edges=0;for(let i=0;i<n;i++){const m=adj[i];if(m)edges+=m.size;}
  const col=new Int32Array(edges),wt=new Float64Array(edges);
  let k=0;
  for(let i=0;i<n;i++){
    rowPtr[i]=k;const m=adj[i];
    if(m){m.forEach(function(v,b){col[k]=b;wt[k]=v;k++;});}
    adj[i]=null;                                            // 逐行释放，压低峰值
  }
  rowPtr[n]=k;
  const rowSum=new Float64Array(n);
  for(let i=0;i<n;i++){let s=0;for(let t=rowPtr[i];t<rowPtr[i+1];t++)s+=wt[t];rowSum[i]=s;}
  const next=new Float64Array(n);let rank=new Float64Array(n);
  for(let i=0;i<n;i++)rank[i]=1/n;
  const base=(1-damping)/n;
  for(let it=0;it<iterations;it++){
    next.fill(0);
    for(let j=0;j<n;j++){
      const rs=rowSum[j];if(rs<=0)continue;
      const push=damping*rank[j]/rs;
      for(let t=rowPtr[j];t<rowPtr[j+1];t++)next[col[t]]+=wt[t]*push;
    }
    for(let i=0;i<n;i++)rank[i]=next[i]+base;
  }
  const out={};for(let i=0;i<n;i++)out[vocab[i]]=rank[i];return {out:out,stats:{n:n,edges:edges}};
}
function pmi(co,a,b,total){if(co<=0||a<=0||b<=0||total<=0)return 0;return Math.max(0,Math.log2((co*total)/(a*b)));}
function dependencyEdges(text,concepts){
  const out=[];
  for(let ci=0;ci<concepts.length;ci++){
    const c=concepts[ci];
    try{
      const re=new RegExp("(?:基于|先学|掌握|了解|学会)\\s*"+c.replace(/[.*+?^${}()|[\]\\]/g,"\\$&")+"\\s*(?:后|之后|再|然后|才能|才能理解|的基础上)\\s*([一-鿿A-Za-z0-9_·、]{2,12})","g");
      let m;
      while((m=re.exec(text))){
        const target=m[1].trim();
        let hit=null;
        for(let k=0;k<concepts.length;k++){
          if(target.indexOf(concepts[k])>=0||concepts[k].indexOf(target)>=0){hit=concepts[k];break;}
        }
        if(hit&&hit!==c)out.push([c,hit]);
      }
    }catch(e){}
  }
  return out;
}
/* ════════════════════════════════════════════════════════════════════════════
参考算法整合 v3（来源：github.com/-Knowledge-Debt-Astral-Path
      tools/kg_algorithm.py + tools/kg_builder.py + contracts/golden json）
   A. 图谱升级：extractOutlineV2（章节层级增强：第N篇/部分/阶段/讲/步骤#N/
      Part/Unit/Lesson/Stage#N/N.N.N 小节码 + 中文数字映射 + 停用词过滤）
      · extractTermsWeighted（频率 × 靠前章节加权 × 领域词典加成）
      · removeCyclesTopo（DAG 投影 + Kahn 拓扑删环）
      · toTriples / toPropertyGraph / toMindmapTree / toMarkdownOutline（四态导出）
   B. 智能体合约：goldenScore（掌握度公式）· checkPlanK（K1 日预算/K3 why 含 from_kp）
      · saleNeed（销账缺口）· narrativeExplain（叙事化脱敏 + slot 填充）
   ════════════════════════════════════════════════════════════════════════════ */
var KG_CN_NUM={"一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9,"十":10,"百":100,"千":1000};
var KG_DICT={"人工智能":3,"机器学习":3,"深度学习":3,"神经网络":3,"Transformer":3,"大模型":3,"LLM":3,"Agent":3,"RAG":3,"注意力":2,"反向传播":2,"梯度下降":2,"算法":2,"数据结构":2,"递归":2,"动态规划":3,"微服务":3,"分布式":3,"并发":2,"数据库":2,"范式":2,"索引":2,"事务":2,"视图":2,"触发器":2,"存储过程":2,"API":2,"接口":1,"面向对象":1,"继承":1,"多态":2,"变量":1,"函数":1,"循环":1,"数组":1,"链表":2,"排序":2,"查找":2,"哈希":2,"二叉树":2,"栈":1,"队列":1,"会计":1,"资产":2,"负债":2,"权益":2,"复式记账":2,"借贷":2,"凭证":2,"账簿":2,"试算平衡":2,"报表":2,"编译":2,"操作系统":2,"网络":1,"协议":2,"加密":2,"缓存":2,"正则":2,"异常处理":2};
var KG_STOP={"www":1,"http":1,"https":1,"cn":1,"com":1,"org":1,"net":1,"pdf":1,"isbn":1,"copyright":1,"版权所有":1,"仅供":1,"内部资料":1,"目录":1,"前言":1,"索引":1,"参考文献":1,"习题":1,"思考题":1,"小结":1,"本章":1,"如图":1,"式中":1,"综上":1,"显然":1,"因此":1,"从而":1,"可知":1,"得到":1,"进行":1,"通过":1,"对于":1,"可以":1,"需要":1,"使用":1,"其中":1,"并且":1,"或者":1,"如果":1,"同时":1,"分别":1,"以上":1,"以下":1,"上述":1,"目前":1,"方法":1,"问题":1,"实现":1,"计算":1,"作用":1,"说明":1,"定义":1,"定义式":1};
/* ── P0-1：概念/标题有效性过滤（拦截英文断词碎片、数字串、括号残片、单字碎片）── */
var KG_STOP_EN={"the":1,"and":1,"for":1,"with":1,"this":1,"that":1,"from":1,"under":1,"when":1,"then":1,"than":1,"into":1,"onto":1,"over":1,"about":1,"above":1,"are":1,"was":1,"were":1,"been":1,"have":1,"has":1,"had":1,"will":1,"would":1,"can":1,"could":1,"should":1,"shall":1,"may":1,"might":1,"must":1,"not":1,"but":1,"all":1,"any":1,"each":1,"its":1,"his":1,"her":1,"our":1,"your":1,"their":1,"one":1,"two":1,"new":1,"use":1,"using":1,"used":1,"also":1,"more":1,"most":1,"some":1,"such":1,"only":1,"other":1,"which":1,"what":1,"who":1,"how":1,"why":1,"you":1};
function kgValidTitle(t){
  let s=String(t||"").trim();
  s=s.replace(/^[\(\[（【「『"'“‘<《\)\]）】」』"”’>》,，、;；.。!！?？\s\-–—*·]+/,"");
  s=s.replace(/[\)\]）】」』"”’>》\s]+$/,"").trim();
  if(!s)return "";
  if(/[0-9]{4,}/.test(s))return "";                       // 长数字串（页码/ISBN/浮点噪声）
  if(!/[一-鿿A-Za-z]/.test(s))return "";                   // 必须含文字
  const cn=(s.match(/[一-鿿]/g)||[]).length;
  if(cn>0){
    if(cn<2||!/[一-鿿]{2}/.test(s))return "";              // 中文候选至少 2 个汉字
  }else{
    if(KG_STOP_EN[s.toLowerCase()])return "";              // 英文功能词碎片（under/when…）
    if(!/[A-Za-z]{3,}/.test(s)&&!/^[A-Z]{2,5}$/.test(s)&&!KG_DICT[s])return ""; // 纯英文需 ≥3 字母词/全大写缩写/领域词
  }
  return s.slice(0,46);
}
/* ── P0-2：兜底分章——空行分段失效时按句子聚合切块，保证今日任务/练习有素材 ── */
function kgChunkChapters(text,maxCh){
  maxCh=maxCh||60;
  const s=String(text).replace(/\r/g,"");
  let units=s.split(/\n{2,}/).map(function(x){return x.trim();}).filter(function(x){return x.length>=20;});
  if(units.length<2){
    units=[];
    const parts=s.split(/([。！？!?；;])/);
    let buf="";
    for(let i=0;i<parts.length;i+=2){
      buf+=parts[i]+(parts[i+1]||"");
      if(buf.length>=600){units.push(buf.trim());buf="";}
    }
    if(buf.trim().length>=40)units.push(buf.trim());
  }
  if(units.length<2)return [{id:"C01",title:(s.replace(/\s+/g,"").slice(0,16)||"正文"),body:s,order:0,level:1}];
  const out=[];
  for(let i=0;i<units.length&&out.length<maxCh;i++){
    const first=units[i].split("\n")[0].trim();
    const ttl=kgValidTitle(first.length<=30?first:units[i].replace(/\s+/g,"").slice(0,16))||("第"+(i+1)+"部分");
    out.push({id:"C"+String(i+1).padStart(2,"0"),title:ttl.slice(0,40),body:units[i],order:i,level:1});
  }
  return out;
}

function kgCn2Num(s){
  if(s==null)return 0;
  const t=String(s).trim();
  if(/^\d+$/.test(t))return parseInt(t,10)||0;
  if(!/^[一二三四五六七八九十百千]+$/.test(t))return 0;
  let n=0,r=0;
  for(let i=0;i<t.length;i++){
    const c=KG_CN_NUM[t.charAt(i)]||0;
    if(c>=100){n+=(r||1)*c;r=0;}else r+=c;
  }
  return n+r;
}
function extractOutlineV2(text,maxCh,tocMode){
  maxCh=maxCh||60;
  // tocMode="page"：页式 OCR 目录页专用扫描（第X章 / 数字 / 一、二、目录行窗口切章）
  if(tocMode==="page"){
    const P=String(text).split("\n"),TM=[];
    for(let i=0;i<P.length&&i<150;i++){
      const ln=P[i].trim();if(!ln)continue;
      if(ln.length>60){
        // 长行：目录标题与正文同行（如"第3章 CPU与总线 CPU通过总线…"），按行内章节标记提取纯净标题
        const rm=/^(第\s*[0-9一二三四五六七八九十百千]+\s*[章节篇讲])[\s:：·.、-]*([^\s。；：:，,、]{2,40})/.exec(ln);
        if(rm){const _rt=kgValidTitle(rm[2]);if(_rt)TM.push({i:i,title:_rt.slice(0,40),level:1,ord:parseInt(rm[1].replace(/[^\d]/g,""),10)||TM.length+1});} // P0-1
        continue;
      }
      const m=/^(第\s*[0-9一二三四五六七八九十百千]+\s*[章节篇讲])\s*[:：·.、\- ]*([^\s。；：:，,、]{2,40})/.exec(ln)
        ||/^(\d+(?:\.\d+)+)\s+([^\s].{1,40})$/.exec(ln)
        ||/^(\d{1,3})[、.．]\s*(.{2,40})$/.exec(ln);
      if(!m)continue;
      const t=kgValidTitle(m[2]); // P0-1
      if(!t)continue;
      if(KG_STOP[t.toLowerCase()])continue;
      TM.push({i:i,title:t.slice(0,40),level:m[1].indexOf("第")===0?1:2,ord:parseInt(m[1].replace(/[^\d]/g,""),10)||TM.length+1});
    }
    if(TM.length>=3){
      const U=[];for(let k=0;k<TM.length;k++){if(!U.length||U[U.length-1].title!==TM[k].title)U.push(TM[k]);}
      const OC=[];
      for(let k2=0;k2<U.length;k2++){
        const a=U[k2].i,b=(k2+1<U.length)?U[k2+1].i:Math.min(P.length,a+50);
        OC.push({id:"C"+String(k2+1).padStart(2,"0"),title:U[k2].title,body:P.slice(a,b).join("\n").trim(),order:k2,level:U[k2].level});
      }
      return OC.slice(0,maxCh);
    }
  }
  const lines=String(text).split("\n"),marks=[];
  // OCR 长行目录探测：页式/扫描 OCR 常把整页打成一行（无换行标记），若全文几乎无换行
  // 且命中 >=3 个"第X章/1.1 小节/一、二、三、"(行内)标题，直接按标题切章建骨架，
  // 让知识图谱能直接读取 OCR 读出的书籍目录，而不是退回"段落 N"。
  if(!lines.some(function(l){return l.length<=60&&(/^(第\s*[0-9一二三四五六七八九十百千]+\s*[章节篇讲])/.test(l.trim())||/^(\d+(?:\.\d+)+)\s+[^\s]/.test(l.trim())||/^([一二三四五六七八九十]+)、/.test(l.trim()));})){
    const full=String(text).replace(/\r/g,"");
    const inner=[];
    const reInner=/(?:第\s*[0-9一二三四五六七八九十百千]+\s*[章节篇讲][\s:：·.、-]*|(?:\d{1,2}(?:\.\d+)+)\s+|(?:[一二三四五六七八九十]+)、)([^\s。；：:，,、]{2,40})/g;
    let mm;
    while((mm=reInner.exec(full))){inner.push({i:mm.index,title:mm[1].replace(/\s+/g," ").trim()});}
    if(inner.length>=3){
      const U=[];const seenT={};
      for(let k=0;k<inner.length;k++){
        const t=kgValidTitle(inner[k].title); // P0-1
        if(!t||KG_STOP[t.toLowerCase()])continue;
        if(seenT[t])continue;seenT[t]=1;
        inner[k].title=t;
        U.push(inner[k]);
      }
      if(U.length>=3){
        const OC=[];
        for(let k2=0;k2<U.length&&k2<maxCh;k2++){
          const a=U[k2].i;
          const b=(k2+1<U.length)?U[k2+1].i:full.length;
          const seg=full.slice(a,b).replace(/[。；：:！？\n]+/g,"\n").trim();
          OC.push({id:"C"+String(k2+1).padStart(2,"0"),title:U[k2].title.slice(0,40),body:seg.slice(0,600),order:k2,level:1});
        }
        if(OC.length>=3)return OC;
      }
    }
  }
  function add(i,title,level,ord){
    title=String(title||"").replace(/\s+/g," ").trim();
    const _vt=kgValidTitle(title);if(!_vt)return; // P0-1
    title=_vt;
    if(title.length<2||title.length>46)return;
    if(/^[=\-–—_*]{2,}$/.test(title))return;
    if(KG_STOP[title.toLowerCase()])return;
    marks.push({i:i,title:title.slice(0,46),level:level,ord:ord});
  }
  for(let i=0;i<lines.length;i++){
    const ln=lines[i].trim();if(!ln||ln.length>60)continue;
    const md=/^#{1,3}\s+(.+)$/.exec(ln);
    if(md){add(i,md[1].trim(),md[0].indexOf("###")===0?3:(md[0].indexOf("##")===0?2:1),0);continue;}
    const ch=/^(第\s*[0-9一二三四五六七八九十百千]+\s*[章节篇讲])[\s:：·.、-]*(.*)$/.exec(ln);
    if(ch){const ord=parseInt(ch[1].replace(/[^\d]/g,""),10)||kgCn2Num(ch[1].replace(/第/,"").replace(/[章节篇讲\s]/g,""));add(i,(ch[2]||ch[1]).trim(),1,ord);continue;}
    const st=/^(步骤)\s*#?\s*(\d+)[\s:：·.、-]*(.*)$/.exec(ln);
    if(st){add(i,(st[3]||(st[1]+" "+st[2])).trim(),2,parseInt(st[2],10));continue;}
    const en1=/^(Chapter)\s+(\d+)[\s:：.\-]*(.*)$/i.exec(ln);
    if(en1){add(i,(en1[3]||("Chapter "+en1[2])).trim(),1,parseInt(en1[2],10));continue;}
    const en=/^(Part|Unit|Lesson|Stage)\s+(\d+)[\s:：.\-]*(.*)$/i.exec(ln);
    if(en){add(i,(en[3]||(en[1]+" "+en[2])).trim(),/(^|i)chapter$/i.test(en[1])?1:2,parseInt(en[2],10));continue;}
    const num=/^(\d+(?:\.\d+)+)\s+([^\s].{1,40})$/.exec(ln);
    if(num){add(i,num[2].trim(),num[1].split(".").length,num[1]);continue;}
    const cn=/^([一二三四五六七八九十]+)、\s*(.+)$/.exec(ln);
    if(cn){add(i,cn[2].trim(),1,kgCn2Num(cn[1]));continue;}
    const sub=/^(\d+)[\.、．]\s*(.+)$/.exec(ln);
    if(sub&&!marks.length){add(i,sub[2].trim(),1,parseInt(sub[1],10));}
  }
  const uniq=[];const uniMap={};
  for(let k=0;k<marks.length;k++){
    const m=marks[k];
    if(!(m.title in uniMap)){uniMap[m.title]=uniq.length;uniq.push(m);}
    else if(m.i>uniq[uniMap[m.title]].i){uniq[uniMap[m.title]]=m;}
  }
  if(uniq.length<2){
    return kgChunkChapters(String(text),maxCh); // P0-2：句子聚合兜底分章（此前整本书塌成 1 章）
  }
  const chs=[];
  for(let k2=0;k2<uniq.length;k2++){
    const a=uniq[k2].i,b=(k2+1<uniq.length)?uniq[k2+1].i:lines.length;
    chs.push({id:"C"+String(k2+1).padStart(2,"0"),title:uniq[k2].title,body:lines.slice(a,b).join("\n").trim(),order:k2,level:uniq[k2].level});
  }
  return chs.slice(0,maxCh);
}
function extractTermsWeighted(text,chapters,limit){
  limit=limit||20;
  const tokens=tokenize(text);
  const tr=textRank(tokens,5,12,0.85).out;
  let total=0;for(const k in tr)total+=tr[k];total=Math.max(total,1e-9);
  const sc={};
  for(const k2 in tr){
    const t2=k2;
    if(!kgValidTitle(t2))continue; // P0-1：碎片术语拦截
    if(t2.length<2||KG_STOP[t2.toLowerCase()])continue;
    if(/^[A-Z\s]+$/.test(t2)&&t2.length>4)continue;   // 纯大写噪声
    if(/^第[0-9一二三四五六七八九十百千]+[章节篇讲回]$/.test(t2))continue; // 目录行噪声（第X章）
    if(/\.{2,}/.test(t2))continue;                    // 连续点号
    const rank=(tr[t2]||0)/total;
    let pos=1;
    for(let i=0;i<chapters.length;i++){
      if(String(chapters[i].body||"").indexOf(t2)>=0){pos=1+(i/chapters.length)*0.8;break;}
    }
    const dict=KG_DICT[t2]||0;
    sc[t2]=rank*(1+pos*0.5)*(1+dict);
  }
  const all=Object.keys(sc).sort(function(a,b){return sc[b]-sc[a];});
  const out=[];
  for(let j=0;j<all.length&&out.length<limit;j++){
    const t3=all[j];
    let inTitle=false;
    for(let k3=0;k3<chapters.length;k3++){if(chapters[k3].title.indexOf(t3)>=0&&t3.length<=chapters[k3].title.length){inTitle=true;break;}}
    if(inTitle)continue;
    let first=-1;
    for(let k4=0;k4<chapters.length;k4++){
      if(String(chapters[k4].body||"").indexOf(t3)>=0||String(chapters[k4].title).indexOf(t3)>=0){first=k4;break;}
    }
    out.push({t:t3,rank:sc[t3],ch:first<0?0:first});
  }
  return out;
}

  return {
    tokenize: tokenize,
    textRank: textRank,
    pmi: pmi,
    dependencyEdges: dependencyEdges,
    kgValidTitle: kgValidTitle,
    kgChunkChapters: kgChunkChapters,
    kgCn2Num: kgCn2Num,
    extractOutlineV2: extractOutlineV2,
    extractTermsWeighted: extractTermsWeighted
  };
});
