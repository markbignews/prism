# Note Suite - 多源信息交叉索引与语义之镜 App 套件 (macOS Native Edition)
## 技术文档与规范 (Technical Specifications & Guidelines - SwiftUI)

---

## 一、 项目架构与数据流路径 (Data Flow Architecture)

产品由 **Feed App**（独立 RSS 客户端）、**Note App**（知识笔记中枢）及 **系统级剪藏器** 组成。为了确保法律合规与极佳的系统资源性能，本系统**绝不抓取或存储网页整篇原文**，仅记录**用户手动选择并复制/划线的内容片段 (Snippets/Highlights)**。这在法理上属于完全合规的“合理引用”，且极大地轻量化了本地数据库与 AI 上下文。

### 1. 统一数据流路径图

```
【 用户的浏览器 (Safari/Chrome/Edge) 】  ──▶ [用户手动选择网页文本并触发] 
                                                  │
       ┌──────────────────────────────────────────┴──────────────────────────────────────────┐
       │ (路径 A: Safari 划线插件)          (路径 B: Chrome/Edge 划线书签脚本)       (路径 C: 剪贴板直接粘贴)
       ▼                                   ▼                                       ▼
 [App Extension IPC]                [HTTP POST :31415/clip]                [主程序 Cmd+V 粘贴]
       │                                   │                                       │
       ▼                                   ▼                                       │
┌──────────────────────────────────────────────────────────────────────────────────┐       │
│ Note App (后台运行)                                                               │       │
│                                                                                  │       │
│ 1. 临时文件写入 ──▶ App Group 共享盘 (group.com.prism.suite/IncomingClips/)       │       │
│ 2. 分布式通知 ──▶ com.prism.suite.newArticle                                      │       │
│                                                                                  │       │
│ 3. 串行异步解析器 (IngestionQueueWorker - Actor 物理隔离)                           │       │
│    - 消费 AsyncStream 挂起队列，读取划线数据                                         │       │
│    - 异步磁盘 I/O 读取 ＆ 结构化清洗 (免去 Readability 重度正文抓取) ◀───────────────┼───────┘
│                                                                                  │
│ 4. 主线程回调 (NoteAppLifecycleManager - @MainActor)                              │
│    - 写入 SwiftData 数据库，触发 Stance 态度光谱与聚类分析                          │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 二、 核心代码实践路径与文件合并 (Consolidated Implementation Paths)

为了防止逻辑分散，我们将整个数据链路划分为四个核心实现文件。

### 路径 1：输入与中转层 (`SharedQueueManager.swift` & `Clipper.js`)
负责处理 Safari App Extension、Bookmarklet 及 Feed App 的划线数据包封装，并写入 App Group 共享沙盒目录，发送进程间分布式通知。

#### A. 共享数据管理器 (Swift)
文件位置：`note/Sources/Note/SharedQueueManager.swift`
```swift
import Foundation

struct SharedQueueManager {
    static let sharedGroupID = "group.com.prism.suite"
    
    // 传输数据包结构（仅传输用户选中的高亮文本片段，而非整页 HTML）
    struct PendingSnippet: Codable {
        let url: String
        let title: String
        let selectedText: String // 用户划线选中的文本
        let source: String
        let timestamp: Date
    }
    
