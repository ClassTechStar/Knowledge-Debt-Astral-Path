/**
 * DEFLATE 原始解压（RFC 1951）—— PDF 的 FlateDecode 流就是这个格式，
 * 不带 zlib 头也不带 Adler32 尾，@ohos.zlib 只认 gzip 文件，用不上。
 *
 * 这里纯 ArkTS 实现（固定/动态哈夫曼 + 未压缩块），用于把 PDF 内容流解出来。
 * 与 DocService 配合：解出字节 → 再从 Tj/TJ 算子里取文本。
 */

interface Huff {
  counts: number[];
  symbols: number[];
}

/** 动态块两张表 */
interface HuffTables {
  lit: Huff;
  dist: Huff;
}

export class Inflate {
  private data: Uint8Array = new Uint8Array(0);
  private pos: number = 0;
  private bitBuf: number = 0;
  private bitCnt: number = 0;
  private out: Uint8Array = new Uint8Array(0);
  private outLen: number = 0;

  /**
   * 解压一段 deflate 数据。PDF 流有两种形态都要支持：
   * - 裸 deflate（无头，RFC 1951）
   * - zlib 包裹（2 字节头 + deflate + 4 字节 Adler32，RFC 1950）
   * 先按裸 deflate 试，失败再跳过 2 字节 zlib 头重试。
   * 这比「只做头检测」稳：有些 zlib 变种的头不一定能被 FCHECK 识别出来。
   */
  static raw(data: Uint8Array): Uint8Array {
    // 先按 RFC 1950 规则判 zlib 头：CM=8、CINFO<=7、FCHECK 整除 31、无 FDICT。
    // 注意 CINFO 不一定是 7（0x78），教材 PDF 里常见 0x68（CINFO=6，8KB 窗口）——
    // 早期只认 0x78~0x7f，导致 990 个流全部解不出（实测踩过）。
    const off = Inflate.zlibHeaderLen(data);
    if (off === 2) {
      try {
        return Inflate.inflateFrom(data, 2);
      } catch (e1) {
        // 头看着像 zlib 但解不动，退回裸 deflate 再试一次
        return Inflate.inflateFrom(data, 0);
      }
    }
    try {
      return Inflate.inflateFrom(data, 0);
    } catch (e2) {
      // 裸 deflate 失败，再看是不是漏判的 zlib 头
      if (data.length > 2) {
        return Inflate.inflateFrom(data, 2);
      }
      throw new Error(`inflate: cannot decompress (${(e2 as Error).message})`);
    }
  }

  /** 返回 zlib 头长度（2 或 0） */
  private static zlibHeaderLen(d: Uint8Array): number {
    if (d.length <= 2) {
      return 0;
    }
    const cmf = d[0];
    const flg = d[1];
    const cm = cmf & 0x0f;
    const cinfo = cmf >> 4;
    if (cm !== 8 || cinfo > 7) {
      return 0;
    }
    if (((cmf << 8) + flg) % 31 !== 0) {
      return 0;
    }
    if ((flg & 0x20) !== 0) {
      return 0; // 有预置字典，不支持
    }
    return 2;
  }

  private static inflateFrom(data: Uint8Array, offset: number): Uint8Array {
    const z = new Inflate();
    z.data = data.subarray(offset);
    z.pos = 0;
    z.bitBuf = 0;
    z.bitCnt = 0;
    z.out = new Uint8Array(Math.max(64, data.length * 4 + 64));
    z.outLen = 0;
    z.run();
    return z.out.subarray(0, z.outLen);
  }

  private run(): void {
    // 保险丝：畸形流最多解 64MB / 200 万轮，防止挂死 UI 线程
    let guard = 0;
    for (;;) {
      guard += 1;
      if (guard > 2000000 || this.outLen > 64 * 1024 * 1024) {
        throw new Error('inflate: guard tripped');
      }
      const final = this.bits(1);
      const type = this.bits(2);
      if (type === 0) {
        this.blockStored();
      } else if (type === 1) {
        this.blockHuffman(this.fixedLit(), this.fixedDist());
      } else if (type === 2) {
        const h = this.dynamicTables();
        this.blockHuffman(h.lit, h.dist);
      } else {
        throw new Error('bad deflate block type');
      }
      if (final) {
        return;
      }
    }
  }

  private bits(n: number): number {
    while (this.bitCnt < n) {
      if (this.pos >= this.data.length) {
        throw new Error('inflate: out of input');
      }
      this.bitBuf |= this.data[this.pos] << this.bitCnt;
      this.pos += 1;
      this.bitCnt += 8;
    }
    const v = this.bitBuf & ((1 << n) - 1);
    this.bitBuf >>>= n;
    this.bitCnt -= n;
    return v;
  }

