/**
 * 图谱力导向图 —— 复刻 Web 版识网页的 CanvasRenderer。
 *
 * 变换模型与 Web 一致：screen = world*scale + offset。
 * - 单指拖拽平移；双指捏合以手势中心缩放；点按命中选中；双击放大到指针
 * - 命中半径 = 20/scale（世界单位），与 Web 的 minDist 一致
 * - 节点三色：章节蓝 / 词绿 / 债红（对应 Web .dnode.chapter/term/debt）
 * - 数据或画布尺寸变化时先布局再「适应视图」，不会出现空白或跑出画面
 */
import { KNode, KEdge } from '../model/Models';
import { Theme } from '../common/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface Pt {
  x: number;
  y: number;
  vx: number;
  vy: number;
}

/** 画布控制器：把 fit/reset 暴露给页面上的按钮（避免按钮压在画布上吞掉节点点击） */
export class GraphCtrl {
  fit: () => void = () => {};
  reset: () => void = () => {};
}

/** 世界坐标系尺寸（布局画布，与屏幕解耦） */
const WORLD_W: number = 1000;
const WORLD_H: number = 800;

@Component
export struct GraphCanvas {
  @Prop nodes: KNode[];
  @Prop edges: KEdge[];
  @Prop selectedId: string;
  /** 债节点集合（用于「债红」配色），由页面注入 */
  @Prop debtIds: string[];
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  @State private w: number = 300;
  @State private h: number = 300;
  /** 组件在窗口中的全局位置（vp），自动化测试据此把画布坐标换算成设备坐标 */
  @State private originX: number = 0;
  @State private originY: number = 0;
  private pos: Map<string, Pt> = new Map();
  onSelect: (id: string) => void = () => {};
  /** 页面传入的控制器；aboutToAppear 时把 fit/reset 挂上 */
  ctrl: GraphCtrl = new GraphCtrl();

  // ── 视图变换（与 Web scale/offsetX/offsetY 同语义）──
  private viewScale: number = 1;
  private voffX: number = 0;
  private voffY: number = 0;

  // ── 手势状态 ──
  private dragging: boolean = false;
  private moved: boolean = false;
  private lastX: number = 0;
  private lastY: number = 0;
  private pinchBaseDist: number = 0;
  private pinchBaseScale: number = 1;
  private lastTapTime: number = 0;

  aboutToAppear(): void {
    this.ctrl.fit = () => this.fitView();
    this.ctrl.reset = () => this.resetZoom();
    this.layoutWorld();
  }

  /** 力导向布局：在世界坐标系里跑，屏幕尺寸只影响适应视图 */
  private layoutWorld(): void {
    const n = this.nodes.length;
    if (n === 0) {
      this.pos.clear();
      return;
    }
    const cx = WORLD_W / 2;
    const cy = WORLD_H / 2;
    for (let i = 0; i < n; i++) {
      const id = this.nodes[i].id;
      const ang = (2 * Math.PI * i) / n;
      const r = Math.min(WORLD_W, WORLD_H) * 0.3;
      this.pos.set(id, { x: cx + r * Math.cos(ang), y: cy + r * Math.sin(ang), vx: 0, vy: 0 });
    }
    const k = Math.sqrt((WORLD_W * WORLD_H) / Math.max(n, 1)) * 0.6;
    for (let step = 0; step < 220; step++) {
      const temp = Math.max(1, 20 * (1 - step / 220));
      for (let i = 0; i < n; i++) {
        const a = this.pos.get(this.nodes[i].id)!;
        for (let j = i + 1; j < n; j++) {
          const b = this.pos.get(this.nodes[j].id)!;
          let dx = a.x - b.x;
          let dy = a.y - b.y;
          let d2 = dx * dx + dy * dy;
          if (d2 < 0.01) {
            dx = (i % 3) + 1;
            dy = (j % 3) + 1;
            d2 = dx * dx + dy * dy;
          }
          const d = Math.sqrt(d2);
          const f = (k * k) / d2;
          a.vx += (dx / d) * f;
          a.vy += (dy / d) * f;
          b.vx -= (dx / d) * f;
          b.vy -= (dy / d) * f;
        }
      }
      for (const e of this.edges) {
        const a = this.pos.get(e.a);
        const b = this.pos.get(e.b);
        if (!a || !b) {
          continue;
        }
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const d = Math.sqrt(dx * dx + dy * dy) || 1;
        const f = ((d - k) / d) * 0.25;
        a.vx += dx * f;
        a.vy += dy * f;
        b.vx -= dx * f;
        b.vy -= dy * f;
      }
      for (let i = 0; i < n; i++) {
        const p = this.pos.get(this.nodes[i].id)!;
        p.vx += (cx - p.x) * 0.012;
        p.vy += (cy - p.y) * 0.012;
        const v = Math.sqrt(p.vx * p.vx + p.vy * p.vy) || 1;
        const s = Math.min(v, temp) / v;
        p.x += p.vx * s;
        p.y += p.vy * s;
        p.x = Math.max(24, Math.min(WORLD_W - 24, p.x));
        p.y = Math.max(24, Math.min(WORLD_H - 24, p.y));
        p.vx = 0;
        p.vy = 0;
      }
    }
    this.fitView();
  }

