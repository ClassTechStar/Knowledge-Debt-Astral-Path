/**
 * exam.js —— 试卷作业错题的结构化与层级图谱（P2-8 首个下沉边界）
 * ===========================================================
 * 从单文件 index.html 抽出的一簇纯文本处理函数（OLE/zip 解包、XML/HTML 文本、
 * 题头与选项解析、结构化）。不依赖 DOM 与页面状态，浏览器与 Node 双端可用
 * （Node 侧由 scripts/exam_runner.js 跑黄金用例）。
 * 注：buildExamKG 依赖页面词库与教材状态，仍留在 index.html。
 */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APExam = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

function t10InflateRaw(bytes){
  return new Promise(function(resolve,reject){
    function attempt(mode){
      try{
        var st=new Blob([bytes]).stream().pipeThrough(new DecompressionStream(mode));
        new Response(st).arrayBuffer().then(function(ab){resolve(new Uint8Array(ab));},function(){reject(new Error("inflate-"+mode+"-failed"));});
      }catch(e){reject(e);}
    }
    if(typeof DecompressionStream==="undefined"){reject(new Error("浏览器不支持 DecompressionStream"));return;}
    attempt("deflate-raw");
  }).catch(function(){
    // 个别容器用 zlib 包装（带 2 字节头），raw 失败再试 deflate
    return new Promise(function(resolve,reject){
      try{
        var st=new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
        new Response(st).arrayBuffer().then(function(ab){resolve(new Uint8Array(ab));},reject);
      }catch(e){reject(e);}
    });
  });
}

function t10Decode(u8){
  if(!u8)return "";
  if(u8.length>=2&&u8[0]===0xFF&&u8[1]===0xFE){try{return new TextDecoder("utf-16le").decode(u8);}catch(e){}}
  try{return new TextDecoder("utf-8",{fatal:false}).decode(u8);}catch(e){return latin1(u8);}
}