  private blockStored(): void {
    this.bitBuf = 0;
    this.bitCnt = 0;
    if (this.pos + 4 > this.data.length) {
      throw new Error('inflate: truncated stored block');
    }
    const len = this.data[this.pos] | (this.data[this.pos + 1] << 8);
    this.pos += 4; // len + ~len
    for (let i = 0; i < len; i++) {
      this.emit(this.data[this.pos + i]);
    }
    this.pos += len;
  }

  private blockHuffman(lit: Huff, dist: Huff): void {
    for (;;) {
      const sym = this.decode(lit);
      if (sym < 256) {
        this.emit(sym);
      } else if (sym === 256) {
        return;
      } else {
        const idx = sym - 257;
        const len = LEN_BASE[idx] + this.bits(LEN_EXTRA[idx]);
        const dsym = this.decode(dist);
        const d = DIST_BASE[dsym] + this.bits(DIST_EXTRA[dsym]);
        if (d <= 0 || d > this.outLen) {
          // 距离越过已输出的起点：流已损坏，必须报错而不是默默补 0
          throw new Error('inflate: distance too far back');
        }
        let src = this.outLen - d;
        for (let i = 0; i < len; i++) {
          this.emit(this.out[src + i]);
        }
      }
    }
  }

  private decode(h: Huff): number {
    let code = 0;
    let first = 0;
    let index = 0;
    for (let l = 1; l <= 15; l++) {
      code |= this.bits(1);
      const count = h.counts[l];
      if (code - first < count) {
        return h.symbols[index + (code - first)];
      }
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    throw new Error('inflate: bad huffman code');
  }

  private dynamicTables(): HuffTables {
    const hlit = this.bits(5) + 257;
    const hdist = this.bits(5) + 1;
    const hclen = this.bits(4) + 4;
    const order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
    const lens: number[] = [];
    for (let i = 0; i < 19; i++) {
      lens[i] = 0;
    }
    for (let i = 0; i < hclen; i++) {
      lens[order[i]] = this.bits(3);
    }
    const cl = this.build(lens);
    const all: number[] = [];
    while (all.length < hlit + hdist) {
      const s = this.decode(cl);
      if (s < 16) {
        all.push(s);
      } else if (s === 16) {
        const n = 3 + this.bits(2);
        const v = all[all.length - 1];
        for (let i = 0; i < n; i++) {
          all.push(v);
        }
      } else if (s === 17) {
        const n = 3 + this.bits(3);
        for (let i = 0; i < n; i++) {
          all.push(0);
        }
      } else {
        const n = 11 + this.bits(7);
        for (let i = 0; i < n; i++) {
          all.push(0);
        }
      }
    }
    const out: HuffTables = {
      lit: this.build(all.slice(0, hlit)),
      dist: this.build(all.slice(hlit))
    };
    return out;
  }

  private fixedLit(): Huff {
    const lens: number[] = [];
    for (let i = 0; i < 288; i++) {
      lens[i] = i <= 143 ? 8 : (i <= 255 ? 9 : (i <= 279 ? 7 : 8));
    }
    return this.build(lens);
  }

  private fixedDist(): Huff {
    const lens: number[] = [];
    for (let i = 0; i < 30; i++) {
      lens[i] = 5;
    }
    return this.build(lens);
  }

  /** 由码长表建哈夫曼表 */
  private build(lengths: number[]): Huff {
    const counts: number[] = [];
    for (let i = 0; i <= 15; i++) {
      counts[i] = 0;
    }
    for (const l of lengths) {
      counts[l] += 1;
    }
    counts[0] = 0;
    const offs: number[] = [];
    let total = 0;
    for (let l = 1; l <= 15; l++) {
      offs[l] = total;
      total += counts[l];
    }
    const symbols: number[] = [];
    for (let s = 0; s < lengths.length; s++) {
      const l = lengths[s];
      if (l > 0) {
        symbols[offs[l]] = s;
        offs[l] += 1;
      }
    }
    const h: Huff = { counts: counts, symbols: symbols };
    return h;
  }

  private emit(b: number): void {
    if (this.outLen >= this.out.length) {
      const grow = new Uint8Array(this.out.length * 2);
      grow.set(this.out);
      this.out = grow;
    }
    this.out[this.outLen] = b & 0xff;
    this.outLen += 1;
  }
}

const LEN_BASE: number[] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
];
const LEN_EXTRA: number[] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
];
const DIST_BASE: number[] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
];
const DIST_EXTRA: number[] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
];