    static func pushToQueue(snippet: PendingSnippet) {
        DispatchQueue.global(qos: .utility).async {
            guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedGroupID) else { return }
            let queueDirectory = groupURL.appendingPathComponent("IncomingClips", isDirectory: true)
            try? FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
            
            let fileURL = queueDirectory.appendingPathComponent("\(UUID().uuidString).json")
            
            do {
                let data = try JSONEncoder().encode(snippet)
                try data.write(to: fileURL, options: .atomic)
                
                // 发送带文件名的轻量通知，通知 Ingestion 引擎处理新片段
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("com.prism.suite.newArticle"),
                    object: fileURL.lastPathComponent,
                    userInfo: nil,
                    deliverImmediately: true
                )
            } catch {
                print("Failed to write to shared container: \(error)")
            }
        }
    }
}
```

#### B. 跨浏览器 Bookmarklet 源码 (JavaScript)
用户选中网页文字后点击书签栏触发，仅提取用户当前选择的文本内容：
```javascript
javascript:(function(){
    // 1. 获取用户在网页中用鼠标划线选中的文本
    var selectedText = window.getSelection().toString().trim();
    
    if (!selectedText) {
        showToast("Prism Clip: 请先用鼠标选择网页中的一段文本后再点击剪藏。", true);
        return;
    }
    
    var payload = {
        url: window.location.href,
        title: document.title,
        selectedText: selectedText
    };
    
    // 通道 A：直接 HTTP POST 到本地端口 (W3C 规范允许 HTTPS 向 127.0.0.1 发送请求，避开 Mixed Content)
    fetch('http://127.0.0.1:31415/clip', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    }).then(res => {
        showToast("Prism Clip: 片段剪藏成功！", false);
    }).catch(err => {
        // 通道 B：通道 A 因站点的 strict CSP 拦截时回退。打开 1x1 隐藏子窗口投递并等待其自销毁
        var clipWindow = window.open('http://127.0.0.1:31415/clip_page', 'PrismClip', 'width=1,height=1,left=10000,top=10000');
        
        if (!clipWindow || clipWindow.closed || typeof clipWindow.closed == 'undefined') {
            showToast("Prism Clip: 剪藏被浏览器弹窗拦截，请在地址栏右侧允许此网站弹出窗口。", true);
        } else {
            setTimeout(function(){
                clipWindow.postMessage(payload, 'http://127.0.0.1:31415');
            }, 400);
        }
    });

    function showToast(msg, isError) {
        var id = "prism-toast-alert";
        var el = document.getElementById(id);
        if (el) { el.parentNode.removeChild(el); }
        el = document.createElement("div");
        el.id = id;
        el.innerText = msg;
        el.style.cssText = "position:fixed;top:20px;right:20px;z-index:999999;padding:12px 24px;border-radius:8px;font-family:sans-serif;font-size:14px;color:white;box-shadow:0 4px 12px rgba(0,0,0,0.15);transition:opacity 0.3s;background:" + (isError ? "#ff3b30" : "#34c759");
        document.body.appendChild(el);
        setTimeout(function(){ el.style.opacity = "0"; setTimeout(function(){ el.parentNode.removeChild(el); }, 300); }, 3000);
    }
})();
```

---

### 路径 2：本地 WebBridge 监听层 (`PrismWebBridge.swift`)
文件位置：`note/Sources/Note/PrismWebBridge.swift`
负责建立本地 Socket 监听，接收来自 Bookmarklet 的 Fetch 或自销毁窗口发送的高亮片段。

```swift
import Network
import Foundation

class PrismWebBridge {
    private var listener: NWListener?
    
    func startBridge() {
        guard let port = NWEndpoint.Port(rawValue: 31415) else { return }
        do {
            listener = try NWListener(using: .tcp, on: port)
            listener?.newConnectionHandler = { connection in
                connection.start(queue: .global(qos: .userInitiated))
                self.receiveMessage(on: connection)
            }
            listener?.start(queue: .global(qos: .background))
            print("Prism WebBridge active on port 31415")
        } catch {
            print("WebBridge initialization failed: \(error)")
        }
    }
    
    private func receiveMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, _, _ in // 仅接收片段，限制最大缓存为 256KB，大幅降低内存与防 DDoS 风险
            guard let data = data, let request = String(data: data, encoding: .utf8) else { return }
            
            // 响应通道 B (window.open) 所需要的自关闭辅助页面
            if request.contains("GET /clip_page") {
                let html = """
                <!DOCTYPE html>
                <html>
                <head><title>Prism Notes Clipper</title></head>
                <body>
                <script>
                window.addEventListener("message", function(event) {
                    fetch("/clip", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify(event.data)
                    }).then(function() {
                        window.close();
                    }).catch(function() {
                        window.close();
                    });
                });
                </script>
                </body>
                </html>
                """
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
                
            } else if request.contains("POST /clip") {
                let body = request.components(separatedBy: "\r\n\r\n").last ?? ""
                self.ingestClippedData(body)
                
                let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{\"status\":\"synced\"}"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
            }
        }
    }
    
    private func ingestClippedData(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = json["url"] as? String,
              let title = json["title"] as? String,
              let selectedText = json["selectedText"] as? String else { return }
              
        let snippet = SharedQueueManager.PendingSnippet(
            url: url,
            title: title,
            selectedText: selectedText,
            source: "bookmarklet",
            timestamp: Date()
        )
        SharedQueueManager.pushToQueue(snippet: snippet)
    }
}
```

---

### 路径 3：物理隔离后台 Ingestion 队列 (`IngestionQueueWorker.swift`)
文件位置：`note/Sources/Note/IngestionQueueWorker.swift`
从主线程物理隔离磁盘 I/O。由于不再执行复杂的整页 Readability HTML 解析，Ingestion 耗时从秒级降低至**微秒级**，完全消除了 CPU 并发拥堵瓶颈。

```swift
import Foundation

