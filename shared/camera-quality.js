/**
 * camera-quality.js —— 实时拍照的清晰度选帧（借鉴 OCR 优化方案「连拍 3 帧选最清晰」）。
 * ===========================================================
 * 为什么放在 shared/ 生成区：页面手写内联 JS 有棘轮上限，且这段是可独立测试的纯逻辑。
 *
 * 机制：
 *   - Laplacian 方差作为清晰度指标（对焦越实，高频能量越强）；
 *   - 先降采样到 320px 宽再评分，避免大 canvas 逐像素造成抓拍卡顿；
 *   - 连抓 N 帧，取评分最高的一帧送 OCR——成本极低（几帧 canvas 拷贝），
 *     却是拍照场景里最划算的质量提升（比换模型便宜得多）。
 *
 * 边界（诚实）：
 *   - 清晰度只能筛掉「糊」的帧，不能纠正斜拍透视、卷面弯曲与反光；
 *     那三类需要几何矫正与光照归一化，属于后续独立改造。
 *   - 评分对纯色/极低纹理页面会偏低，属预期行为（这类页面本来也不适合 OCR）。
 *
 * 环境：浏览器 window.APCameraQuality；Node require() 可测 qualityHint 等纯函数。
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.APCameraQuality = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  /** 从 canvas 计算 Laplacian 方差；scoreCanvas 可注入以便 Node 测试。 */
  function sharpness(canvas, sampleW) {
    if (!canvas || !canvas.width || !canvas.height) return 0;
    var w = Math.max(16, Math.min(sampleW || 320, canvas.width));
    var h = Math.max(16, Math.round(canvas.height * w / canvas.width));
    var c = (typeof document !== "undefined") ? document.createElement("canvas") : null;
    if (!c) return 0;
    c.width = w; c.height = h;
    var ctx = c.getContext("2d", { willReadFrequently: true });
    if (!ctx) return 0;
    try { ctx.drawImage(canvas, 0, 0, w, h); } catch (e) { return 0; }
    var d;
    try { d = ctx.getImageData(0, 0, w, h).data; } catch (e) { return 0; }
    var n = w * h, gray = new Float32Array(n);
    for (var i = 0; i < n; i++) {
      gray[i] = 0.299 * d[i * 4] + 0.587 * d[i * 4 + 1] + 0.114 * d[i * 4 + 2];
    }
    var sum = 0, sum2 = 0, cnt = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        var p = y * w + x;
        var lap = 4 * gray[p] - gray[p - 1] - gray[p + 1] - gray[p - w] - gray[p + w];
        sum += lap; sum2 += lap * lap; cnt++;
      }
    }
    if (!cnt) return 0;
    var mean = sum / cnt;
    return Math.max(0, sum2 / cnt - mean * mean);
  }

  /**
   * 连拍 N 帧，返回清晰度最高的一帧。
   * @param {HTMLVideoElement} video 已 play 的相机视频
   * @param {{frames?:number, delayMs?:number, maxSide?:number}} opts
   * @returns {Promise<{canvas:HTMLCanvasElement, score:number, taken:number}>}
   */
  async function captureBestFrame(video, opts) {
    opts = opts || {};
    var frames = Math.max(1, Math.min(5, opts.frames || 3));
    var delay = Math.max(0, Math.min(500, opts.delayMs == null ? 120 : opts.delayMs));
    var maxSide = Math.max(640, Math.min(4096, opts.maxSide || 2560));
    var best = null, bestScore = -1, taken = 0;
    for (var i = 0; i < frames; i++) {
      if (!video || !video.videoWidth || !video.videoHeight) throw new Error("相机未就绪");
      var scale = Math.min(1, maxSide / Math.max(video.videoWidth, video.videoHeight));
      var c = document.createElement("canvas");
      c.width = Math.max(1, Math.round(video.videoWidth * scale));
      c.height = Math.max(1, Math.round(video.videoHeight * scale));
      var ctx = c.getContext("2d", { alpha: false });
      if (!ctx) throw new Error("画布不可用");
      ctx.drawImage(video, 0, 0, c.width, c.height);
      var s = sharpness(c);
      taken++;
      if (s > bestScore) { bestScore = s; best = c; }
      if (i < frames - 1) await new Promise(function (r) { setTimeout(r, delay); });
    }
    return { canvas: best, score: bestScore, taken: taken };
  }

  /** 把清晰度分数翻译成用户提示；阈值由经验给出，不是精确物理量。 */
  function qualityHint(score) {
    if (!score || score < 40) return "画面较糊，建议对焦后重拍";
    if (score < 120) return "清晰度一般，可尝试靠近试卷";
    return "清晰度良好";
  }

  return {
    sharpness: sharpness,
    captureBestFrame: captureBestFrame,
    qualityHint: qualityHint
  };
});