  /** 适应视图：让世界包围盒缩放居中到屏幕内 */
  private fitView(): void {
    if (this.w < 8 || this.h < 8 || this.pos.size === 0) {
      return;
    }
    let minX = WORLD_W;
    let minY = WORLD_H;
    let maxX = 0;
    let maxY = 0;
    this.pos.forEach((p: Pt) => {
      minX = Math.min(minX, p.x);
      minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x);
      maxY = Math.max(maxY, p.y);
    });
    const bw = Math.max(maxX - minX, 1) + 60;
    const bh = Math.max(maxY - minY, 1) + 60;
    const s = Math.max(0.1, Math.min(10, Math.min(this.w / bw, this.h / bh)));
    this.viewScale = s;
    this.voffX = (this.w - (maxX + minX) * s) / 2;
    this.voffY = (this.h - (maxY + minY) * s) / 2;
    this.draw();
  }

  /** 重置到 100%：缩放固定 1.0，把世界包围盒中心对齐到画布中心 */
  private resetZoom(): void {
    if (this.w < 8 || this.h < 8 || this.pos.size === 0) {
      return;
    }
    let minX = WORLD_W;
    let minY = WORLD_H;
    let maxX = 0;
    let maxY = 0;
    this.pos.forEach((p: Pt) => {
      minX = Math.min(minX, p.x);
      minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x);
      maxY = Math.max(maxY, p.y);
    });
    this.viewScale = 1;
    this.voffX = this.w / 2 - (minX + maxX) / 2;
    this.voffY = this.h / 2 - (minY + maxY) / 2;
    this.draw();
  }

  /** 世界坐标 → 屏幕坐标 */
  private sx(wx: number): number {
    return wx * this.viewScale + this.voffX;
  }

  private sy(wy: number): number {
    return wy * this.viewScale + this.voffY;
  }

  private draw(): void {
    const ctx = this.ctx;
    const s = this.viewScale;
    ctx.clearRect(0, 0, this.w, this.h);
    ctx.fillStyle = Theme.SURFACE;
    ctx.fillRect(0, 0, this.w, this.h);

    // 边（Web 用 #55a77b）
    ctx.strokeStyle = Theme.EDGE;
    ctx.globalAlpha = 0.75;
    ctx.lineWidth = 1.2 * Math.max(0.6, Math.min(1.6, s));
    for (const e of this.edges) {
      const a = this.pos.get(e.a);
      const b = this.pos.get(e.b);
      if (!a || !b) {
        continue;
      }
      ctx.beginPath();
      ctx.moveTo(this.sx(a.x), this.sy(a.y));
      ctx.lineTo(this.sx(b.x), this.sy(b.y));
      ctx.stroke();
    }
    ctx.globalAlpha = 1;

    // 节点
    const r = Math.max(5, Math.min(11, 9 * Math.sqrt(s)));
    const isDebt = (id: string): boolean => {
      for (const d of this.debtIds) {
        if (d === id) {
          return true;
        }
      }
      return false;
    };
    for (const n of this.nodes) {
      const p = this.pos.get(n.id);
      if (!p) {
        continue;
      }
      const x = this.sx(p.x);
      const y = this.sy(p.y);
      const debt = isDebt(n.id);
      const chapter = n.kind === 'chapter';
      // 填充与描边按 Web .dnode 三色
      ctx.fillStyle = debt ? Theme.NODE_DEBT_FILL :
        (chapter ? Theme.NODE_CHAPTER_FILL : Theme.NODE_TERM_FILL);
      ctx.strokeStyle = debt ? Theme.NODE_DEBT_BORDER :
        (chapter ? Theme.NODE_CHAPTER_BORDER : Theme.NODE_TERM_BORDER);
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      // 选中：外圈主色高亮
      if (n.id === this.selectedId) {
        ctx.strokeStyle = Theme.PRIMARY;
        ctx.lineWidth = 2.5;
        ctx.beginPath();
        ctx.arc(x, y, r + 3.5, 0, Math.PI * 2);
        ctx.stroke();
      }
      // 标签（Web：12.5px 加粗，章节用 11px）
      const fs = chapter ? 11 : 12.5;
      ctx.font = `${fs}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = debt ? Theme.NODE_DEBT_INK : (chapter ? Theme.NODE_CHAPTER_INK : Theme.NODE_TERM_INK);
      const title = n.title.length > 8 ? `${n.title.substring(0, 8)}…` : n.title;
      ctx.fillText(title, x, y + r + fs * 0.8);
    }
    const dbg: string[] = [];
    this.pos.forEach((p: Pt, id: string) => {
      dbg.push(`${id}@${Math.round(this.sx(p.x))},${Math.round(this.sy(p.y))}`);
    });
    hilog.info(0x0000, 'GRAPHCANVAS',
      `canvas ${Math.round(this.w)}x${Math.round(this.h)} ` +
      `origin=${Math.round(this.originX)},${Math.round(this.originY)} scale=${s.toFixed(2)} ` +
      `off=${Math.round(this.voffX)},${Math.round(this.voffY)} selected=${this.selectedId} ` +
      `nodes=${dbg.join(' ')}`);
  }

  /** 命中判定：世界距离 < 20/scale（与 Web minDist 一致） */
  private hitTest(tx: number, ty: number): string {
    const wx = (tx - this.voffX) / this.viewScale;
    const wy = (ty - this.voffY) / this.viewScale;
    const maxD = 20 / this.viewScale;
    let best = '';
    let bestD = maxD * maxD;
    this.pos.forEach((p: Pt, id: string) => {
      const dx = p.x - wx;
      const dy = p.y - wy;
      const d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        best = id;
      }
    });
    return best;
  }

  private zoomAt(mx: number, my: number, factor: number): void {
    const wx = (mx - this.voffX) / this.viewScale;
    const wy = (my - this.voffY) / this.viewScale;
    this.viewScale = Math.max(0.1, Math.min(10, this.viewScale * factor));
    this.voffX = mx - wx * this.viewScale;
    this.voffY = my - wy * this.viewScale;
    this.draw();
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onAreaChange((oldVal: Area, newVal: Area) => {
          const w = Number(newVal.width);
          const h = Number(newVal.height);
          this.originX = Number(newVal.globalPosition.x);
          this.originY = Number(newVal.globalPosition.y);
          if (w > 0 && h > 0 && (Math.abs(w - this.w) > 4 || Math.abs(h - this.h) > 4)) {
            this.w = w;
            this.h = h;
            // 尺寸变化后必须重新适应视图并重绘，否则画面坐标与命中坐标错位
            this.fitView();
          }
        })
        .onReady(() => {
          this.layoutWorld();
        })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            if (e.touches.length === 1) {
              this.lastX = e.touches[0].x;
              this.lastY = e.touches[0].y;
              this.dragging = true;
              this.moved = false;
            } else if (e.touches.length === 2) {
              // 双指捏合：以手势中心为定点缩放
              const dx = e.touches[0].x - e.touches[1].x;
              const dy = e.touches[0].y - e.touches[1].y;
              this.pinchBaseDist = Math.sqrt(dx * dx + dy * dy) || 1;
              this.pinchBaseScale = this.viewScale;
              this.dragging = false;
            }
            return;
          }
          if (e.type === TouchType.Move) {
            if (e.touches.length === 2 && this.pinchBaseDist > 0) {
              const dx = e.touches[0].x - e.touches[1].x;
              const dy = e.touches[0].y - e.touches[1].y;
              const dist = Math.sqrt(dx * dx + dy * dy) || 1;
              const mx = (e.touches[0].x + e.touches[1].x) / 2;
              const my = (e.touches[0].y + e.touches[1].y) / 2;
              const target = Math.max(0.1, Math.min(10,
                this.pinchBaseScale * (dist / this.pinchBaseDist)));
              this.zoomAt(mx, my, target / this.viewScale);
              this.moved = true;
              return;
            }
            if (this.dragging && e.touches.length === 1) {
              const dx = e.touches[0].x - this.lastX;
              const dy = e.touches[0].y - this.lastY;
              if (Math.abs(dx) > 1.5 || Math.abs(dy) > 1.5) {
                this.moved = true;
              }
              this.voffX += dx;
              this.voffY += dy;
              this.lastX = e.touches[0].x;
              this.lastY = e.touches[0].y;
              this.draw();
            }
            return;
          }
          if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            this.pinchBaseDist = 0;
            if (!this.dragging) {
              return;
            }
            this.dragging = false;
            if (this.moved) {
              return; // 拖拽过就不算点击
            }
            const tx = this.lastX;
            const ty = this.lastY;
            // 双击：放大到指针
            const now = Date.now();
            // 阈值取 450ms：系统双击间隔通常 300ms 左右，280ms 会把双击拆成两次单击
            if (now - this.lastTapTime < 450) {
              this.zoomAt(tx, ty, 1.6);
              this.lastTapTime = 0;
              return;
            }
            this.lastTapTime = now;
            const hit = this.hitTest(tx, ty);
            if (hit.length > 0) {
              this.onSelect(hit);
              // 选中后立即重绘高亮圈；否则日志与画面都是旧状态（实测踩过）
              this.draw();
            }
          }
        })
    }
    .width('100%')
    .height('100%')
  }
}
