using System.Diagnostics;
using AstralPath.Core.Diagnostics;
using System.Text.Json;
using System.Threading;
using AstralPath.Infrastructure;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace AstralPath.Monolith;

/// <summary>
/// 知债：星穹学途 · 单体版 Windows 壳（无微服务、无本地 HTTP）。
/// 直接以虚拟域加载同目录 Resources\index.html，全部业务在页面内完成。
/// 页面文本层解析失败/乱码时，通过 postMessage 桥请求本壳执行 OCR
/// （tools\ocr_pipeline.py + tesseract，均为本机文件，无网络、无端口）。
///
/// 可靠性：单实例互斥 + 二次启动唤起已有窗口；启动失败计数，连续失败进恢复模式；
/// 托盘常驻（今日剩余徽章 / 勿扰开关 / 数据目录）；点关闭最小化到托盘，托盘菜单才真正退出。
/// </summary>
internal static class Program
{
    internal const string MutexName = @"Global\AstralPath.Monolith.SingleInstance";
    internal const string ShowEventName = "AstralPath.Monolith.ShowFirst";
    internal static bool ClearCacheOnBoot;

    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.ThreadException += (_, e) => BumpFailCount(e.Exception, "ThreadException");
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            if (e.ExceptionObject is Exception ex) BumpFailCount(ex, "UnhandledException");
        };

        using var mutex = new Mutex(true, MutexName, out var createdNew);
        if (!createdNew)
        {
            // 已有实例在跑：发信号唤起它的窗口后退出
            try
            {
                using var evt = EventWaitHandle.OpenExisting(ShowEventName);
                evt.Set();
            }
            catch (Exception ex) { Diag.Recover(ex, "Program"); }
            return;
        }

        if (ReadFailCount() >= 3)
        {
            var choice = MessageBox.Show(
                "检测到程序连续多次启动失败。\n\n" +
                "「是」——清零计数并正常启动；\n" +
                "「否」——打开数据目录（可手动备份/删除数据）；\n" +
                "「取消」——清理界面缓存后启动（学习进度数据在浏览器存储，不受影响）。",
                "知债：星穹学途 · 恢复模式",
                MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
            if (choice == DialogResult.No)
            {
                try { Process.Start("explorer.exe", GetDataDir()); } catch (Exception ex) { Diag.Recover(ex, "Program"); }
                return;
            }
            if (choice == DialogResult.Cancel) ClearCacheOnBoot = true;
        }
        WriteFailCount(0);

        using var showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        var form = new MainForm();
        var waiter = ThreadPool.RegisterWaitForSingleObject(
            showEvent, (_, _) => form.BeginInvoke(new Action(form.ShowFromSecondInstance)),
            null, -1, executeOnlyOnce: false);
        Application.Run(form);
        waiter.Unregister(null);
    }

    internal static string GetDataDir() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AstralPath.Monolith");

    private static string CountFile() => Path.Combine(GetDataDir(), "startup-count");

    private static int ReadFailCount()
    {
        try { return int.TryParse(File.ReadAllText(CountFile()).Trim(), out var n) ? n : 0; }
        catch { return 0; }
    }

    private static void WriteFailCount(int n)
    {
        try { Directory.CreateDirectory(GetDataDir()); File.WriteAllText(CountFile(), n.ToString()); }
        catch (Exception ex) { Diag.Recover(ex, "Program"); }
    }

    internal static void BumpFailCount(Exception ex, string source)
    {
        Diag.Recover(ex, source);
        try { WriteFailCount(Math.Min(ReadFailCount() + 1, 99)); }
        catch (Exception ex2) { Diag.Recover(ex2, "BumpFailCount"); }
    }
}

internal sealed class MainForm : Form
{
    private readonly WebView2 _web = new() { Dock = DockStyle.Fill };
    private NotifyIcon? _tray;
    private bool _reallyExit;
    private bool _hideTipShown;
    private ToolStripMenuItem? _menuDnd;
    private System.Windows.Forms.Timer? _badgeTimer;
    private int _lastRemaining = -1;

    public MainForm()
    {
        Text = "知债：星穹学途";
        Width = 1280;
        Height = 840;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(960, 640);
        KeyPreview = true;
        KeyDown += OnKeyDown;
        try
        {
            var ico = Path.Combine(AppContext.BaseDirectory, "Resources", "astralpath-icon.ico");
            if (File.Exists(ico)) Icon = new Icon(ico);
        }
        catch (Exception ex)
        {
            Diag.Recover(ex, "Program");
        }

        Controls.Add(_web);
        Shown += async (_, _) => await BootAsync();
        FormClosing += OnFormClosing;
    }

