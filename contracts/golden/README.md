# golden · 契约金样

本目录只放**有唯一消费方**的契约资产：

| 文件 | 消费方 | 说明 |
|---|---|---|
| `xss-cases.json` | `scripts/verify_xss.py` | XSS 黄金用例（14 例） |
| `redteam-cases.json` | `scripts/redteam_runner.js` | 红队对抗语料（由 `tools/gen_redteam_corpus.py` 生成，536 条） |
| `ocr/samples.json` | `scripts/ocr_quality.py` | OCR 金样清单 |

> 公式金样（score / impact / sale / plan_k / narrative）统一放在 `eval/golden/`：
> `GoldenSampleTests.cs` 与 `verify_formulas.py` 只读那一份，避免两处副本漂移。
> v2 公式的跨语言对拍见 `eval/golden/formula-cross.json`（C# ↔ JS 双跑）。