function t10Ent(s){
  return String(s==null?"":s)
    .replace(/&#x([0-9a-fA-F]+);/g,function(_,h){try{return String.fromCodePoint(parseInt(h,16));}catch(e){return "";}})
    .replace(/&#(\d+);/g,function(_,d){try{return String.fromCodePoint(parseInt(d,10));}catch(e){return "";}})
    .replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&quot;/g,'"').replace(/&apos;/g,"'").replace(/&amp;/g,"&");
}

function t10XmlText(xml){
  var s=String(xml||"");
  s=s.replace(/<(?:w|a):p\b[^>]*\/>/g,"\n");
  s=s.replace(/<\/(?:w|a):p>/g,"\n");
  s=s.replace(/<(?:w|a):br\b[^>]*\/>/g,"\n");
  s=s.replace(/<w:tab\b[^>]*\/>/g,"\t");
  s=s.replace(/<[^>]+>/g,"");
  s=t10Ent(s);
  return s.replace(/[ \t\u00a0]+/g," ").replace(/ ?\n ?/g,"\n").replace(/\n{3,}/g,"\n\n").trim();
}

function t10HtmlText(html){
  var s=String(html||"");
  s=s.replace(/<!--[\s\S]*?-->/g,"");
  s=s.replace(/<script\b[\s\S]*?<\/script>/gi,"").replace(/<style\b[\s\S]*?<\/style>/gi,"");
  s=s.replace(/<\/(?:p|div|li|tr|h[1-6]|blockquote|section|article|figcaption)\s*>/gi,"\n");
  s=s.replace(/<br\s*\/?>/gi,"\n");
  s=s.replace(/<[^>]+>/g,"");
  s=t10Ent(s);
  return s.replace(/[ \t\u00a0]+/g," ").replace(/\n{3,}/g,"\n\n").trim();
}

var EXAM_MAX_ITEMS=300;

function t10PaperTypeLabel(t){return t==="hw"?"作业":(t==="wrong"?"错题":"试卷");}

function t10QTypeLabel(t){
  return t==="choice"?"选择题":(t==="blank"?"填空题":(t==="judge"?"判断题":(t==="solve"?"解答题":"题目")));
}

function t10ExamLines(text){
  return String(text||"").replace(/\r\n?/g,"\n").split("\n")
    .map(function(l){return l.replace(/^\s*\[(?:page|slide|image|media|备注)\s*\d+\]\s*/,"").replace(/\s+$/,"");})
    .filter(function(l){return l.trim().length>0;});
}

function t10SectionOf(line){
  const s=String(line||"").trim();
  if(!s||s.length>26)return null;
  if(/[?？。；，,]$/.test(s))return null;
  let m=/^第\s*[一二三四五六七八九十]+\s*[大部分大题篇]/.exec(s);
  if(m)return s;
  m=/^[（(][一二三四五六七八九十]+[）)]\s*\S/.exec(s);
  if(m)return s;
  m=/^[一二三四五六七八九十]+、\s*(.{1,22})$/.exec(s);
  if(m){
    const body=m[1];
    if(body.length<=10&&!/[?？]/.test(body))return s;
    if(/(选择|填空|判断|解答|计算|应用|证明|简答|论述|综述|分析|改错|写作|翻译|名词解释|案例|听力|阅读|综合|基础|拓展|题目|试题|部分)/.test(body))return s;
    return null;
  }
  if(/^(选择|填空|判断|解答|计算|应用|证明|简答|论述|综述|分析|改错|写作|翻译|名词解释|案例)题?$/.test(s))return s;
  return null;
}

function t10QuestionHead(line){
  const s=String(line||"").trim();
  let m=/^(\d{1,3})\s*[.、．)]\s*(\S.*)$/.exec(s);
  if(m)return {no:parseInt(m[1],10),rest:m[2].trim()};
  m=/^[（(](\d{1,3})[）)]\s*(\S.*)$/.exec(s);
  if(m)return {no:parseInt(m[1],10),rest:m[2].trim()};
  m=/^第\s*(\d{1,3})\s*题\s*[:：]?\s*(.*)$/.exec(s);
  if(m)return {no:parseInt(m[1],10),rest:(m[2]||"").trim()};
  return null;
}

function t10AnswerOf(line){
  const s=String(line||"").trim();
  const m=/^(?:【\s*答案\s*】|参考答案|答案|答)\s*[:：]?\s*(\S.*)$/.exec(s);
  if(!m)return [];
  const body=m[1].trim();
  const multi=body.match(/\d{1,3}\s*[.、．)]\s*\S{1,24}/g);
  if(multi&&multi.length>=2){
    return multi.map(function(x){
      const mm=/^(\d{1,3})\s*[.、．)]\s*(.+)$/.exec(x.trim());
      return mm?{no:parseInt(mm[1],10),text:mm[2].trim()}:null;
    }).filter(Boolean);
  }
  const one=/^(\d{1,3})\s*[.、．)]\s*(.+)$/.exec(body);
  if(one)return [{no:parseInt(one[1],10),text:one[2].trim()}];
  return [{no:null,text:body}];
}

function t10InlineOptions(stem){
  const s=String(stem||"");
  const marks=s.match(/(?:^|\s)[A-Da-d]\s*[.、．)]/g)||[];
  if(marks.length<2)return null;
  const parts=s.split(/(?:^|\s)[A-Da-d]\s*[.、．)]/).map(function(x){return x.trim();}).filter(Boolean);
  if(parts.length<3)return null;
  return {head:parts[0],options:parts.slice(1).map(function(t,i){return String.fromCharCode(65+i)+"."+t;})};
}

function t10QType(item,section){
  const s=String(section||"")+" "+String((item&&item.stem)||"").slice(0,40);
  if((item&&item.options||[]).length>=2)return "choice";
  if(/填空|填写/.test(s))return "blank";
  if(/判断/.test(s))return "judge";
  if(/解答|计算|应用|证明|简答|论述|综述|分析|改错|案例|翻译|写作/.test(s))return "solve";
  return "unknown";
}

