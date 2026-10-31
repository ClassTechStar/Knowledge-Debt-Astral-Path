/**
 * 存储服务 —— 对应单文件版 shared/store.js 的五分片布局（ap:meta/books/answers/plan/papers）。
 * 鸿蒙侧用 @kit.ArkData 的 preferences（用户首选项）按分片各存一份，
 * 一次作答只回写 answers，避免整包序列化（与原实现的分片动机一致）。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppState, Book, AnswerLog, Mastery, Paper, PlanItem, MetaShard, SaleState, AnswersShard } from '../model/Models';

const STORE_NAME: string = 'astralpath';
const KEY_META: string = 'ap:meta';
const KEY_BOOKS: string = 'ap:books';
const KEY_ANSWERS: string = 'ap:answers';
const KEY_PLAN: string = 'ap:plan';
const KEY_PAPERS: string = 'ap:papers';
const KEY_AI: string = 'ap:aicfg';
// 版本标记：与 Web 版 ap:schema 同语义。分片布局演进时升 SCHEMA_VERSION 并补迁移器；
// 旧数据首次读取补写标记，更高版本的数据按只读处理，防止旧版本覆盖写坏。
const KEY_SCHEMA: string = 'ap:schema';
const SCHEMA_VERSION: number = 2;
const TAG: string = 'StoreService';

export interface AiCfg {
  baseUrl: string;
  key: string;
  model: string;
}

export class StoreService {
  private static store: preferences.Preferences | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (StoreService.store) {
      return;
    }
    StoreService.store = await preferences.getPreferences(context, STORE_NAME);
  }

  private static get(): preferences.Preferences {
    if (!StoreService.store) {
      throw new Error('StoreService 未初始化，请先调用 init(context)');
    }
    return StoreService.store;
  }

  // ── 版本协商与自愈 ────────────────────────────────────
  /** 加载完成后调用，幂等：无标记补写、标记损坏重写、更高版本记警告（调用方只读使用） */
  static async ensureSchema(): Promise<void> {
    const s = StoreService.get();
    const raw = await s.get(KEY_SCHEMA, '') as string;
    let v = 0;
    let broken = false;
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as number;
        if (typeof parsed === 'number' && parsed >= 0) {
          v = parsed;
        } else {
          broken = true;
        }
      } catch (e) {
        broken = true;
      }
    }
    if (broken) {
      hilog.warn(0x0000, TAG, `schema mark corrupted, rewrite to ${SCHEMA_VERSION}`);
      await s.put(KEY_SCHEMA, JSON.stringify(SCHEMA_VERSION));
      await s.flush();
      return;
    }
    if (v > SCHEMA_VERSION) {
      // 数据来自更高版本的应用：不覆写标记，调用方应避免覆盖保存
      hilog.warn(0x0000, TAG, `data written by newer version (v${v} > v${SCHEMA_VERSION}), treat as read-only`);
      return;
    }
    if (v < SCHEMA_VERSION) {
      await s.put(KEY_SCHEMA, JSON.stringify(SCHEMA_VERSION));
      await s.flush();
    }
  }

  /** 读一个分片：损坏时先把原始串备份到 ap:backup:<key>，再删坏键返回默认值。
   *  对齐 Web 版 repairIfCorrupt 的语义：一片坏了不拖垮整包，原始串可人工找回。 */
  private static async loadShard<T>(key: string, fallback: T, revive: (raw: string) => T): Promise<T> {
    const s = StoreService.get();
    const raw = await s.get(key, '') as string;
    if (!raw) {
      return fallback;
    }
    try {
      return revive(raw);
    } catch (e) {
      hilog.error(0x0000, TAG, `shard ${key} corrupted, backup and reset: ${(e as Error).message}`);
      try {
        await s.put(`ap:backup:${key}`, raw);
        await s.delete(key);
        await s.flush();
      } catch (e2) {
        hilog.warn(0x0000, TAG, `backup failed: ${(e2 as Error).message}`);
      }
      return fallback;
    }
  }

  // ── 分片读写 ──────────────────────────────────────────
  static async loadMeta(): Promise<MetaShard> {
    return StoreService.loadShard<MetaShard>(KEY_META, StoreService.defaultMeta(),
      (raw: string) => JSON.parse(raw) as MetaShard);
  }

  static async saveMeta(meta: MetaShard): Promise<void> {
    await StoreService.get().put(KEY_META, JSON.stringify(meta));
    await StoreService.get().flush();
  }

  static async loadBooks(): Promise<Book[]> {
    return StoreService.loadShard<Book[]>(KEY_BOOKS, [],
      (raw: string) => JSON.parse(raw) as Book[]);
  }

  static async saveBooks(books: Book[]): Promise<void> {
    await StoreService.get().put(KEY_BOOKS, JSON.stringify(books));
    await StoreService.get().flush();
  }

  /** answers 分片（写最频繁）：mastery / logs / sale */
  static async loadAnswers(): Promise<AnswersShard> {
    return StoreService.loadShard<AnswersShard>(KEY_ANSWERS, { mastery: {}, logs: [], sale: {} },
      (raw: string) => JSON.parse(raw) as AnswersShard);
  }

  static async saveAnswers(a: AnswersShard): Promise<void> {
    await StoreService.get().put(KEY_ANSWERS, JSON.stringify(a));
    await StoreService.get().flush();
  }

  static async loadPlan(): Promise<PlanItem[]> {
    return StoreService.loadShard<PlanItem[]>(KEY_PLAN, [],
      (raw: string) => JSON.parse(raw) as PlanItem[]);
  }

  static async savePlan(plan: PlanItem[]): Promise<void> {
    await StoreService.get().put(KEY_PLAN, JSON.stringify(plan));
    await StoreService.get().flush();
  }

  static async loadPapers(): Promise<Paper[]> {
    return StoreService.loadShard<Paper[]>(KEY_PAPERS, [],
      (raw: string) => JSON.parse(raw) as Paper[]);
  }

  static async savePapers(papers: Paper[]): Promise<void> {
    await StoreService.get().put(KEY_PAPERS, JSON.stringify(papers));
    await StoreService.get().flush();
  }

  /** 模型配置（base url / key / model）。生产环境应改用 Asset Store Kit 做加密存储，
   *  这里先用首选项，保证「密钥只存本机」这一条不被破坏。 */
  static async loadAiCfg(): Promise<AiCfg> {
    return StoreService.loadShard<AiCfg>(KEY_AI, { baseUrl: '', key: '', model: '' },
      (raw: string) => JSON.parse(raw) as AiCfg);
  }

  static async saveAiCfg(cfg: AiCfg): Promise<void> {
    await StoreService.get().put(KEY_AI, JSON.stringify(cfg));
    await StoreService.get().flush();
  }

  static async loadAll(): Promise<AppState> {
    await StoreService.ensureSchema();
    const meta = await StoreService.loadMeta();
    const books = await StoreService.loadBooks();
    const ans = await StoreService.loadAnswers();
    return {
      meta: meta,
      books: books,
      mastery: ans.mastery,
      logs: ans.logs,
      sale: ans.sale,
      plan: await StoreService.loadPlan(),
      papers: await StoreService.loadPapers()
    };
  }

  /** 清空本机数据（账户页「清除本机数据」） */
  static async wipe(): Promise<void> {
    const s = StoreService.get();
    await s.delete(KEY_META);
    await s.delete(KEY_BOOKS);
    await s.delete(KEY_ANSWERS);
    await s.delete(KEY_PLAN);
    await s.delete(KEY_PAPERS);
    await s.delete(KEY_AI);
    // 清数据的同时清掉版本标记与损坏备份，避免下次启动读到孤儿备份
    await s.delete(KEY_SCHEMA);
    await s.delete('ap:backup:ap:meta');
    await s.delete('ap:backup:ap:books');
    await s.delete('ap:backup:ap:answers');
    await s.delete('ap:backup:ap:plan');
    await s.delete('ap:backup:ap:papers');
    await s.delete('ap:backup:ap:aicfg');
    await s.flush();
  }

  private static defaultMeta(): MetaShard {
    return {
      userName: '王小明（有债）',
      activeBookId: '',
      day: 1,
      consent: false,
      optOut: false,
      onboard: false
    };
  }
}
