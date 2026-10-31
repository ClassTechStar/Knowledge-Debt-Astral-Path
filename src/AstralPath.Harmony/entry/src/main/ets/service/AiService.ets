/**
 * 模型服务 —— 与单文件版同一套接口：OpenAI 兼容的 /v1/chat/completions，
 * 鉴权 Authorization: Bearer <key>，SSE 流式（data: {...}\n\n，以 [DONE] 结束）。
 * 未配置密钥或网络不可用时返回 null，调用方走本地规则兜底（演示模式），
 * 这一点和 Web / Android 版保持一致：AI 挂了不影响核心功能。
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

export interface AiConfig {
  baseUrl: string;
  key: string;
  model: string;
}

export interface AiChunk {
  text: string;
  done: boolean;
}

/** /v1/chat/completions 请求体 */
export interface ChatRequestBody {
  model: string;
  messages: ChatMessage[];
  stream: boolean;
  max_tokens: number;
}

export class AiService {
  static readonly DEFAULT_BASE: string = 'https://api.xiaomimimo.com/v1';

  static ready(cfg: AiConfig): boolean {
    return !!cfg && !!cfg.key && cfg.key.length > 0;
  }

  /** 非流式：一次拿全量，用于讲解、计划编排等对实时性要求不高的场景 */
  static async complete(cfg: AiConfig, prompt: string, maxTokens: number = 1500): Promise<string | null> {
    if (!AiService.ready(cfg)) {
      return null;
    }
    const msg: ChatMessage = { role: 'user', content: prompt };
    const reqBody: ChatRequestBody = {
      model: cfg.model,
      messages: [msg],
      stream: false,
      max_tokens: maxTokens
    };
    const req = http.createHttp();
    try {
      const res = await new Promise<http.HttpResponse>((resolve, reject) => {
        req.request(`${cfg.baseUrl || AiService.DEFAULT_BASE}/chat/completions`, {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': `Bearer ${cfg.key}`
          },
          extraData: JSON.stringify(reqBody),
          expectDataType: http.HttpDataType.STRING
        }, (err: Error, data: http.HttpResponse) => {
          if (err) {
            reject(err);
          } else {
            resolve(data);
          }
        });
      });
      if (res.responseCode !== 200) {
        return null;
      }
      const body = JSON.parse(res.result as string) as ChatResponse;
      return body?.choices?.[0]?.message?.content ?? null;
    } catch (e) {
      return null;
    } finally {
      req.destroy();
    }
  }

  /** 流式：逐块回调，用于智能体对话与「命题中」进度；失败时回退到非流式 */
  static async stream(cfg: AiConfig, prompt: string, onDelta: (chunk: AiChunk) => void,
    maxTokens: number = 1500): Promise<void> {
    if (!AiService.ready(cfg)) {
      onDelta({ text: '', done: true });
      return;
    }
    const req = http.createHttp();
    const streamMsg: ChatMessage = { role: 'user', content: prompt };
    const streamBody: ChatRequestBody = {
      model: cfg.model,
      messages: [streamMsg],
      stream: true,
      max_tokens: maxTokens
    };
    const body = JSON.stringify(streamBody);
    // 解码与分行必须带缓冲：网络 chunk 既不按 UTF-8 字符边界切，也不按 SSE 事件边界切——
    // 逐字节 String.fromCharCode 会把跨 chunk 的中文解码成乱码，跨 chunk 的 JSON 事件会被整条丢弃（掉字）。
    // TextDecoder 的 stream 模式负责攒多字节字符，lineBuf 负责攒半行。
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    let lineBuf: string = '';
    let finished = false;
    const handleLine = (line: string): void => {
      const t = line.trim();
      if (!t.startsWith('data:')) {
        return;
      }
      const payload = t.slice(5).trim();
      if (payload === '[DONE]') {
        finished = true;
        onDelta({ text: '', done: true });
        return;
      }
      try {
        const j = JSON.parse(payload) as StreamResponse;
        const delta = j?.choices?.[0]?.delta?.content ?? '';
        if (delta) {
          onDelta({ text: delta, done: false });
        }
      } catch (e) {
        // 完整行但解析失败（心跳/注释行），忽略
      }
    };
    req.on('dataReceive', (chunk: ArrayBuffer) => {
      if (finished) {
        return;
      }
      let text = '';
      try {
        text = decoder.decodeToString(new Uint8Array(chunk), { stream: true });
      } catch (e) {
        return; // 解码失败丢弃本块，不中断流
      }
      lineBuf += text;
      const lines = lineBuf.split('\n');
      lineBuf = lines.pop() ?? ''; // 最后一段可能是不完整行，留到下一块
      for (const line of lines) {
        handleLine(line);
        if (finished) {
          return;
        }
      }
    });
    req.on('dataEnd', () => {
      if (!finished && lineBuf.trim().length > 0) {
        handleLine(lineBuf); // 流结束时的最后半行
      }
      lineBuf = '';
      onDelta({ text: '', done: true });
      req.destroy();
    });
    await new Promise<void>((resolve) => {
      req.requestInStream(`${cfg.baseUrl || AiService.DEFAULT_BASE}/chat/completions`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Bearer ${cfg.key}`,
          'Accept': 'text/event-stream'
        },
        expectDataType: http.HttpDataType.STRING
      }).then(() => resolve()).catch(() => {
        onDelta({ text: '', done: true });
        resolve();
      });
    });
  }

}

export interface ChatMessage {
  role?: string;
  content?: string;
}

export interface ChatChoice {
  message?: ChatMessage;
  delta?: ChatMessage;
}

export interface ChatResponse {
  choices?: ChatChoice[];
}

export interface StreamResponse {
  choices?: ChatChoice[];
}