    internal void ShowFromSecondInstance()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.KeyCode != Keys.F11) return;
        if (FormBorderStyle == FormBorderStyle.None)
        {
            FormBorderStyle = FormBorderStyle.Sizable;
            WindowState = FormWindowState.Normal;
        }
        else
        {
            FormBorderStyle = FormBorderStyle.None;
            WindowState = FormWindowState.Maximized;
        }
        e.Handled = true;
    }

    private async Task BootAsync()
    {
        try
        {
            var html = Path.Combine(AppContext.BaseDirectory, "Resources", "index.html");
            if (!File.Exists(html))
            {
                MessageBox.Show(this, "缺少 Resources\\index.html，请重新安装完整组件。", "知债：星穹学途",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            var webViewDir = Path.Combine(Program.GetDataDir(), "WebView2");
            if (Program.ClearCacheOnBoot && Directory.Exists(webViewDir))
            {
                try { Directory.Delete(webViewDir, recursive: true); }
                catch (Exception ex) { Diag.Recover(ex, "Program"); }
            }

            var env = await CoreWebView2Environment.CreateAsync(userDataFolder: webViewDir);
            await _web.EnsureCoreWebView2Async(env);
            _web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;
            _web.CoreWebView2.Settings.IsStatusBarEnabled = false;
            _web.CoreWebView2.Settings.AreDevToolsEnabled = true;
            // ★ OCR 宿主桥：页面 postMessage({type:"astralpath.ocr",...}) → 本壳跑管线 → 回传文本
            _web.CoreWebView2.WebMessageReceived += OnWebMessage;
            // 页面加载完成即视为启动成功：清零失败计数
            _web.CoreWebView2.NavigationCompleted += (_, _) =>
            {
                try { File.WriteAllText(Path.Combine(Program.GetDataDir(), "startup-count"), "0"); }
                catch (Exception ex) { Diag.Recover(ex, "Program"); }
            };
            // 本地单体：禁止页面再依赖远程 API；脚本即全部能力
            // 虚拟域映射：file:// 下 Chromium 禁 Worker/fetch 本地资源，
            // pdf.js worker 与 WASM OCR 引擎全部失效 → 文本层回退裸解析器 → 乱码被当成功接受。
            // 映射 https://appassets.local → 应用根目录后，worker/WASM 与宿主桥(postMessage)均可用。
            var appRoot = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            _web.CoreWebView2.SetVirtualHostNameToFolderMapping(
                "appassets.local", appRoot, CoreWebView2HostResourceAccessKind.Allow);
            _web.CoreWebView2.Navigate("https://appassets.local/Resources/index.html");
            InitTray();
            StartBadgeTimer();
        }
        catch (Exception ex)
        {
            Program.BumpFailCount(ex, "BootAsync");
            MessageBox.Show(this, "启动失败：" + ex.Message, "知债：星穹学途",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /* ── 托盘：常驻入口 + 今日剩余徽章 + 勿扰开关 ── */

    private Icon? BadgeIcon(int remaining)
    {
        try
        {
            using var bmp = new Bitmap(32, 32);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                using var bg = new SolidBrush(remaining == 0 ? Color.FromArgb(46, 160, 90) : Color.FromArgb(47, 111, 237));
                g.FillEllipse(bg, 1, 1, 30, 30);
                var text = remaining > 9 ? "9+" : remaining.ToString();
                using var f = new Font("Segoe UI", remaining > 9 ? 11f : 14f, FontStyle.Bold, GraphicsUnit.Pixel);
                var sz = g.MeasureString(text, f);
                using var white = new SolidBrush(Color.White);
                g.DrawString(text, f, white, (32 - sz.Width) / 2f, (32 - sz.Height) / 2f + 1);
            }
            return Icon.FromHandle(bmp.GetHicon());
        }
        catch (Exception ex)
        {
            Diag.Recover(ex, "BadgeIcon");
            return null;
        }
    }

    private void InitTray()
    {
        try
        {
            var menu = new ContextMenuStrip();
            menu.Items.Add("打开主窗口", null, (_, _) => ShowFromSecondInstance());
            _menuDnd = new ToolStripMenuItem("免打扰（演示模式）");
            _menuDnd.Click += async (_, _) =>
            {
                try
                {
                    var r = await _web.CoreWebView2.ExecuteScriptAsync(
                        "window.__APShell&&window.__APShell.toggleDnd?window.__APShell.toggleDnd():false");
                    _menuDnd.Checked = r.Trim('"') == "true";
                }
                catch (Exception ex) { Diag.Recover(ex, "TrayDnd"); }
            };
            menu.Items.Add(_menuDnd);
            menu.Items.Add("全屏 / 退出全屏（F11）", null, (_, _) => OnKeyDown(this, new KeyEventArgs(Keys.F11)));
            menu.Items.Add("打开数据目录", null, (_, _) =>
            {
                try { Process.Start("explorer.exe", Program.GetDataDir()); }
                catch (Exception ex) { Diag.Recover(ex, "TrayOpenData"); }
            });
            menu.Items.Add("退出", null, (_, _) => { _reallyExit = true; Close(); });
            _tray = new NotifyIcon
            {
                Text = "知债：星穹学途",
                ContextMenuStrip = menu,
                Visible = true,
            };
            var ico = Path.Combine(AppContext.BaseDirectory, "Resources", "astralpath-icon.ico");
            if (File.Exists(ico)) _tray.Icon = new Icon(ico);
            _tray.DoubleClick += (_, _) => ShowFromSecondInstance();
        }
        catch (Exception ex)
        {
            Diag.Recover(ex, "InitTray");
        }
    }

    private void StartBadgeTimer()
    {
        _badgeTimer = new System.Windows.Forms.Timer { Interval = 60_000 };
        _badgeTimer.Tick += async (_, _) => await RefreshBadgeAsync();
        _badgeTimer.Start();
        _ = RefreshBadgeAsync();
    }

    private async Task RefreshBadgeAsync()
    {
        try
        {
            var raw = await _web.CoreWebView2.ExecuteScriptAsync(
                "window.__APShell&&window.__APShell.todayRemaining?window.__APShell.todayRemaining():-1");
            if (!int.TryParse(raw.Trim().Trim('"'), out var n)) return;
            if (n == _lastRemaining || _tray == null) return;
            _lastRemaining = n;
            var made = BadgeIcon(Math.Max(0, n));
            if (made != null)
            {
                var old = _tray.Icon;
                _tray.Icon = made;
                _tray.Text = n == 0 ? "知债：星穹学途 · 今日任务已完成" : $"知债：星穹学途 · 今日还剩 {n} 个任务";
                try { old?.Dispose(); } catch (Exception ex) { Diag.Recover(ex, "RefreshBadge"); }
            }
        }
        catch (Exception ex)
        {
            Diag.Recover(ex, "RefreshBadge");
        }
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (_reallyExit || e.CloseReason != CloseReason.UserClosing) return;
        // 点关闭 = 最小化到托盘；真正退出走托盘菜单
        e.Cancel = true;
        Hide();
        if (!_hideTipShown && _tray != null)
        {
            _hideTipShown = true;
            _tray.ShowBalloonTip(2500, "知债：星穹学途", "已最小化到托盘，双击托盘图标可再次打开；右键托盘可选「退出」。", ToolTipIcon.Info);
        }
    }

    // OCR 宿主桥
    private static readonly JsonSerializerOptions JsonOpts = new(JsonSerializerDefaults.Web);

    private sealed record OcrRequest(string? Type, string? Id, string? Name, string? Mode, string? Pages, string? Data);

    private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        OcrRequest? req;
        try { req = JsonSerializer.Deserialize<OcrRequest>(e.WebMessageAsJson, JsonOpts); }
        catch { return; } // 非 JSON 消息一律忽略
        if (req is { Type: "astralpath.cache.clear" } && !string.IsNullOrEmpty(req.Id))
        {
            var cid = req.Id!;
            _ = Task.Run(() =>
            {
                try { OcrHost.ClearOcrCache(); } catch (Exception ex)
                {
                    Diag.Recover(ex, "Program");
                }
                Reply(cid, "ok", "");
            });
            return;
        }
        if (req is not { Type: "astralpath.ocr" } || string.IsNullOrEmpty(req.Id) || string.IsNullOrEmpty(req.Data)) return;

        var id = req.Id;
        var name = string.IsNullOrWhiteSpace(req.Name) ? "material.pdf" : req.Name!;
        var mode = string.IsNullOrWhiteSpace(req.Mode) ? "standard" : req.Mode!;
        _ = Task.Run(() => RunOcrAndReplyAsync(id, name, mode, req.Pages, req.Data!));
    }

    private async Task RunOcrAndReplyAsync(string id, string name, string mode, string? pages, string base64)
    {
        string? text = null;
        var error = "";
        try
        {
            text = await OcrHost.RunAsync(name, mode, pages, base64, onProgress: line =>
            {
                // 把 PROGRESS 行边跑边回传页面，页面上的 OCR 进度就跟着动
                var payload = new Dictionary<string, object?>
                {
                    ["type"] = "astralpath.ocr.progress",
                    ["id"] = id,
                    ["message"] = line
                };
                var json = JsonSerializer.Serialize(payload, JsonOpts);
                void Post()
                {
                    try { _web.CoreWebView2?.PostWebMessageAsJson(json); }
                    catch (Exception ex)
                    {
                        Diag.Recover(ex, "Program");
                    }
                }
                if (InvokeRequired) BeginInvoke((Action)Post); else Post();
            });
        }
        catch (Exception ex) { error = ex.Message; }
        Reply(id, text, error);
    }

    private void Reply(string id, string? text, string error)
    {
        var payload = new Dictionary<string, object?>
        {
            ["type"] = "astralpath.ocr.result",
            ["id"] = id,
            ["ok"] = !string.IsNullOrEmpty(text),
            ["text"] = text,
            ["error"] = string.IsNullOrEmpty(text)
                ? (string.IsNullOrWhiteSpace(error) ? "OCR 未返回文本" : error)
                : null
        };
        var json = JsonSerializer.Serialize(payload, JsonOpts);
        void Post()
        {
            try { _web.CoreWebView2?.PostWebMessageAsJson(json); }
            catch (Exception ex)
            {
                Diag.Recover(ex, "Program");
            }
        }
        if (InvokeRequired) BeginInvoke((Action)Post); else Post();
    }
}
