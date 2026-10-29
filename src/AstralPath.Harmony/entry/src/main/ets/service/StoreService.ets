/**
 * 存储服务 —— 对应单文件版 shared/store.js 的五分片布局（ap:meta/books/answers/plan/papers）。
 * 鸿蒙侧用 @kit.ArkData 的 preferences（用户首选项）按分片各存一份，
 * 一次作答只回写 answers，避免整包序列化（与原实现的分片动机一致）。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppState, Book, AnswerLog, Mastery, Paper, PlanItem, MetaShard, SaleState, AnswersShard } from '../model/Models';

const STORE_NAME: string = 'astralpath';
const KEY_META: string = 'ap:meta';
const KEY_BOOKS: string = 'ap:books';
const KEY_ANSWERS: string = 'ap:answers';
const KEY_PLAN: string = 'ap:plan';
const KEY_PAPERS: string = 'ap:papers';
const KEY_AI: string = 'ap:aicfg';

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

  // ── 分片读写 ──────────────────────────────────────────
  static async loadMeta(): Promise<MetaShard> {
    const raw = await StoreService.get().get(KEY_META, '') as string;
    return raw ? (JSON.parse(raw) as MetaShard) : StoreService.defaultMeta();
  }

  static async saveMeta(meta: MetaShard): Promise<void> {
    await StoreService.get().put(KEY_META, JSON.stringify(meta));
    await StoreService.get().flush();
  }

  static async loadBooks(): Promise<Book[]> {
    const raw = await StoreService.get().get(KEY_BOOKS, '[]') as string;
    return JSON.parse(raw) as Book[];
  }

  static async saveBooks(books: Book[]): Promise<void> {
    await StoreService.get().put(KEY_BOOKS, JSON.stringify(books));
    await StoreService.get().flush();
  }

  /** answers 分片（写最频繁）：mastery / logs / sale */
  static async loadAnswers(): Promise<AnswersShard> {
    const raw = await StoreService.get().get(KEY_ANSWERS, '') as string;
    return raw ? JSON.parse(raw) as AnswersShard : { mastery: {}, logs: [], sale: {} };
  }

  static async saveAnswers(a: AnswersShard): Promise<void> {
    await StoreService.get().put(KEY_ANSWERS, JSON.stringify(a));
    await StoreService.get().flush();
  }

  static async loadPlan(): Promise<PlanItem[]> {
    const raw = await StoreService.get().get(KEY_PLAN, '[]') as string;
    return JSON.parse(raw) as PlanItem[];
  }

  static async savePlan(plan: PlanItem[]): Promise<void> {
    await StoreService.get().put(KEY_PLAN, JSON.stringify(plan));
    await StoreService.get().flush();
  }

  static async loadPapers(): Promise<Paper[]> {
    const raw = await StoreService.get().get(KEY_PAPERS, '[]') as string;
    return JSON.parse(raw) as Paper[];
  }

  static async savePapers(papers: Paper[]): Promise<void> {
    await StoreService.get().put(KEY_PAPERS, JSON.stringify(papers));
    await StoreService.get().flush();
  }

  /** 模型配置（base url / key / model）。生产环境应改用 Asset Store Kit 做加密存储，
   *  这里先用首选项，保证「密钥只存本机」这一条不被破坏。 */
  static async loadAiCfg(): Promise<AiCfg> {
    const raw = await StoreService.get().get(KEY_AI, '') as string;
    return raw ? JSON.parse(raw) as AiCfg : { baseUrl: '', key: '', model: '' };
  }

  static async saveAiCfg(cfg: AiCfg): Promise<void> {
    await StoreService.get().put(KEY_AI, JSON.stringify(cfg));
    await StoreService.get().flush();
  }

  static async loadAll(): Promise<AppState> {
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
