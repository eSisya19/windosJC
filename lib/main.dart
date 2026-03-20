import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_windows/webview_windows.dart' as win;

// ─── CONFIG ───────────────────────────────────────────────────────────────────
const String kConfigUrl =
    'https://raw.githubusercontent.com/eSisya19/paratec/refs/heads/main/url_to_jc.txt';
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WebShellApp());
}

class WebShellApp extends StatelessWidget {
  const WebShellApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ParasJC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ShellLoader(),
    );
  }
}

class ShellLoader extends StatefulWidget {
  const ShellLoader({super.key});

  @override
  State<ShellLoader> createState() => _ShellLoaderState();
}

class _ShellLoaderState extends State<ShellLoader> {
  String? _targetUrl;
  String? _error;
  String _version = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchVersion();
    _fetchUrl();
  }

  Future<void> _fetchVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _version = "v${info.version}+${info.buildNumber}");
    } catch (_) {}
  }

  Future<void> _fetchUrl() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse('$kConfigUrl?t=$timestamp');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final url = response.body.trim();
        if (Uri.tryParse(url)?.isAbsolute ?? false) {
          setState(() {
            _targetUrl = url;
            _isLoading = false;
          });
          return;
        }
        throw Exception('Invalid URL in configuration: $url');
      }
      throw Exception('Failed to load config (HTTP ${response.statusCode})');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              if (_version.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(_version, style: const TextStyle(color: Colors.grey)),
              ],
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 60, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Connection Error',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _fetchUrl,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                if (_version.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Text(_version, style: const TextStyle(color: Colors.grey)),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return WebShellHome(url: _targetUrl!, version: _version);
  }
}

class WebShellHome extends StatefulWidget {
  final String url;
  final String version;
  const WebShellHome({super.key, required this.url, required this.version});
  @override
  State<WebShellHome> createState() => _WebShellHomeState();
}

class _WebShellHomeState extends State<WebShellHome> {
  // Mobile Controller
  late final WebViewController _mobileController;
  // Windows Controller
  final win.WebviewController _winController = win.WebviewController();
  
  final bool _isWindows = Platform.isWindows;

  bool _isLoading = true;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String _downloadFileName = '';

  // ── JS injected on every page load (Android Only) ──────────────────────────
  static const String _blobInterceptorJS = r"""
(function() {
  if (window.__flutterDlPatched) return;
  window.__flutterDlPatched = true;

  function sendToFlutter(type, fileName, extra) {
    var payload = JSON.stringify(Object.assign({ type: type, fileName: fileName }, extra));
    var chunkSize = 400000;
    var id = Date.now().toString() + Math.random().toString(36).slice(2);
    var total = Math.ceil(payload.length / chunkSize);
    for (var i = 0; i < total; i++) {
      FlutterDownloadChannel.postMessage(JSON.stringify({
        id: id, chunk: i, total: total,
        data: payload.slice(i * chunkSize, (i + 1) * chunkSize)
      }));
    }
  }

  document.addEventListener('click', function(e) {
    var el = e.target;
    while (el && el.tagName !== 'A') el = el.parentElement;
    if (!el) return;

    var href = el.href || '';
    var dlAttr = el.getAttribute('download');

    if (href.startsWith('blob:')) {
      e.preventDefault();
      var name = dlAttr || ('download_' + Date.now());
      var xhr = new XMLHttpRequest();
      xhr.open('GET', href, true);
      xhr.responseType = 'blob';
      xhr.onload = function() {
        var reader = new FileReader();
        reader.onloadend = function() {
          sendToFlutter('blob', name, { dataUrl: reader.result });
        };
        reader.readAsDataURL(xhr.response);
      };
      xhr.onerror = function() {
        sendToFlutter('blobUrl', name, { url: href });
      };
      xhr.send();
      return;
    }

    if (dlAttr !== null && href && !href.startsWith('javascript:')) {
      e.preventDefault();
      var name2 = dlAttr || href.split('/').pop().split('?')[0] || 'download';
      sendToFlutter('url', name2, { url: href });
    }
  }, true);
})();
""";

