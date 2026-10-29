/**
 * 图谱力导向图 —— 用 Canvas 自绘，对齐 Web 版识网页的「节点 + 边 + 点选」。
 *
 * 布局：斥力（节点互推）+ 弹簧（边拉近）+ 向心力（防止飘走），迭代若干轮后定型。
 * 不做动画循环（省电、不抖），数据变化时重算一次；点击按最近节点命中。
 * 折叠屏展开态画布更宽，节点会自动铺开（坐标按画布尺寸归一化）。
 */
import { KNode, KEdge } from '../model/Models';

interface Pt {
  x: number;
  y: number;
  vx: number;
  vy: number;
}

@Component
export struct GraphCanvas {
  @Prop nodes: KNode[];
  @Prop edges: KEdge[];
  @Prop selectedId: string;
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  @State private w: number = 300;
  @State private h: number = 300;
  private pos: Map<string, Pt> = new Map();
  onSelect: (id: string) => void = () => {};

  aboutToAppear(): void {
    this.layout(300, 300);
  }

  /** 力导向布局：迭代 220 轮，温度递减 */
  private layout(w: number, h: number): void {
    const n = this.nodes.length;
    if (n === 0) {
      return;
    }
    const cx = w / 2;
    const cy = h / 2;
    // 初始位置：圆周均匀分布，带一点确定性抖动，避免完全对称导致斥力抵消
    for (let i = 0; i < n; i++) {
      const id = this.nodes[i].id;
      const ang = (2 * Math.PI * i) / n;
      const r = Math.min(w, h) * 0.3;
      this.pos.set(id, { x: cx + r * Math.cos(ang), y: cy + r * Math.sin(ang), vx: 0, vy: 0 });
    }
    const k = Math.sqrt((w * h) / Math.max(n, 1)) * 0.6; // 理想边长
    for (let step = 0; step < 220; step++) {
      const temp = Math.max(1, 20 * (1 - step / 220));
      // 斥力
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
      // 弹簧
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
      // 向心 + 积分
      for (let i = 0; i < n; i++) {
        const p = this.pos.get(this.nodes[i].id)!;
        p.vx += (cx - p.x) * 0.012;
        p.vy += (cy - p.y) * 0.012;
        const v = Math.sqrt(p.vx * p.vx + p.vy * p.vy) || 1;
        const scale = Math.min(v, temp) / v;
        p.x += p.vx * scale;
        p.y += p.vy * scale;
        p.x = Math.max(16, Math.min(w - 16, p.x));
        p.y = Math.max(16, Math.min(h - 16, p.y));
        p.vx = 0;
        p.vy = 0;
      }
    }
  }

  private draw(): void {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.w, this.h);
    // 边
    ctx.strokeStyle = '#C9D2DE';
    ctx.lineWidth = 1.2;
    for (const e of this.edges) {
      const a = this.pos.get(e.a);
      const b = this.pos.get(e.b);
      if (!a || !b) {
        continue;
      }
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.stroke();
    }
    // 节点
    const r = Math.max(6, Math.min(10, 120 / Math.max(this.nodes.length, 1)));
    ctx.font = '11px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (const n of this.nodes) {
      const p = this.pos.get(n.id);
      if (!p) {
        continue;
      }
      const on = n.id === this.selectedId;
      ctx.fillStyle = on ? '#2F6BFF' : (n.diff >= 3 ? '#C77700' : '#1F9254');
      ctx.beginPath();
      ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = on ? '#2F6BFF' : '#1E2228';
      const title = n.title.length > 6 ? `${n.title.substring(0, 6)}…` : n.title;
      ctx.fillText(title, p.x, p.y + r + 9);
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')
      .onAreaChange((oldVal: Area, newVal: Area) => {
        const w = Number(newVal.width);
        const h = Number(newVal.height);
        if (w > 0 && h > 0 && (Math.abs(w - this.w) > 4 || Math.abs(h - this.h) > 4)) {
          this.w = w;
          this.h = h;
          this.layout(w, h);
        }
      })
      .onReady(() => {
        this.layout(this.w, this.h);
        this.draw();
      })
      .onTouch((e: TouchEvent) => {
        if (e.touches.length === 0 || e.type !== TouchType.Down) {
          return;
        }
        const tx = e.touches[0].x;
        const ty = e.touches[0].y;
        let best = '';
        let bestD = 1e9;
        this.pos.forEach((p: Pt, id: string) => {
          const d = (p.x - tx) * (p.x - tx) + (p.y - ty) * (p.y - ty);
          if (d < bestD) {
            bestD = d;
            best = id;
          }
        });
        if (bestD < 900 && best) {
          this.onSelect(best);
        }
      });
  }
}
