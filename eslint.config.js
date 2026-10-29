// ESLint 配置（flat config）
// 范围：前端共享代码与门禁脚本（shared/、scripts/、tools/、e2e/、根级配置）。
// 选型说明：
//   - 只开「会导致真 bug」的规则（未定义变量、重复声明、不可达代码等），
//     不开风格类规则，避免把行文格式当门禁；
//   - sourceType 用 script：shared/*.js 是 UMD 脚本（浏览器与 Node 双端），
//     按 ESM 解析会误报；
//   - 浏览器与 Node 全局按实际使用白名单给出。
module.exports = [
  {
    ignores: [
      "node_modules/**",
      "artifacts/**",
      "attic/**",
      // 第三方压缩产物与随包运行时（不属本仓库代码，不做 lint）
      "**/ort-runtime/**",
      "**/ocr-engine/**",
      // 构建输出与部署副本
      ".cloudflare/**",
      "release/**",
      "deploy/monolith-web/astralpath-monolith.html",
      "src/**/wwwroot/**",
      "src/**/Resources/**",
      "src/**/assets/**",
      "materials/**",
      // 鸿蒙工程是 ArkTS（.ets），规范由 codelinter 管；这里的 oh_modules/build
      // 是 ohpm 依赖与产物，当成 JS 扫会刷出一堆 "import 只能出现在 module" 的假错
      "src/AstralPath.Harmony/**",
    ],
  },
  {
    files: ["**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script",
      globals: {
        // 浏览器
        window: "readonly",
        document: "readonly",
        self: "readonly",
        navigator: "readonly",
        location: "readonly",
        history: "readonly",
        localStorage: "readonly",
        sessionStorage: "readonly",
        indexedDB: "readonly",
        console: "readonly",
        fetch: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
        setInterval: "readonly",
        clearInterval: "readonly",
        requestAnimationFrame: "readonly",
        URL: "readonly",
        URLSearchParams: "readonly",
        Blob: "readonly",
        FileReader: "readonly",
        File: "readonly",
        TextDecoder: "readonly",
        TextEncoder: "readonly",
        Uint8Array: "readonly",
        Float32Array: "readonly",
        Int32Array: "readonly",
        ArrayBuffer: "readonly",
        atob: "readonly",
        btoa: "readonly",
        performance: "readonly",
        crypto: "readonly",
        Image: "readonly",
        MutationObserver: "readonly",
        CustomEvent: "readonly",
        Event: "readonly",
        KeyboardEvent: "readonly",
        ResizeObserver: "readonly",
        HTMLElement: "readonly",
        HTMLCanvasElement: "readonly",
        ImageData: "readonly",
        DecompressionStream: "readonly",
        Response: "readonly",
        Request: "readonly",
        Headers: "readonly",
        AbortController: "readonly",
        WebAssembly: "readonly",
        XMLHttpRequest: "readonly",
        Worker: "readonly",
        Path2D: "readonly",
        getComputedStyle: "readonly",
        matchMedia: "readonly",
        globalThis: "readonly",
        structuredClone: "readonly",
        OffscreenCanvas: "readonly",
        CryptoKey: "readonly",
        // Node（门禁脚本）
        require: "readonly",
        module: "writable",
        exports: "writable",
        process: "readonly",
        __dirname: "readonly",
        __filename: "readonly",
        Buffer: "readonly",
      },
    },
    rules: {
      "no-undef": "error",
      "no-redeclare": "error",
      "no-dupe-keys": "error",
      "no-dupe-class-members": "error",
      "no-unreachable": "error",
      "no-const-assign": "error",
      "no-self-compare": "error",
      "no-sparse-arrays": "error",
      "no-dupe-else-if": "error",
      "no-duplicate-case": "error",
      "no-fallthrough": "error",
      "no-unused-vars": ["warn", { args: "none", varsIgnorePattern: "^_", caughtErrors: "none" }],
      "no-empty": ["warn", { allowEmptyCatch: true }],
    },
  },
  // 集成脚本：注入 .cloudflare/pages/index.html 尾部运行，依赖页面上的全局对象。
  // 这些符号由页面内联脚本定义，无法在此逐个枚举且会随页面演进漂移，故关闭 no-undef；
  // 重复声明等真实缺陷规则仍保留。
  {
    files: ["shared/integrations/**/*.js"],
    rules: {
      "no-undef": "off",
    },
  },
  // 页面装配层：app-glue.js 直接操作页面里的全局（S/save/renderToday 等），
  // 它自己不是模块，靠 index.html 的作用域运行。
  {
    files: ["shared/app-glue.js"],
    languageOptions: {
      globals: {
        S: "readonly", save: "readonly", renderToday: "readonly",
        renderGraph: "readonly", renderDebts: "readonly", renderProfile: "readonly",
        APStore: "readonly", APNotify: "readonly", APRuntime: "readonly",
        activeBook: "readonly", activeNodes: "readonly", activeQs: "readonly",
        esc: "readonly", toast: "readonly", scoreOf: "readonly", K: "readonly",
      },
    },
  },
];