function structureExamText(text,type){
  const lines=t10ExamLines(text);
  const items=[];let cur=null;let section=null;const secOrder=[];const ansPool=[];
  function flush(){
    // 上限在收尾 flush 时也要生效，否则最后一道题会突破 EXAM_MAX_ITEMS（单卷上限 300）
    if(cur&&(cur.stem||cur.raw)&&items.length<EXAM_MAX_ITEMS)items.push(cur);
    cur=null;
  }
  for(let i=0;i<lines.length&&items.length<EXAM_MAX_ITEMS;i++){
    const ln=lines[i];
    const sec=t10SectionOf(ln);
    if(sec){
      section=sec;
      if(secOrder.indexOf(sec)<0)secOrder.push(sec);
      continue;
    }
    const qh=t10QuestionHead(ln);
    if(qh){
      flush();
      cur={no:items.length+1,rawNo:qh.no,section:section,stem:qh.rest,options:[],answer:"",qtype:"",raw:ln,kps:[]};
      continue;
    }
    const om=/^\s*([A-Da-d])\s*[.、．)]\s*(.+)$/.exec(ln);
    if(om&&cur){cur.options.push(om[1].toUpperCase()+"."+om[2].trim());cur.raw+="\n"+ln;continue;}
    const an=t10AnswerOf(ln);
    if(an&&an.length){
      if(cur&&an.length===1&&an[0].no==null){cur.answer=an[0].text;cur.raw+="\n"+ln;}
      else{an.forEach(function(a){ansPool.push(a);});}
      continue;
    }
    if(cur){cur.stem+=(cur.stem?"\n":"")+ln;cur.raw+="\n"+ln;}
  }
  flush();
  items.forEach(function(it){
    if(it.options.length)return;
    const io=t10InlineOptions(it.stem);
    if(io){it.stem=io.head;it.options=io.options;}
  });
  items.forEach(function(it){
    it.qtype=t10QType(it,it.section);
    it.stem=String(it.stem||"").replace(/\n{2,}/g,"\n").trim().slice(0,600);
    it.raw=String(it.raw||"").slice(0,900);
  });
  ansPool.forEach(function(a){
    if(a.no!=null){
      const it=items.find(function(x){return x.rawNo===a.no;});
      if(it&&!it.answer)it.answer=a.text;
    }
  });
  const un=items.filter(function(it){return !it.answer;});
  if(un.length&&ansPool.length&&ansPool.every(function(a){return a.no==null;})&&ansPool.length===un.length){
    un.forEach(function(it,i){it.answer=ansPool[i].text;});
  }
  const sections=secOrder.map(function(t){
    return {title:t,items:items.filter(function(it){return it.section===t;}).length};
  });
  if(!sections.length&&items.length)sections.push({title:"全部题目",items:items.length});
  return {items:items,sections:sections};
}

function t10Triples(nodes,edges){
  const titles={};
  nodes.forEach(function(n){titles[n.id]=n.title;});
  const label={prerequisite:"先修于",related:"同题共现",attach:"归属",tested:"考查"};
  return edges.map(function(e){
    return {subject:titles[e.from]||e.from,relation:label[e.etype]||e.etype||"关联",
      object:titles[e.to]||e.to,weight:+(e.w||0).toFixed(3),confidence:e.conf!=null?+e.conf.toFixed(3):null};
  });
}

  return { t10InflateRaw: t10InflateRaw, t10Decode: t10Decode, t10Ent: t10Ent, t10XmlText: t10XmlText, t10HtmlText: t10HtmlText, t10PaperTypeLabel: t10PaperTypeLabel, t10QTypeLabel: t10QTypeLabel, t10ExamLines: t10ExamLines, t10SectionOf: t10SectionOf, t10QuestionHead: t10QuestionHead, t10AnswerOf: t10AnswerOf, t10InlineOptions: t10InlineOptions, t10QType: t10QType, structureExamText: structureExamText, t10Triples: t10Triples };
});
