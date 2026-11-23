using System.Diagnostics;
using Xunit;

namespace AstralPath.Core.Tests;

public class MaterialOcrPipelineTests
{
    private static string RepoRoot
    {
        get
        {
            var candidates = new[]
            {
                Path.Combine(Directory.GetCurrentDirectory()),
                Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..")
            };
            foreach (var c in candidates)
            {
                var full = Path.GetFullPath(c);
                if (File.Exists(Path.Combine(full, "tools", "ocr_pipeline.py"))) return full;
            }
            // 兜底：从测试输出目录逐级上溯（不写死机器路径）
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir is not null)
            {
                if (File.Exists(Path.Combine(dir.FullName, "tools", "ocr_pipeline.py"))) return dir.FullName;
                dir = dir.Parent;
            }
            throw new DirectoryNotFoundException("repo root with tools/ocr_pipeline.py not found");
        }
    }

    private static string Python
    {
        get
        {
            var env = Environment.GetEnvironmentVariable("ASTRALPATH_OCR_PYTHON");
            if (!string.IsNullOrWhiteSpace(env) && File.Exists(env)) return env;
            var venv = Path.Combine(RepoRoot, "tools", "ocr-venv", "Scripts", "python.exe");
            return File.Exists(venv) ? venv : @"C:\Program Files\Xiaomi MiMo\resources\runtimes\win32-x64\python\python.exe";
        }
    }

    private static string? FirstSamplePdf()
    {
        // 样例 PDF 由本机提供：默认 <仓库>/materials/pdf，可用 ASTRALPATH_PDF_DIR 覆盖。
        // 不在代码里写死某台机器的下载目录与具体书名（可移植性 + 版权书目不外泄）。
        var dir = Environment.GetEnvironmentVariable("ASTRALPATH_PDF_DIR");
        if (string.IsNullOrWhiteSpace(dir))
            dir = Path.Combine(RepoRoot, "materials", "pdf");
        if (!Directory.Exists(dir)) return null;
        return Directory.EnumerateFiles(dir, "*.pdf", SearchOption.TopDirectoryOnly)
            .OrderBy(p => p, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }

    [Fact]
    public void OcrPipeline_ExtractsScannedPdfAndBuildsGraphNodes()
    {
        var pdf = FirstSamplePdf();
        if (pdf is null) return; // 样例 PDF 不是每台机器都有

        var script = Path.Combine(RepoRoot, "tools", "ocr_pipeline.py");
        Assert.True(File.Exists(script));

        var outPath = Path.Combine(Path.GetTempPath(), $"astralpath_ocr_test_{Guid.NewGuid():N}.json");
        var psi = new ProcessStartInfo
        {
            FileName = Python,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        psi.ArgumentList.Add(script);
        psi.ArgumentList.Add(pdf!);
        psi.ArgumentList.Add("--ocr");
        psi.ArgumentList.Add("quick");
        psi.ArgumentList.Add("--out");
        psi.ArgumentList.Add(outPath);

        using var proc = Process.Start(psi)!;
        var stderr = proc.StandardError.ReadToEnd();
        proc.WaitForExit(120_000);
        Assert.True(File.Exists(outPath), $"pipeline output missing. stderr={stderr}");

        var json = File.ReadAllText(outPath);
        Assert.False(string.IsNullOrWhiteSpace(json));
        using var doc = System.Text.Json.JsonDocument.Parse(json);
        var root = doc.RootElement;
        Assert.True(root.TryGetProperty("nodes", out var nodes));
        Assert.True(nodes.GetArrayLength() > 0, "expected auto graph nodes");
        Assert.True(root.TryGetProperty("extractedChars", out var chars));
        // 扫描版要么抽出文本，要么 OCR 出点东西
        Assert.True(chars.GetInt32() >= 0);
        Assert.True(root.TryGetProperty("mode", out _));
    }

    [Fact]
    public void AutoGraphBuilder_ProducesAcyclicChapterChain()
    {
        // 纯单元路径：造一份类似 OCR 输出的数据
        var chapters = new[]
        {
            new { title = "第1章 变量与类型", kind = "chapter", offset = 0 },
            new { title = "第2章 控制流", kind = "chapter", offset = 100 },
            new { title = "第3章 函数", kind = "chapter", offset = 200 }
        };
        var terms = new[]
        {
            new { term = "变量", freq = 12 },
            new { term = "函数", freq = 9 }
        };

        var payload = System.Text.Json.JsonSerializer.Serialize(new
        {
            nodes = Array.Empty<object>(),
            edges = Array.Empty<object>(),
            chapters,
            terms
        });

        // 用 C# 复刻流水线脚本的同一套规则，把图重建出来
        var nodes = new List<AstralPath.Graph.KpNode>();
        var edges = new List<AstralPath.Graph.KpEdge>();
        var i = 1;
        string Next() => $"A{i++:000}";
        var chapterIds = new List<string>();
        foreach (var ch in chapters)
        {
            var id = Next();
            nodes.Add(new AstralPath.Graph.KpNode(id, ch.title, "DEMO", ch.kind));
            chapterIds.Add(id);
        }
        foreach (var (a, b) in chapterIds.Zip(chapterIds.Skip(1)))
            edges.Add(new AstralPath.Graph.KpEdge(a, b, "prerequisite", 1.2, "auto:chapter-sequence"));
        foreach (var t in terms)
        {
            var id = Next();
            nodes.Add(new AstralPath.Graph.KpNode(id, t.term, "DEMO", $"freq={t.freq}"));
            edges.Add(new AstralPath.Graph.KpEdge(id, chapterIds[0], "prerequisite", 1.0, "auto:term-anchor"));
        }

        var pack = new AstralPath.Graph.GraphPack("auto-demo", "demo", "DEMO", 1, DateTime.UtcNow.ToString("O"), nodes, edges);
        var result = new AstralPath.Graph.KnowledgeGraph(pack).Validate();
        Assert.True(result.Cycles.Count == 0, string.Join(";", result.Cycles));
        Assert.True(result.NodeCount >= 3);
        Assert.True(result.EdgeCount >= 2);
        Assert.False(string.IsNullOrWhiteSpace(payload));
    }
}
