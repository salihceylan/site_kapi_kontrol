import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/pdf_logs_service.dart';
import 'package:site_kapi_kontrol/styles/role_theme.dart';

class DoorLogsView extends StatefulWidget {
  const DoorLogsView({
    super.key,
    required this.authService,
  });

  final AuthService authService;

  @override
  State<DoorLogsView> createState() => _DoorLogsViewState();
}

class _DoorLogsViewState extends State<DoorLogsView> {
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm:ss');
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<DoorAccessLogRecord> _logs = [];
  int _totalCount = 0;
  int _page = 1;
  final int _pageSize = 100;

  List<SiteRecord> _sites = [];
  int? _selectedSiteCode;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final sitePage = await widget.authService.listSites(page: 1, pageSize: 100);
      if (mounted) {
        setState(() {
          _sites = sitePage.sites;
          if (_sites.isNotEmpty && _selectedSiteCode == null) {
            _selectedSiteCode = _sites.first.id;
          }
        });
        await _fetchLogs();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _fetchLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final (logPage, error) = await widget.authService.listDoorAccessLogs(
      siteCode: _selectedSiteCode,
      search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
      page: _page,
      pageSize: _pageSize,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (error != null) {
        _errorMessage = error;
      } else if (logPage != null) {
        _logs = logPage.logs;
        _totalCount = logPage.total;
      }
    });
  }

  Future<void> _downloadPdfReport() async {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Raporlanacak geçiş kaydı bulunmuyor.')),
      );
      return;
    }

    String? siteName;
    if (_selectedSiteCode != null) {
      final found = _sites.where((s) => s.id == _selectedSiteCode);
      if (found.isNotEmpty) {
        siteName = found.first.name;
      }
    }

    try {
      await PdfLogsService.printOrShareLogsPdf(
        logs: _logs,
        siteName: siteName,
        startDate: _startDate,
        endDate: _endDate,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulurken hata oluştu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.authService.session?.role;
    final primaryColor = role?.accentColor ?? const Color(0xFF1A237E);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kapı Geçiş & Erişim Logları'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _fetchLogs,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF Raporu İndir / Yazdır',
            onPressed: _downloadPdfReport,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchLogs,
        child: Column(
          children: [
            _buildFilterCard(primaryColor),
            if (_logs.isNotEmpty) _buildSummaryCounters(),
            Expanded(
              child: _buildLogList(primaryColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCard(Color primaryColor) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedSiteCode,
                    decoration: const InputDecoration(
                      labelText: 'Site Seçimi',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Tüm Siteler')),
                      ..._sites.map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedSiteCode = val;
                        _page = 1;
                      });
                      _fetchLogs();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _downloadPdfReport,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('PDF İndir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Kişi, kapı, daire veya site ara...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _fetchLogs();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _fetchLogs(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCounters() {
    final cloudCount = _logs.where((l) => l.triggerType == 'cloud_app').length;
    final localCount = _logs.where((l) => l.triggerType == 'local_wifi').length;
    final guestCount = _logs.where((l) => l.triggerType == 'guest_pass').length;
    final voiceCount = _logs.where((l) => l.triggerType == 'voice').length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _buildChip('Toplam', '$_totalCount', Colors.indigo),
          const SizedBox(width: 6),
          _buildChip('Bulut', '$cloudCount', Colors.blue),
          const SizedBox(width: 6),
          _buildChip('Yerel Wi-Fi', '$localCount', Colors.green),
          const SizedBox(width: 6),
          _buildChip('Misafir', '$guestCount', Colors.orange),
          const SizedBox(width: 6),
          _buildChip('Sesli', '$voiceCount', Colors.purple),
        ],
      ),
    );
  }

  Widget _buildChip(String label, String count, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 11, color: color.shade900),
          ),
          Text(
            count,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(Color primaryColor) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _fetchLogs, child: const Text('Tekrar Dene')),
            ],
          ),
        ),
      );
    }

    if (_logs.isEmpty) {
      return const Center(
        child: Text('Kayıtlı kapı geçiş logu bulunamadı.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: _logs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final log = _logs[index];
        return Card(
          margin: EdgeInsets.zero,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: _triggerTypeColor(log.triggerType).withValues(alpha: 0.15),
              child: Icon(
                _triggerTypeIcon(log.triggerType),
                color: _triggerTypeColor(log.triggerType),
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    log.userName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _triggerTypeColor(log.triggerType).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _triggerTypeColor(log.triggerType).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    log.triggerTypeDisplay,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _triggerTypeColor(log.triggerType),
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.door_front_door_outlined, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      log.doorName,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                    ),
                    if (log.apartmentLabel != null && log.apartmentLabel!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.apartment, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        log.apartmentLabel!,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      _dateFormat.format(log.openedAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    if (log.siteName != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '• ${log.siteName}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _triggerTypeColor(String triggerType) {
    switch (triggerType) {
      case 'voice':
        return Colors.purple;
      case 'local_wifi':
        return Colors.green.shade700;
      case 'guest_pass':
        return Colors.orange.shade800;
      case 'offline_sync':
        return Colors.brown;
      case 'cloud_app':
      default:
        return Colors.blue.shade700;
    }
  }

  IconData _triggerTypeIcon(String triggerType) {
    switch (triggerType) {
      case 'voice':
        return Icons.mic;
      case 'local_wifi':
        return Icons.wifi;
      case 'guest_pass':
        return Icons.qr_code_2;
      case 'offline_sync':
        return Icons.sync;
      case 'cloud_app':
      default:
        return Icons.cloud_outlined;
    }
  }
}