  final Map<String, List<MapEntry<int, String>>> _chunks = {};

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      _initWindows();
    } else {
      _requestPermissions();
      _initMobile();
    }
  }

  Future<void> _initWindows() async {
    try {
      await _winController.initialize();
      await _winController.setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
      await _winController.loadUrl(widget.url);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Windows WebView init error: $e');
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [Permission.storage, Permission.manageExternalStorage].request();
    }
  }

  void _initMobile() {
    _mobileController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterDownloadChannel',
        onMessageReceived: (msg) => _onJsMessage(msg.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) {
          setState(() => _isLoading = false);
          _mobileController.runJavaScript(_blobInterceptorJS);
        },
        onWebResourceError: (err) {
          if (err.description.contains('blob:') ||
              err.description.contains('ERR_FILE_NOT_FOUND') ||
              err.description.contains('ERR_UNKNOWN_URL_SCHEME')) return;
          debugPrint('WebView error: ${err.description}');
          setState(() => _isLoading = false);
        },
        onNavigationRequest: (req) {
          if (req.url.startsWith('blob:')) return NavigationDecision.prevent;
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));

    if (_mobileController.platform is AndroidWebViewController) {
      (_mobileController.platform as AndroidWebViewController)
          .setOnShowFileSelector(_handleFileUpload);
    }
  }

  void _onJsMessage(String raw) {
    try {
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      final id = outer['id'] as String;
      final chunk = outer['chunk'] as int;
      final total = outer['total'] as int;
      final data = outer['data'] as String;

      _chunks.putIfAbsent(id, () => []);
      _chunks[id]!.add(MapEntry(chunk, data));

      if (_chunks[id]!.length == total) {
        final sorted = List<MapEntry<int, String>>.from(_chunks.remove(id)!)
          ..sort((a, b) => a.key.compareTo(b.key));
        _processPayload(sorted.map((e) => e.value).join(''));
      }
    } catch (e) {
      debugPrint('JS channel parse error: $e');
    }
  }

  void _processPayload(String payload) {
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final type = map['type'] as String;
      final rawName = (map['fileName'] as String?)?.trim() ?? 'download';
      final fileName = rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      switch (type) {
        case 'blob':
          _saveBlobDownload(fileName, map['dataUrl'] as String);
          break;
        case 'url':
        case 'blobUrl':
          _downloadUrl(map['url'] as String, fileName);
          break;
      }
    } catch (e) {
      debugPrint('Payload error: $e');
    }
  }

  Future<void> _saveBlobDownload(String fileName, String dataUrl) async {
    try {
      setState(() {
        _isDownloading = true;
        _downloadProgress = -1;
        _downloadFileName = fileName;
      });

      final comma = dataUrl.indexOf(',');
      if (comma == -1) throw Exception('Invalid data URL');
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      final path = await _resolveSavePath(fileName);
      await File(path).writeAsBytes(bytes);

      setState(() => _isDownloading = false);
      _showSuccess(fileName, path);
    } catch (e) {
      setState(() => _isDownloading = false);
      _showError(e.toString());
    }
  }

  Future<void> _downloadUrl(String url, [String? name]) async {
    try {
      final uri = Uri.parse(url);
      final fileName = name ??
          (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null) ??
          'download_${DateTime.now().millisecondsSinceEpoch}';

      setState(() {
        _isDownloading = true;
        _downloadProgress = 0;
        _downloadFileName = fileName;
      });

      final savePath = await _resolveSavePath(fileName);
      final res = await http.Request('GET', uri).send();
      final total = res.contentLength ?? 0;
      int received = 0;

      final sink = File(savePath).openWrite();
      await res.stream.map((chunk) {
        received += chunk.length;
        if (total > 0) setState(() => _downloadProgress = received / total);
        return chunk;
      }).pipe(sink);

      setState(() => _isDownloading = false);
      _showSuccess(fileName, savePath);
    } catch (e) {
      setState(() => _isDownloading = false);
      _showError(e.toString());
    }
  }

  Future<List<String>> _handleFileUpload(FileSelectorParams params) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return [];

      final cacheDir = await getTemporaryDirectory();
      final List<String> uris = [];

      for (final file in result.files) {
        if (file.bytes == null && file.path == null) continue;
        final fileName = file.name;
        final cacheFile = File('${cacheDir.path}/$fileName');
        if (file.bytes != null) {
          await cacheFile.writeAsBytes(file.bytes!);
        } else {
          await File(file.path!).copy(cacheFile.path);
        }
        try {
          final contentUri = await _getContentUri(cacheFile.path);
          if (contentUri != null) {
            uris.add(contentUri);
          } else {
            uris.add(cacheFile.path);
          }
        } catch (e) {
          uris.add(cacheFile.path);
        }
      }
      return uris;
    } catch (e) {
      debugPrint('File picker error: $e');
    }
    return [];
  }

  static const _channel = MethodChannel('com.example.webshell/file_provider');

  Future<String?> _getContentUri(String filePath) async {
    try {
      final uri = await _channel.invokeMethod<String>(
        'getContentUri',
        {'path': filePath},
      );
      return uri;
    } catch (e) {
      return null;
    }
  }

  Future<String> _resolveSavePath(String fileName) async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) {
        dir = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    return '${dir.path}/$fileName';
  }

  void _showSuccess(String name, String path) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Saved: $name'),
      action: SnackBarAction(label: 'Open', onPressed: () => OpenFile.open(path)),
      duration: const Duration(seconds: 6),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $msg')));
  }

  @override
  void dispose() {
    if (_isWindows) _winController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (!_isWindows && await _mobileController.canGoBack()) {
              await _mobileController.goBack();
            } else {
              if (mounted) SystemNavigator.pop();
            }
          },
          child: Stack(children: [
            _isWindows 
                ? (_winController.value.isInitialized 
                    ? win.Webview(_winController) 
                    : const Center(child: CircularProgressIndicator()))
                : WebViewWidget(controller: _mobileController),
            if (_isLoading) const LinearProgressIndicator(minHeight: 3),
            if (_isDownloading)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black87,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saving: $_downloadFileName',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value:
                            _downloadProgress >= 0 ? _downloadProgress : null,
                        backgroundColor: Colors.white24,
                        color: Colors.blueAccent,
                      ),
                    ],
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