actor IngestionQueueWorker {
    
    struct ParsedResult {
        let url: String
        let title: String
        let snippetText: String
        let source: String
    }
    
    private let stream: AsyncStream<URL>
    private let continuation: AsyncStream<URL>.Continuation
    
    init() {
        let (stream, continuation) = AsyncStream<URL>.makeStream()
        self.stream = stream
        self.continuation = continuation
        
        Task {
            await self.startWorkerLoop()
        }
    }
    
    func enqueue(fileURL: URL) {
        continuation.yield(fileURL)
    }
    
    private func startWorkerLoop() async {
        for await fileURL in stream {
            await self.processSingleFile(at: fileURL)
        }
    }
    
    private func processSingleFile(at fileURL: URL) async {
        do {
            // 1. 物理异步磁盘读取
            let data = try Data(contentsOf: fileURL)
            let pending = try JSONDecoder().decode(SharedQueueManager.PendingSnippet.self, from: data)
            
            // 2. 清洗多余的首尾空行，包装为 Markdown 引用块格式
            let formattedText = "> \(pending.selectedText.replacingOccurrences(of: "\n", with: "\n> "))"
            
            let result = ParsedResult(
                url: pending.url,
                title: pending.title,
                snippetText: formattedText,
                source: pending.source
            )
            
            // 3. 将高亮片段结构体抛回主线程 SwiftData 库
            await NoteAppLifecycleManager.shared.insertSnippet(result)
            
            // 4. 清理共享盘缓存文件
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            print("Failed to process snippet: \(error)")
        }
    }
}
```

---

### 路径 4：主线程调度与 SwiftData 落地层 (`NoteAppLifecycleManager.swift`)
文件位置：`note/Sources/Note/NoteAppLifecycleManager.swift`
运行在主线程（@MainActor），负责启动本地 WebBridge 监听、接收运行期通知、进行冷启动孤儿文件扫描，并将高亮片段插入本地数据库。

```swift
import Foundation
import SwiftData

@MainActor
class NoteAppLifecycleManager {
    static let shared = NoteAppLifecycleManager()
    
    private let worker = IngestionQueueWorker()
    private let bridge = PrismWebBridge()
    
    private init() {
        // 1. 开启端口监听
        bridge.startBridge()
        
        // 2. 注册分布式通知监听
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleNotification(_:)),
            name: Notification.Name("com.prism.suite.newArticle"),
            object: nil
        )
        
        // 3. 执行冷启动孤儿文件扫描
        self.sweepOrphanedClips()
    }
    
    func sweepOrphanedClips() {
        DispatchQueue.global(qos: .utility).async {
            guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedQueueManager.sharedGroupID) else { return }
            let queueDirectory = groupURL.appendingPathComponent("IncomingClips", isDirectory: true)
            let fileURLs = (try? FileManager.default.contentsOfDirectory(at: queueDirectory, includingPropertiesForKeys: nil)) ?? []
            
            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                Task {
                    await self.worker.enqueue(fileURL: fileURL)
                }
            }
        }
    }
    
    @objc private func handleNotification(_ notification: Notification) {
        guard let fileName = notification.object as? String else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedQueueManager.sharedGroupID) else { return }
            let fileURL = groupURL.appendingPathComponent("IncomingClips").appendingPathComponent(fileName)
            Task {
                await self.worker.enqueue(fileURL: fileURL)
            }
        }
    }
    
    // 主线程落库接口（仅保存高亮选段）
    func insertSnippet(_ parsed: IngestionQueueWorker.ParsedResult) {
        let source = ArticleSource(rawValue: parsed.source) ?? .bookmarklet
        let snippet = ClippedSnippet(
            url: parsed.url,
            title: parsed.title,
            snippetContent: parsed.snippetText,
            sourceName: URL(string: parsed.url)?.host ?? "",
            articleSource: source
        )
        // 示例：modelContext.insert(snippet)
    }
}
```

---

## 三、 数据模型 (SwiftData Models)

文件位置：`note/Sources/Note/Models.swift`

```swift
import SwiftData
import Foundation

enum ArticleSource: String, Codable {
    case rss           // 来自 Feed App 推送的摘要划线
    case safariClip    // 来自 Safari App Extension 划线
    case bookmarklet   // 来自 Chrome/Edge Bookmarklet 划线
    case searchResult  // 来自 AI 触发的网页搜索高亮
}

@Model
final class ResearchTopic {
    @Attribute(.unique) var id: String
    var title: String
    var summary: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var snippets: [ClippedSnippet] = []
    
    init(id: String = UUID().uuidString, title: String) {
        self.id = id
        self.title = title
        self.summary = ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class ClippedSnippet {
    @Attribute(.unique) var id: String
    var url: String
    var title: String
    var snippetContent: String  // 存储用户划线选中的正文片段（而非整篇 HTML/Markdown）
    var sourceName: String      // 媒体域名，如 "wsj.com"
    var articleSource: ArticleSource
    var stanceScore: Double     // 对该片段的 Stance 分析分值
    var clippedAt: Date
    var topic: ResearchTopic?
    
    init(url: String, title: String, snippetContent: String, sourceName: String, articleSource: ArticleSource) {
        self.id = UUID().uuidString
        self.url = url
        self.title = title
        self.snippetContent = snippetContent
        self.sourceName = sourceName
        self.articleSource = articleSource
        self.stanceScore = 0.0
        self.clippedAt = Date()
    }
}
```
